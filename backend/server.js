require('dotenv').config();

const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const pdfParse = require('pdf-parse');

const app = express();
const PORT = process.env.PORT || 3000;

const upload = multer({ storage: multer.memoryStorage() });

app.use(cors());
app.use(express.json({ limit: '10mb' }));

const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = path.join(DATA_DIR, 'cv.json');

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// ============================================================
// 1. MISTRAL AI (PRIMARNI - besplatno 1B tokena/mjesečno)
// ============================================================

async function callMistral(prompt) {
  const apiKey = process.env.MISTRAL_API_KEY;
  if (!apiKey) {
    throw new Error("MISTRAL_API_KEY nije postavljen u .env datoteci.");
  }

  const url = "https://api.mistral.ai/v1/chat/completions";
  
  console.log('➡️  [Mistral] Pokušavam...');
  
  try {
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json'
      },
      body: JSON.stringify({
        model: "mistral-small-latest",
        messages: [
          { 
            role: "system", 
            content: "You are an expert ATS resume parser. Extract data into strict, valid JSON format matching the requested schema. Return ONLY clean JSON without markdown codeblocks or intro text." 
          },
          { role: "user", content: prompt }
        ],
        max_tokens: 2000,
        temperature: 0.1
      }),
      signal: AbortSignal.timeout(15000)
    });

    const data = await response.json();

    if (!response.ok) {
      const errMsg = data.error?.message || data.error || `HTTP ${response.status}`;
      throw new Error(`Mistral API greška: ${errMsg}`);
    }

    if (data.choices && data.choices[0] && data.choices[0].message) {
      console.log('✅ [Mistral] USPIJEH!');
      return data.choices[0].message.content;
    }

    throw new Error("Mistral vratio neispravan format");
    
  } catch (err) {
    throw new Error(`Mistral ne radi: ${err.message}`);
  }
}

// ============================================================
// 2. HUGGING FACE (FALLBACK - ako Mistral ne radi)
// ============================================================

async function callHuggingFace(prompt) {
  const token = process.env.HF_TOKEN;
  if (!token) throw new Error("HF_TOKEN nije postavljen");

  const providers = process.env.PROVIDER_LIST 
    ? process.env.PROVIDER_LIST.split(',').map(p => p.trim())
    : ["Qwen/Qwen2.5-72B-Instruct:novita", "Qwen/Qwen2.5-72B-Instruct:cerebras"];

  const url = "https://router.huggingface.co/v1/chat/completions";
  let lastError = null;

  for (const provider of providers) {
    try {
      console.log(`➡️  [HF] Pokušavam: ${provider}`);
      const response = await fetch(url, {
        method: 'POST',
        headers: {
          'Authorization': `Bearer ${token}`,
          'Content-Type': 'application/json'
        },
        body: JSON.stringify({
          model: provider,
          messages: [{ role: "user", content: prompt }],
          max_tokens: 2000,
          temperature: 0.1
        }),
        signal: AbortSignal.timeout(15000)
      });

      const data = await response.json();
      if (response.ok && data.choices?.[0]?.message?.content) {
        console.log(`✅ [HF] USPIJEH: ${provider}`);
        return data.choices[0].message.content;
      }
      console.warn(`⚠️  [HF] ${provider} ne radi: ${data.error || 'Nepoznato'}`);
      lastError = new Error(data.error || 'Nepoznato');
    } catch (err) {
      console.warn(`⚠️  [HF] ${provider} greška: ${err.message}`);
      lastError = err;
    }
  }

  throw new Error(`Svi HF provideri neuspješni: ${lastError?.message}`);
}

// ============================================================
// 3. GLAVNI FALLBACK: Mistral -> HF
// ============================================================

async function callAIWithFallback(prompt) {
  try {
    // 1. Prvo probaj Mistral (besplatni, veliki limit)
    return await callMistral(prompt);
  } catch (mistralErr) {
    console.warn(`⚠️  Mistral ne radi: ${mistralErr.message}`);
    console.log(`➡️  Prebacujem na Hugging Face fallback...`);
    
    // 2. Ako Mistral ne radi, probaj HF
    try {
      return await callHuggingFace(prompt);
    } catch (hfErr) {
      throw new Error(`Ni Mistral ni HF ne rade. Mistral: ${mistralErr.message}. HF: ${hfErr.message}`);
    }
  }
}

// ============================================================
// 📄 RUTA ZA UPLOAD PDF
// ============================================================

app.post('/api/cv/upload-pdf', upload.single('file'), async (req, res) => {
  console.log("\n=== 📄 UPLOAD PDF ===");
  
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Nema datoteke.' });
    }

    console.log('📦 PDF primljen, veličina:', req.file.size, 'bytes');

    let text;
    try {
      const data = await pdfParse(req.file.buffer);
      text = data.text;
    } catch (pdfErr) {
      console.error('❌ Greška pri parsiranju PDF-a:', pdfErr);
      return res.status(500).json({ error: 'Problem s čitanjem PDF-a: ' + pdfErr.message });
    }

    if (!text || !text.trim()) {
      return res.status(400).json({ error: 'PDF ne sadrži čitljiv tekst.' });
    }

    console.log(`✅ Tekst izvučen (${text.length} znakova)`);

    const prompt = `You are an expert ATS resume parser. Extract data from this text and convert to JSON.

Format:
{
  "personal": { "name": "", "email": "", "phone": "", "location": "", "linkedin": "", "github": "", "twitter": "", "portfolio": "", "website": "" },
  "summary": "",
  "experience": [{"title": "", "company": "", "start": "", "end": "", "description": ""}],
  "education": [{"degree": "", "institution": "", "year": ""}],
  "skills": [],
  "languages": [],
  "projects": [{"name": "", "description": "", "link": ""}],
  "certificates": [{"name": "", "issuer": "", "date": ""}]
}

Return ONLY valid JSON, no markdown.

Text:
${text}`;

    console.log('⏳ Šaljem AI-ju...');
    const aiResult = await callAIWithFallback(prompt);
    
    const cleaned = aiResult
      .replace(/```json/g, '')
      .replace(/```/g, '')
      .trim();

    try {
      const parsed = JSON.parse(cleaned);
      console.log('✅ PDF uspješno parsiran!');
      console.log(`👤 Ime: ${parsed.personal?.name || 'Nepoznato'}`);
      return res.json(parsed);
    } catch (e) {
      console.error('❌ Neispravan JSON:', e.message);
      
      try {
        const fixed = JSON.parse(
          cleaned
            .replace(/,\s*(\]|\})/g, '$1')
            .replace(/(\{|,)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:/g, '$1"$2":')
        );
        console.log('✅ JSON popravljen!');
        return res.json(fixed);
      } catch (e2) {
        return res.status(500).json({ error: 'AI vratio neispravan JSON format' });
      }
    }

  } catch (err) {
    console.error('💥 Greška:', err);
    res.status(500).json({ error: err.message });
  }
});

// ============================================================
// 📄 RUTA ZA UPLOAD MARKDOWN
// ============================================================

app.post('/api/cv/upload-markdown', upload.single('file'), async (req, res) => {
  console.log("\n=== 📄 UPLOAD MARKDOWN ===");
  
  try {
    if (!req.file) {
      return res.status(400).json({ error: 'Nema datoteke.' });
    }

    const content = req.file.buffer.toString('utf8');
    console.log(`📦 Primljeno ${content.length} znakova`);

    const prompt = `You are an expert ATS resume parser. Extract data from this Markdown CV and convert to JSON.

Format:
{
  "personal": { "name": "", "email": "", "phone": "", "location": "", "linkedin": "", "github": "", "twitter": "", "portfolio": "", "website": "" },
  "summary": "",
  "experience": [{"title": "", "company": "", "start": "", "end": "", "description": ""}],
  "education": [{"degree": "", "institution": "", "year": ""}],
  "skills": [],
  "languages": [],
  "projects": [{"name": "", "description": "", "link": ""}],
  "certificates": [{"name": "", "issuer": "", "date": ""}]
}

Return ONLY valid JSON, no markdown.

CV:
${content}`;

    console.log('⏳ Šaljem AI-ju...');
    const aiResult = await callAIWithFallback(prompt);
    
    const cleaned = aiResult
      .replace(/```json/g, '')
      .replace(/```/g, '')
      .trim();

    try {
      const parsed = JSON.parse(cleaned);
      console.log('✅ Markdown uspješno parsiran!');
      console.log(`👤 Ime: ${parsed.personal?.name || 'Nepoznato'}`);
      return res.json(parsed);
    } catch (e) {
      console.error('❌ Neispravan JSON:', e.message);
      
      try {
        const fixed = JSON.parse(
          cleaned
            .replace(/,\s*(\]|\})/g, '$1')
            .replace(/(\{|,)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:/g, '$1"$2":')
        );
        console.log('✅ JSON popravljen!');
        return res.json(fixed);
      } catch (e2) {
        return res.json({
          personal: { name: '', email: '', phone: '', location: '', linkedin: '', github: '', twitter: '', portfolio: '', website: '' },
          summary: '',
          experience: [],
          education: [],
          skills: [],
          languages: [],
          projects: [],
          certificates: []
        });
      }
    }

  } catch (err) {
    console.error('💥 Greška:', err);
    res.status(500).json({ error: err.message });
  }
});

// ============================================================
// OSTALE RUTE
// ============================================================

app.get('/api/cv', (req, res) => {
  if (fs.existsSync(DATA_FILE)) {
    res.json(JSON.parse(fs.readFileSync(DATA_FILE, 'utf8')));
  } else {
    res.json({ personal: { name: '', email: '', phone: '', location: '', linkedin: '' }, summary: '', experience: [], education: [], skills: [], languages: [], projects: [], certificates: [] });
  }
});

app.post('/api/cv', (req, res) => {
  fs.writeFileSync(DATA_FILE, JSON.stringify(req.body, null, 2));
  res.json({ success: true });
});

app.post('/api/cv/ai-optimize', async (req, res) => {
  try {
    const { text, context } = req.body;
    if (!text) return res.status(400).json({ error: 'Tekst nedostaje.' });

    const prompt = `You are an ATS resume expert. Improve this text: "${text}". Context: ${context}. Return ONLY the improved text, no explanations.`;
    const result = await callAIWithFallback(prompt);
    res.json({ text: result.trim() });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/cv/translate', async (req, res) => {
  try {
    const { cvData, targetLang } = req.body;
    if (!cvData || !targetLang) return res.status(400).json({ error: 'Missing parameters' });

    const isToCroatian = targetLang === 'hr';
    const sourceLang = isToCroatian ? 'English' : 'Croatian';
    const targetLangName = isToCroatian ? 'Croatian' : 'English';

    const prompt = `You are a professional translator. Translate this CV JSON from ${sourceLang} to ${targetLangName}. Translate ONLY text values, not field names, URLs, emails, dates, or numbers. Return ONLY valid JSON, no markdown.\n\nCV: ${JSON.stringify(cvData)}`;

    const result = await callAIWithFallback(prompt);
    const cleaned = result.replace(/```json/g, '').replace(/```/g, '').trim();
    const parsed = JSON.parse(cleaned);
    res.json(parsed);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ============================================================
// 🚀 POKRENI SERVER
// ============================================================

app.listen(PORT, () => {
  console.log(`🚀 Server pokrenut na http://localhost:${PORT}`);
  console.log(`📋 Primarni API: Mistral AI (besplatno 1B tokena/mjesečno)`);
  console.log(`📋 Fallback: Hugging Face`);
  console.log(`📋 PDF endpoint: /api/cv/upload-pdf`);
  console.log(`📋 Markdown endpoint: /api/cv/upload-markdown`);
});