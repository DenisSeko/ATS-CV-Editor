#!/bin/bash

set -e

echo "=============================================="
echo "  ATS CV Editor - Angular 22 (FULL SETUP)"
echo "=============================================="

# ============================================================
# 1. PROVJERA NODE.JS
# ============================================================

if ! command -v node &> /dev/null; then
    echo "❌ Node.js nije instaliran. Molimo instalirajte Node.js (v18.19.0+) i pokušajte ponovo."
    exit 1
fi
echo "✅ Node.js verzija: $(node -v)"

if ! command -v npm &> /dev/null; then
    echo "❌ npm nije instaliran."
    exit 1
fi
echo "✅ npm verzija: $(npm -v)"

# ============================================================
# 2. INSTALACIJA ANGULAR CLI 22
# ============================================================

echo "📦 Instaliram Angular CLI 22 globalno..."
npm install -g @angular/cli@22

# ============================================================
# 3. KREIRANJE ANGULAR PROJEKTA
# ============================================================

echo "🛠️  Kreiram Angular projekt u mapi 'frontend' (verzija 22, standalone)..."
npx @angular/cli@22 new frontend --routing=false --style=scss --skip-tests

cd frontend

# ============================================================
# 4. KONFIGURACIJA .npmrc (allow-scripts)
# ============================================================

echo "allow-scripts=true" > .npmrc

# ============================================================
# 5. INSTALACIJA PAKETA
# ============================================================

echo "📦 Instaliram zone.js..."
npm install zone.js --legacy-peer-deps --no-audit --no-fund

echo "📦 Instaliram Angular Material 22, CDK i Quill WYSIWYG editor..."
npm install @angular/material@22 @angular/cdk@22 html2pdf.js ngx-quill quill --legacy-peer-deps --no-audit --no-fund

echo "📦 Instaliram @angular/build 22..."
npm install @angular/build@22 --legacy-peer-deps --no-audit --no-fund

# Automatsko odobravanje install skripti
if npm approve-scripts --allow-scripts-pending 2>/dev/null; then
    echo "✅ Scripts approved."
else
    echo "ℹ️  npm approve-scripts nije dostupan, preskačem."
fi

cd ..

# ============================================================
# 6. BACKEND (Express + JSON)
# ============================================================

echo "📦 Kreiram dead-simple backend (Express + JSON datoteka)..."
mkdir -p backend/data
mkdir -p backend/data/translate_cache
cd backend

npm init -y > /dev/null 2>&1
npm install express cors multer pdf-parse marked dotenv --legacy-peer-deps --no-audit --no-fund

cd ..

# ============================================================
# 7. KREIRANJE .env DATOTEKE
# ============================================================

cat > backend/.env << 'EOF'
PORT=3000
HF_TOKEN=hf_xxxxxxxxxxxxxxxx
MISTRAL_API_KEY=xxxxxxxxxxxxxxxx
OPENROUTER_API_KEY=sk-or-v1-xxxxxxxxxxxxxxxx
PROVIDER_LIST=Qwen/Qwen2.5-72B-Instruct:novita,Qwen/Qwen2.5-72B-Instruct:cerebras,Qwen/Qwen2.5-72B-Instruct:together
EOF

# ============================================================
# 8. KREIRANJE .gitignore
# ============================================================

cat > .gitignore << 'EOF'
# Node.js
node_modules/
npm-debug.log*
yarn-debug.log*
yarn-error.log*
package-lock.json

# Backend
backend/node_modules/
backend/data/cv.json
backend/data/translate_cache/
backend/.env
backend/*.log

# Frontend
frontend/node_modules/
frontend/.angular/
frontend/dist/
frontend/package-lock.json
frontend/*.log

# IDE
.vscode/
.idea/
*.swp
*.swo

# OS
.DS_Store
Thumbs.db

# Environment
.env
.env.local
EOF

echo "=============================================="
echo "  KREIRANJE IZVORNIH KODOVA..."
echo "=============================================="

# ============================================================
# 9. BACKEND: server.js
# ============================================================

cat > backend/server.js << 'EOF'
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
// 3. OPENROUTER (ZADNJI FALLBACK)
// ============================================================

async function callOpenRouter(prompt) {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) {
    throw new Error("OPENROUTER_API_KEY nije postavljen u .env datoteci.");
  }

  const url = "https://openrouter.ai/api/v1/chat/completions";
  
  try {
    console.log('➡️  [OpenRouter] Pokušavam...');
    const response = await fetch(url, {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${apiKey}`,
        'Content-Type': 'application/json',
        'HTTP-Referer': 'http://localhost:4200',
        'X-Title': 'ATS CV Editor'
      },
      body: JSON.stringify({
        model: "qwen/qwen-2.5-72b-instruct",
        messages: [{ role: "user", content: prompt }],
        max_tokens: 2000,
        temperature: 0.1
      }),
      signal: AbortSignal.timeout(15000)
    });

    const data = await response.json();
    if (response.ok && data.choices?.[0]?.message?.content) {
      console.log('✅ [OpenRouter] USPIJEH!');
      return data.choices[0].message.content;
    }
    throw new Error(`OpenRouter greška: ${data.error || 'Nepoznato'}`);
  } catch (err) {
    throw new Error(`OpenRouter ne radi: ${err.message}`);
  }
}

// ============================================================
// 4. GLAVNI FALLBACK: Mistral -> HF -> OpenRouter
// ============================================================

async function callAIWithFullFallback(prompt) {
  try {
    return await callMistral(prompt);
  } catch (mistralErr) {
    console.warn(`⚠️  Mistral ne radi: ${mistralErr.message}`);
    console.log(`➡️  Prebacujem na Hugging Face fallback...`);
    
    try {
      return await callHuggingFace(prompt);
    } catch (hfErr) {
      console.warn(`⚠️  Hugging Face ne radi: ${hfErr.message}`);
      console.log(`➡️  Prebacujem na OpenRouter fallback...`);
      
      try {
        return await callOpenRouter(prompt);
      } catch (orErr) {
        throw new Error(`Svi provideri neuspješni. Mistral: ${mistralErr.message}. HF: ${hfErr.message}. OpenRouter: ${orErr.message}`);
      }
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
    const aiResult = await callAIWithFullFallback(prompt);
    
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
    const aiResult = await callAIWithFullFallback(prompt);
    
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
// 🌍 PREVOĐENJE CIJELOG CV-a
// ============================================================

const translationCache = new Map();

function createHash(str) {
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    const char = str.charCodeAt(i);
    hash = ((hash << 5) - hash) + char;
    hash = hash & hash;
  }
  return hash.toString(16);
}

function tryFixCommonJsonIssues(jsonString) {
  try {
    const fixed1 = jsonString.replace(/,\s*(\]|\})/g, '$1');
    const fixed2 = fixed1.replace(/(\{|,)\s*([a-zA-Z_][a-zA-Z0-9_]*)\s*:/g, '$1"$2":');
    const fixed3 = fixed2.replace(/'/g, '"');
    return JSON.parse(fixed3);
  } catch (e) {
    console.error('[FIX JSON] Failed:', e.message);
    return null;
  }
}

app.post('/api/cv/translate', async (req, res) => {
  try {
    const { cvData, targetLang } = req.body;
    if (!cvData || !targetLang) {
      return res.status(400).json({ error: 'cvData i targetLang su obavezni parametri' });
    }
    
    const cacheKey = `${targetLang}-${createHash(JSON.stringify(cvData))}`;
    
    if (translationCache.has(cacheKey)) {
      console.log(`[CACHE HIT] ${targetLang}`);
      return res.json(translationCache.get(cacheKey));
    }
    
    console.log(`[CACHE MISS] Prevodim na ${targetLang}...`);

    const isToCroatian = targetLang === 'hr';
    const sourceLang = isToCroatian ? 'English' : 'Croatian';
    const targetLangName = isToCroatian ? 'Croatian' : 'English';
    
    const translatePrompt = `You are a professional translator. Translate ALL text values in this CV JSON from ${sourceLang} to ${targetLangName}. Be concise and efficient.
    
    RULES:
    - Translate EVERY text value, including: summary, skills, languages, experience descriptions, education details, project details, certificate details
    - DO NOT translate: field names, keys, URLs, emails, phone numbers, dates, numbers, programming languages, technical terms, location names
    - Preserve EXACTLY: JSON structure, arrays, objects, field names
    - Return ONLY: valid JSON, no markdown, no explanations
    
    CV JSON (currently in ${sourceLang}):
    ${JSON.stringify(cvData)}`;

    console.log(`⏳ Prevodim...`);
    const translatedText = await callAIWithFullFallback(translatePrompt);
    
    const cleaned = translatedText
      .replace(/```json/g, '')
      .replace(/```/g, '')
      .trim();

    try {
      const translatedJson = JSON.parse(cleaned);
      translationCache.set(cacheKey, translatedJson);
      console.log(`✅ Prevod uspješan!`);
      res.json(translatedJson);
    } catch (parseErr) {
      const fixedJson = tryFixCommonJsonIssues(cleaned);
      if (fixedJson) {
        translationCache.set(cacheKey, fixedJson);
        res.json(fixedJson);
      } else {
        res.status(500).json({ 
          error: 'AI vratio neispravan JSON format. Dobiveni tekst: ' + cleaned.substring(0, 200) + '...'
        });
      }
    }
    
  } catch (err) {
    console.error('[TRANSLATE ERROR]:', err);
    res.status(500).json({ error: 'Greška prilikom prevođenja: ' + err.message });
  }
});

// ============================================================
// 🔥 RUTA ZA ATS OPTIMIZACIJU TEKSTA
// ============================================================

app.post('/api/cv/ai-optimize', async (req, res) => {
  try {
    const { text, context } = req.body;
    if (!text) return res.status(400).json({ error: 'Tekst nedostaje.' });

    const prompt = `You are an ATS resume expert. Improve this text: "${text}". Context: ${context}. Return ONLY the improved text, no explanations.`;
    const result = await callAIWithFullFallback(prompt);
    res.json({ text: result.trim() });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// ============================================================
// 📁 OSNOVNE RUTE (GET, POST, CLEAR CACHE)
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

app.post('/api/cv/clear-cache', (req, res) => {
  translationCache.clear();
  console.log('[CACHE CLEAR] Izbrisano');
  res.json({ success: true, message: 'Cache cleared' });
});

// ============================================================
// 🚀 POKRENI SERVER
// ============================================================

app.listen(PORT, () => {
  console.log(`========================================`);
  console.log(`🚀 ATS CV Editor Backend`);
  console.log(`========================================`);
  console.log(`✅ Server pokrenut na http://localhost:${PORT}`);
  console.log(`📋 Primarni API: Mistral AI (besplatno 1B tokena/mjesečno)`);
  console.log(`📋 Fallback: Hugging Face Router`);
  console.log(`📋 Zadnji fallback: OpenRouter`);
  console.log(`📋 PDF endpoint: /api/cv/upload-pdf`);
  console.log(`📋 Markdown endpoint: /api/cv/upload-markdown`);
  console.log(`========================================`);
});
EOF

# ============================================================
# 10. FRONTEND: MODELS (cv.model.ts)
# ============================================================

mkdir -p frontend/src/app/models
cat > frontend/src/app/models/cv.model.ts << 'EOF'
export interface Personal {
  name: string;
  email: string;
  phone: string;
  location: string;
  linkedin: string;
  github: string;
  twitter: string;
  portfolio: string;
  website: string;
}

export interface Experience {
  title: string;
  company: string;
  start: string;
  end: string;
  description: string;
}

export interface Education {
  degree: string;
  institution: string;
  year: string;
}

export interface Project {
  name: string;
  description: string;
  link: string;
}

export interface Certificate {
  name: string;
  issuer: string;
  date: string;
}

export interface CV {
  personal: Personal;
  summary: string;
  experience: Experience[];
  education: Education[];
  skills: string[];
  languages: string[];
  projects: Project[];
  certificates: Certificate[];
}
EOF

# ============================================================
# 11. FRONTEND: SERVISI (cv.service.ts, theme.service.ts)
# ============================================================

mkdir -p frontend/src/app/services

cat > frontend/src/app/services/cv.service.ts << 'EOF'
import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { CV } from '../models/cv.model';

@Injectable({ providedIn: 'root' })
export class CvService {
  private apiUrl = 'http://localhost:3000/api/cv';

  constructor(private http: HttpClient) {}

  getCV(): Observable<CV> {
    return this.http.get<CV>(this.apiUrl);
  }

  saveCV(cv: CV): Observable<any> {
    return this.http.post(this.apiUrl, cv);
  }

  uploadPdfAndParse(file: File): Observable<CV> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<CV>(`${this.apiUrl}/upload-pdf`, formData);
  }

  uploadMarkdownAndParse(file: File): Observable<CV> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<CV>(`${this.apiUrl}/upload-markdown`, formData);
  }

  optimizeText(text: string, context: string): Observable<{ text: string }> {
    return this.http.post<{ text: string }>(`${this.apiUrl}/ai-optimize`, { text, context });
  }

  translateCV(cv: any, targetLang: 'hr' | 'en'): Observable<CV> {
    return this.http.post<CV>(`${this.apiUrl}/translate`, {
      cvData: cv,
      targetLang
    });
  }
}
EOF

cat > frontend/src/app/services/theme.service.ts << 'EOF'
import { Injectable, Renderer2, RendererFactory2 } from '@angular/core';

@Injectable({ providedIn: 'root' })
export class ThemeService {
  private renderer: Renderer2;
  private darkMode = false;

  constructor(rendererFactory: RendererFactory2) {
    this.renderer = rendererFactory.createRenderer(null, null);
    const saved = localStorage.getItem('theme');
    if (saved === 'dark') {
      this.setDarkMode(true);
    } else {
      this.setDarkMode(false);
    }
  }

  toggleTheme(): void {
    this.setDarkMode(!this.darkMode);
  }

  setDarkMode(enabled: boolean): void {
    this.darkMode = enabled;
    const htmlElement = document.documentElement;

    if (enabled) {
      this.renderer.setStyle(htmlElement, 'color-scheme', 'dark');
      this.renderer.addClass(document.body, 'dark-theme');
      localStorage.setItem('theme', 'dark');
    } else {
      this.renderer.setStyle(htmlElement, 'color-scheme', 'light');
      this.renderer.removeClass(document.body, 'dark-theme');
      localStorage.setItem('theme', 'light');
    }
  }

  isDarkMode(): boolean {
    return this.darkMode;
  }
}
EOF

# ============================================================
# 12. FRONTEND: APP COMPONENT (app.component.ts)
# ============================================================

cat > frontend/src/app/app.component.ts << 'EOF'
import { Component, OnInit, ViewChild, ElementRef, inject, ChangeDetectorRef } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClientModule } from '@angular/common/http';

import { MatToolbarModule } from '@angular/material/toolbar';
import { MatIconModule } from '@angular/material/icon';
import { MatButtonModule } from '@angular/material/button';
import { MatButtonToggleModule } from '@angular/material/button-toggle';
import { MatSlideToggleModule } from '@angular/material/slide-toggle';
import { MatInputModule } from '@angular/material/input';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatExpansionModule } from '@angular/material/expansion';
import { MatCardModule } from '@angular/material/card';
import { MatDividerModule } from '@angular/material/divider';
import { MatSnackBarModule, MatSnackBar } from '@angular/material/snack-bar';
import { MatTooltipModule } from '@angular/material/tooltip';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

import { QuillModule } from 'ngx-quill';

import { CvService } from './services/cv.service';
import { ThemeService } from './services/theme.service';
import { CV } from './models/cv.model';
import html2pdf from 'html2pdf.js';

@Component({
  selector: 'app-root',
  standalone: true,
  templateUrl: './app.component.html',
  styleUrls: ['./app.component.scss'],
  imports: [
    CommonModule,
    FormsModule,
    HttpClientModule,
    MatToolbarModule,
    MatIconModule,
    MatButtonModule,
    MatButtonToggleModule,
    MatSlideToggleModule,
    MatInputModule,
    MatFormFieldModule,
    MatExpansionModule,
    MatCardModule,
    MatDividerModule,
    MatSnackBarModule,
    MatTooltipModule,
    MatProgressSpinnerModule,
    QuillModule,
  ]
})
export class AppComponent implements OnInit {
  @ViewChild('previewElement') previewElement!: ElementRef;

  cv: CV = this.getEmptyCV();
  isLoading = false;
  private saveTimeout: any;
  language: 'hr' | 'en' = 'hr';
  private isTranslating = false;

  quillModules = {
    toolbar: [
      ['bold', 'italic', 'underline', 'strike'],
      ['blockquote', 'code-block'],
      [{ 'header': 1 }, { 'header': 2 }],
      [{ 'list': 'ordered' }, { 'list': 'bullet' }],
      [{ 'script': 'sub' }, { 'script': 'super' }],
      [{ 'indent': '-1' }, { 'indent': '+1' }],
      [{ 'size': ['small', false, 'large', 'huge'] }],
      [{ 'header': [1, 2, 3, 4, 5, 6, false] }],
      [{ 'color': [] }, { 'background': [] }],
      [{ 'font': [] }],
      [{ 'align': [] }],
      ['clean'],
      ['link']
    ]
  };

  private cvService = inject(CvService);
  public themeService = inject(ThemeService);
  private snackBar = inject(MatSnackBar);
  private cdr = inject(ChangeDetectorRef);

  ngOnInit(): void {
    this.loadCV();
  }

  toggleLanguage(newLang: 'hr' | 'en'): void {
    if (newLang === this.language) return;
    if (this.isTranslating || this.isLoading) return;
    this.language = newLang;
    this.translateCV();
  }

  translateCV(): void {
    if (this.isTranslating) return;

    this.isTranslating = true;
    this.isLoading = true;
    this.cdr.detectChanges();

    const snackBarRef = this.snackBar.open(
      `Prevodim CV na ${this.language === 'hr' ? 'hrvatski' : 'engleski'}...`,
      'Molimo pričekajte',
      { duration: 0 }
    );

    this.cvService.translateCV(this.cv, this.language).subscribe({
      next: (translatedCv) => {
        this.cv = JSON.parse(JSON.stringify(translatedCv));
        this.cdr.detectChanges();

        this.cvService.saveCV(this.cv).subscribe({
          next: () => {},
          error: (err) => console.error('Greška pri spremanju:', err)
        });

        this.isTranslating = false;
        this.isLoading = false;
        snackBarRef.dismiss();
        this.snackBar.open(
          `CV preveden na ${this.language === 'hr' ? 'hrvatski' : 'engleski'}`,
          'Zatvori',
          { duration: 3000 }
        );
      },
      error: (err) => {
        console.error('Greška pri prevođenju:', err);
        this.isTranslating = false;
        this.isLoading = false;
        this.cdr.detectChanges();
        snackBarRef.dismiss();
        this.snackBar.open(
          err.error?.error || 'Greška pri prevođenju',
          'OK',
          { duration: 5000 }
        );
      }
    });
  }

  optimizeField(
    context: string,
    currentValue: string,
    callback: (optimized: string) => void
  ): void {
    if (!currentValue || !currentValue.trim()) {
      this.snackBar.open('Polje je prazno, nema se što optimizirati', 'OK', { duration: 3000 });
      return;
    }

    this.snackBar.open('AI optimizira tekst...', 'Molimo pričekajte', { duration: 2000 });

    this.cvService.optimizeText(currentValue, context).subscribe({
      next: (res) => {
        callback(res.text);
        this.onDataChange();
        this.cdr.detectChanges();
        this.snackBar.open('Tekst uspješno optimiziran', 'OK', { duration: 3000 });
      },
      error: (err) => {
        console.error('AI optimizacija greška:', err);
        this.snackBar.open(
          err.error?.error || 'Greška s AI modulom',
          'OK',
          { duration: 4000 }
        );
      }
    });
  }

  onQuillChange(event: any): void {
    this.onDataChange();
  }

  onImportPdf(event: Event): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;

    this.isLoading = true;
    this.cdr.detectChanges();

    this.snackBar.open('AI analizira i parsira vaš PDF...', 'Učitavanje', { duration: 5000 });

    this.cvService.uploadPdfAndParse(file).subscribe({
      next: (parsedCv) => {
        this.cv = parsedCv;
        this.saveCV();
        this.isLoading = false;
        this.cdr.detectChanges();
        this.snackBar.open('PDF uspješno parsiran i učitan u editor', 'Zatvori', { duration: 4000 });
      },
      error: (err) => {
        console.error('PDF parsing greška:', err);
        this.isLoading = false;
        this.cdr.detectChanges();
        this.snackBar.open(
          err.error?.error || 'Greška pri parsiranju PDF-a',
          'OK',
          { duration: 5000 }
        );
      }
    });

    (event.target as HTMLInputElement).value = '';
  }

  onImportMarkdown(event: Event): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;

    this.isLoading = true;
    this.cdr.detectChanges();

    this.snackBar.open('AI analizira Markdown životopis...', 'Učitavanje', { duration: 5000 });

    this.cvService.uploadMarkdownAndParse(file).subscribe({
      next: (parsedCv) => {
        this.cv = parsedCv;
        this.saveCV();
        this.isLoading = false;
        this.cdr.detectChanges();
        this.snackBar.open('Markdown uspješno parsiran i učitan u editor', 'Zatvori', { duration: 4000 });
      },
      error: (err) => {
        console.error('Markdown parsing greška:', err);
        this.isLoading = false;
        this.cdr.detectChanges();
        this.snackBar.open(
          err.error?.error || 'Greška pri parsiranju Markdowna',
          'OK',
          { duration: 5000 }
        );
      }
    });

    (event.target as HTMLInputElement).value = '';
  }

  resetCV(): void {
    const confirmReset = confirm('Jeste li sigurni da želite obrisati cijeli CV? Ova radnja se ne može poništiti.');
    
    if (confirmReset) {
      this.cv = this.getEmptyCV();
      this.saveCV();
      this.cdr.detectChanges();
      this.snackBar.open('CV je uspješno obrisan!', 'OK', { duration: 3000 });
    }
  }

  getEmptyCV(): CV {
    return {
      personal: {
        name: '',
        email: '',
        phone: '',
        location: '',
        linkedin: '',
        github: '',
        twitter: '',
        portfolio: '',
        website: ''
      },
      summary: '',
      experience: [],
      education: [],
      skills: [],
      languages: [],
      projects: [],
      certificates: []
    };
  }

  loadCV(): void {
    this.cvService.getCV().subscribe({
      next: (data) => {
        this.cv = data;
        this.cdr.detectChanges();
      },
      error: () => {
        this.snackBar.open('Greška pri učitavanju CV-a', 'OK', { duration: 3000 });
      }
    });
  }

  onDataChange(): void {
    clearTimeout(this.saveTimeout);
    this.saveTimeout = setTimeout(() => this.saveCV(), 500);
  }

  saveCV(): void {
    this.cvService.saveCV(this.cv).subscribe({
      next: () => {},
      error: () => {
        this.snackBar.open('Greška pri spremanju', 'OK', { duration: 3000 });
      }
    });
  }

  onImportJson(event: Event): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;

    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        this.cv = JSON.parse(e.target?.result as string);
        this.saveCV();
        this.cdr.detectChanges();
        this.snackBar.open('CV uspješno uvezen', 'OK', { duration: 3000 });
      } catch {
        this.snackBar.open('Neispravan JSON format', 'OK', { duration: 3000 });
      }
    };
    reader.readAsText(file);
    (event.target as HTMLInputElement).value = '';
  }

  exportJson(): void {
    const blob = new Blob([JSON.stringify(this.cv, null, 2)], { type: 'application/json' });
    const url = URL.createObjectURL(blob);
    const a = document.createElement('a');
    a.href = url;
    a.download = `cv-${new Date().toISOString().split('T')[0]}.json`;
    a.click();
    URL.revokeObjectURL(url);
  }

  exportPdf(): void {
    const element = this.previewElement.nativeElement;
    const fileName = this.cv.personal.name
      ? `${this.cv.personal.name.replace(/\s+/g, '_')}_CV`
      : 'CV';

    const opt = {
      margin: 0.5,
      filename: `${fileName}.pdf`,
      image: { type: 'jpeg' as const, quality: 0.98 },
      html2canvas: { scale: 2, letterRendering: true, useCORS: true },
      jsPDF: { unit: 'in', format: 'a4', orientation: 'portrait' as const }
    };

    html2pdf().set(opt).from(element).save();
  }

  addItem(array: keyof CV, template: any): void {
    (this.cv[array] as any[]).push(template);
    this.onDataChange();
    this.cdr.detectChanges();
  }

  removeItem(array: keyof CV, index: number): void {
    (this.cv[array] as any[]).splice(index, 1);
    this.onDataChange();
    this.cdr.detectChanges();
  }

  trackByIndex(index: number): number { return index; }

  addSkill(): void {
    this.cv.skills.push('');
    this.onDataChange();
    this.cdr.detectChanges();
  }

  removeSkill(index: number): void {
    this.cv.skills.splice(index, 1);
    this.onDataChange();
    this.cdr.detectChanges();
  }

  addLanguage(): void {
    this.cv.languages.push('');
    this.onDataChange();
    this.cdr.detectChanges();
  }

  removeLanguage(index: number): void {
    this.cv.languages.splice(index, 1);
    this.onDataChange();
    this.cdr.detectChanges();
  }

  getLabel(key: string): string {
    const labels: Record<string, Record<'hr' | 'en', string>> = {
      title: { hr: 'ATS CV Editor', en: 'ATS CV Editor' },
      exportJson: { hr: 'Izvezi JSON', en: 'Export JSON' },
      exportPdf: { hr: 'Generiraj PDF', en: 'Generate PDF' },
      importJson: { hr: 'Uvezi JSON', en: 'Import JSON' },
      importPdf: { hr: 'AI Uvoz iz PDF-a', en: 'AI Import from PDF' },
      importMarkdown: { hr: 'AI Uvoz iz Markdowna', en: 'AI Import from Markdown' },
      deleteCV: { hr: 'Obriši CV', en: 'Delete CV' },
      editCV: { hr: 'Uredi CV', en: 'Edit CV' },
      personalInfo: { hr: 'Osobni podaci', en: 'Personal Info' },
      fullName: { hr: 'Ime i prezime', en: 'Full Name' },
      email: { hr: 'Email', en: 'Email' },
      phone: { hr: 'Telefon', en: 'Phone' },
      location: { hr: 'Lokacija', en: 'Location' },
      linkedin: { hr: 'LinkedIn URL', en: 'LinkedIn URL' },
      github: { hr: 'GitHub URL', en: 'GitHub URL' },
      twitter: { hr: 'Twitter / X URL', en: 'Twitter / X URL' },
      portfolio: { hr: 'Portfolio URL', en: 'Portfolio URL' },
      website: { hr: 'Web stranica', en: 'Website URL' },
      summary: { hr: 'Sažetak', en: 'Summary' },
      professionalSummary: { hr: 'Profesionalni sažetak', en: 'Professional Summary' },
      aiImproveSummary: { hr: 'AI Poboljšaj sažetak', en: 'AI Improve Summary' },
      workExperience: { hr: 'Radno iskustvo', en: 'Work Experience' },
      jobTitle: { hr: 'Naziv radnog mjesta', en: 'Job Title' },
      company: { hr: 'Tvrtka', en: 'Company' },
      start: { hr: 'Početak', en: 'Start' },
      end: { hr: 'Kraj', en: 'End' },
      description: { hr: 'Opis i postignuća', en: 'Description & Achievements' },
      aiOptimizeJob: { hr: 'AI Optimiziraj opis', en: 'AI Optimize Description' },
      addExperience: { hr: '+ Dodaj iskustvo', en: '+ Add Experience' },
      education: { hr: 'Obrazovanje', en: 'Education' },
      degree: { hr: 'Stupanj / naziv', en: 'Degree' },
      institution: { hr: 'Institucija', en: 'Institution' },
      year: { hr: 'Godina', en: 'Year' },
      addEducation: { hr: '+ Dodaj obrazovanje', en: '+ Add Education' },
      projects: { hr: 'Projekti', en: 'Projects' },
      projectName: { hr: 'Naziv projekta', en: 'Project Name' },
      projectDescription: { hr: 'Opis', en: 'Description' },
      link: { hr: 'Link', en: 'URL' },
      addProject: { hr: '+ Dodaj projekt', en: '+ Add Project' },
      certificates: { hr: 'Certifikati', en: 'Certificates' },
      certificateName: { hr: 'Naziv certifikata', en: 'Certificate Name' },
      issuer: { hr: 'Izdavatelj', en: 'Issuer' },
      date: { hr: 'Datum', en: 'Date' },
      addCertificate: { hr: '+ Dodaj certifikat', en: '+ Add Certificate' },
      skills: { hr: 'Vještine', en: 'Skills' },
      skill: { hr: 'Vještina', en: 'Skill' },
      addSkill: { hr: '+ Dodaj vještinu', en: '+ Add Skill' },
      languages: { hr: 'Jezici', en: 'Languages' },
      language: { hr: 'Jezik', en: 'Language' },
      addLanguage: { hr: '+ Dodaj jezik', en: '+ Add Language' },
      preview: { hr: 'Pregled (ATS friendly)', en: 'Preview (ATS friendly)' },
      remove: { hr: 'Ukloni', en: 'Remove' },
      processing: { hr: 'AI transformira PDF...', en: 'AI processing PDF...' }
    };

    return labels[key]?.[this.language] || key;
  }
}
EOF

# ============================================================
# 13. FRONTEND: APP COMPONENT HTML (app.component.html)
# ============================================================

cat > frontend/src/app/app.component.html << 'EOF'
<mat-toolbar color="primary" class="toolbar">
  <span class="title">{{ getLabel('title') }}</span>
  <span class="spacer"></span>

  <mat-button-toggle-group
    [value]="language"
    (change)="toggleLanguage($event.value)"
    class="lang-toggle"
    hideSingleSelectionIndicator
  >
    <mat-button-toggle value="hr" matTooltip="Hrvatski / Croatian">HR</mat-button-toggle>
    <mat-button-toggle value="en" matTooltip="English">EN</mat-button-toggle>
  </mat-button-toggle-group>

  <button mat-icon-button (click)="exportJson()" [matTooltip]="getLabel('exportJson')">
    <mat-icon>download</mat-icon>
  </button>
  <button mat-icon-button (click)="exportPdf()" [matTooltip]="getLabel('exportPdf')">
    <mat-icon>picture_as_pdf</mat-icon>
  </button>

  <label mat-icon-button [matTooltip]="getLabel('importJson')" style="cursor: pointer;">
    <mat-icon>upload_file</mat-icon>
    <input type="file" accept=".json" (change)="onImportJson($event)" style="display:none">
  </label>

  <label mat-icon-button [matTooltip]="getLabel('importPdf')" style="cursor: pointer; color: #ffeb3b;">
    <mat-icon>auto_awesome</mat-icon>
    <input type="file" accept=".pdf" (change)="onImportPdf($event)" style="display:none">
  </label>

  <label mat-icon-button [matTooltip]="getLabel('importMarkdown')" style="cursor: pointer; color: #2196f3;">
    <mat-icon>description</mat-icon>
    <input type="file" accept=".md,.markdown,.txt" (change)="onImportMarkdown($event)" style="display:none">
  </label>

  <button mat-icon-button (click)="resetCV()" [matTooltip]="getLabel('deleteCV')" style="color: #ff4444;">
    <mat-icon>delete_forever</mat-icon>
  </button>

  <mat-slide-toggle
    [checked]="themeService.isDarkMode()"
    (toggleChange)="themeService.toggleTheme()"
    class="theme-toggle"
  >
    {{ themeService.isDarkMode() ? '🌙' : '☀️' }}
  </mat-slide-toggle>
</mat-toolbar>

<div class="spinner-overlay" *ngIf="isLoading">
  <mat-spinner></mat-spinner>
  <p>{{ getLabel('processing') }}</p>
</div>

<div class="main-container">
  <div class="editor-panel">
    <h2>{{ getLabel('editCV') }}</h2>

    <!-- OSOBNI PODACI -->
    <mat-expansion-panel expanded>
      <mat-expansion-panel-header>{{ getLabel('personalInfo') }}</mat-expansion-panel-header>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('fullName') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.name" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('email') }}</mat-label>
        <input matInput type="email" [(ngModel)]="cv.personal.email" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('phone') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.phone" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('location') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.location" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('linkedin') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.linkedin" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('github') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.github" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('twitter') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.twitter" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('portfolio') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.portfolio" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>{{ getLabel('website') }}</mat-label>
        <input matInput [(ngModel)]="cv.personal.website" (ngModelChange)="onDataChange()">
      </mat-form-field>
    </mat-expansion-panel>

    <!-- SAŽETAK - QUILL EDITOR -->
    <mat-expansion-panel>
      <mat-expansion-panel-header>{{ getLabel('summary') }}</mat-expansion-panel-header>
      <div class="ai-field-container">
        <quill-editor
          [(ngModel)]="cv.summary"
          (onContentChanged)="onQuillChange($event)"
          [modules]="quillModules"
          placeholder="{{ getLabel('professionalSummary') }}"
          class="full-width quill-editor"
        ></quill-editor>
        <button
          mat-mini-fab
          color="accent"
          class="ai-inline-btn"
          [matTooltip]="getLabel('aiImproveSummary')"
          (click)="optimizeField('Profesionalni sažetak / Professional Summary', cv.summary, (val) => cv.summary = val)"
        >
          <mat-icon>auto_awesome</mat-icon>
        </button>
      </div>
    </mat-expansion-panel>

    <!-- RADNO ISKUSTVO -->
    <mat-expansion-panel>
      <mat-expansion-panel-header>{{ getLabel('workExperience') }}</mat-expansion-panel-header>
      <div *ngFor="let exp of cv.experience; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('jobTitle') }}</mat-label>
          <input matInput [(ngModel)]="exp.title" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('company') }}</mat-label>
          <input matInput [(ngModel)]="exp.company" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <div class="row-gap">
          <mat-form-field appearance="fill" class="flex-half">
            <mat-label>{{ getLabel('start') }}</mat-label>
            <input matInput [(ngModel)]="exp.start" (ngModelChange)="onDataChange()">
          </mat-form-field>
          <mat-form-field appearance="fill" class="flex-half">
            <mat-label>{{ getLabel('end') }}</mat-label>
            <input matInput [(ngModel)]="exp.end" (ngModelChange)="onDataChange()">
          </mat-form-field>
        </div>
        <div class="ai-field-container">
          <quill-editor
            [(ngModel)]="exp.description"
            (onContentChanged)="onQuillChange($event)"
            [modules]="quillModules"
            placeholder="{{ getLabel('description') }}"
            class="full-width quill-editor"
          ></quill-editor>
          <button
            mat-mini-fab
            color="accent"
            class="ai-inline-btn"
            [matTooltip]="getLabel('aiOptimizeJob')"
            (click)="optimizeField('Opis posla za poziciju ' + exp.title, exp.description, (val) => exp.description = val)"
          >
            <mat-icon>auto_awesome</mat-icon>
          </button>
        </div>
        <button mat-raised-button color="warn" (click)="removeItem('experience', i)">{{ getLabel('remove') }}</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('experience', { title:'', company:'', start:'', end:'', description:'' })">
        + {{ getLabel('addExperience') }}
      </button>
    </mat-expansion-panel>

    <!-- OBRAZOVANJE -->
    <mat-expansion-panel>
      <mat-expansion-panel-header>{{ getLabel('education') }}</mat-expansion-panel-header>
      <div *ngFor="let edu of cv.education; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('degree') }}</mat-label>
          <input matInput [(ngModel)]="edu.degree" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('institution') }}</mat-label>
          <input matInput [(ngModel)]="edu.institution" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('year') }}</mat-label>
          <input matInput [(ngModel)]="edu.year" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-raised-button color="warn" (click)="removeItem('education', i)">{{ getLabel('remove') }}</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('education', { degree:'', institution:'', year:'' })">
        + {{ getLabel('addEducation') }}
      </button>
    </mat-expansion-panel>

    <!-- PROJEKTI -->
    <mat-expansion-panel>
      <mat-expansion-panel-header>{{ getLabel('projects') }}</mat-expansion-panel-header>
      <div *ngFor="let proj of cv.projects; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('projectName') }}</mat-label>
          <input matInput [(ngModel)]="proj.name" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('projectDescription') }}</mat-label>
          <textarea matInput rows="2" [(ngModel)]="proj.description" (ngModelChange)="onDataChange()"></textarea>
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('link') }}</mat-label>
          <input matInput [(ngModel)]="proj.link" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-raised-button color="warn" (click)="removeItem('projects', i)">{{ getLabel('remove') }}</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('projects', { name:'', description:'', link:'' })">
        + {{ getLabel('addProject') }}
      </button>
    </mat-expansion-panel>

    <!-- CERTIFIKATI -->
    <mat-expansion-panel>
      <mat-expansion-panel-header>{{ getLabel('certificates') }}</mat-expansion-panel-header>
      <div *ngFor="let cert of cv.certificates; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('certificateName') }}</mat-label>
          <input matInput [(ngModel)]="cert.name" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('issuer') }}</mat-label>
          <input matInput [(ngModel)]="cert.issuer" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>{{ getLabel('date') }}</mat-label>
          <input matInput [(ngModel)]="cert.date" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-raised-button color="warn" (click)="removeItem('certificates', i)">{{ getLabel('remove') }}</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('certificates', { name:'', issuer:'', date:'' })">
        + {{ getLabel('addCertificate') }}
      </button>
    </mat-expansion-panel>

    <!-- VJEŠTINE - QUILL EDITOR -->
    <mat-expansion-panel>
      <mat-expansion-panel-header>{{ getLabel('skills') }}</mat-expansion-panel-header>
      <div *ngFor="let skill of cv.skills; let i = index" class="chip-input-row">
        <quill-editor
          [(ngModel)]="cv.skills[i]"
          (onContentChanged)="onQuillChange($event)"
          [modules]="quillModules"
          [placeholder]="getLabel('skill') + ' #' + (i+1)"
          class="full-width quill-editor"
          style="flex: 1;"
        ></quill-editor>
        <button mat-icon-button color="warn" (click)="removeSkill(i)">
          <mat-icon>close</mat-icon>
        </button>
      </div>
      <button mat-raised-button color="primary" (click)="addSkill()">+ {{ getLabel('addSkill') }}</button>
    </mat-expansion-panel>

    <!-- JEZICI - QUILL EDITOR -->
    <mat-expansion-panel>
      <mat-expansion-panel-header>{{ getLabel('languages') }}</mat-expansion-panel-header>
      <div *ngFor="let lang of cv.languages; let i = index" class="chip-input-row">
        <quill-editor
          [(ngModel)]="cv.languages[i]"
          (onContentChanged)="onQuillChange($event)"
          [modules]="quillModules"
          [placeholder]="getLabel('language') + ' #' + (i+1)"
          class="full-width quill-editor"
          style="flex: 1;"
        ></quill-editor>
        <button mat-icon-button color="warn" (click)="removeLanguage(i)">
          <mat-icon>close</mat-icon>
        </button>
      </div>
      <button mat-raised-button color="primary" (click)="addLanguage()">+ {{ getLabel('addLanguage') }}</button>
    </mat-expansion-panel>
  </div>

  <div class="preview-panel">
    <h2>{{ getLabel('preview') }}</h2>
    <div class="preview-wrapper">
      <div #previewElement id="cvPreview" class="cv-paper">
        <h1>{{ cv.personal.name || getLabel('fullName') }}</h1>
        <div class="contact-line">
          <span *ngIf="cv.personal.email">{{ cv.personal.email }}</span>
          <span *ngIf="cv.personal.phone"> | {{ cv.personal.phone }}</span>
          <span *ngIf="cv.personal.location"> | {{ cv.personal.location }}</span>
          <span *ngIf="cv.personal.linkedin"> | <a [href]="cv.personal.linkedin" target="_blank">LinkedIn</a></span>
          <span *ngIf="cv.personal.github"> | <a [href]="cv.personal.github" target="_blank">GitHub</a></span>
          <span *ngIf="cv.personal.twitter"> | <a [href]="cv.personal.twitter" target="_blank">Twitter</a></span>
          <span *ngIf="cv.personal.portfolio"> | <a [href]="cv.personal.portfolio" target="_blank">Portfolio</a></span>
          <span *ngIf="cv.personal.website"> | <a [href]="cv.personal.website" target="_blank">Website</a></span>
        </div>

        <h2 *ngIf="cv.summary">{{ getLabel('summary') }}</h2>
        <p *ngIf="cv.summary" [innerHTML]="cv.summary"></p>

        <h2 *ngIf="cv.experience.length">{{ getLabel('workExperience') }}</h2>
        <div *ngFor="let exp of cv.experience" class="preview-item">
          <div class="item-header">
            <strong>{{ exp.title }}</strong> – {{ exp.company }}
            <span class="item-date">{{ exp.start }} – {{ exp.end }}</span>
          </div>
          <p *ngIf="exp.description" [innerHTML]="exp.description"></p>
        </div>

        <h2 *ngIf="cv.education.length">{{ getLabel('education') }}</h2>
        <div *ngFor="let edu of cv.education" class="preview-item">
          <div class="item-header">
            <strong>{{ edu.degree }}</strong> – {{ edu.institution }}
            <span class="item-date">{{ edu.year }}</span>
          </div>
        </div>

        <h2 *ngIf="cv.projects.length">{{ getLabel('projects') }}</h2>
        <div *ngFor="let proj of cv.projects" class="preview-item">
          <div class="item-header">
            <strong>{{ proj.name }}</strong>
            <span *ngIf="proj.link"> | <a [href]="proj.link" target="_blank">Link</a></span>
          </div>
          <p *ngIf="proj.description">{{ proj.description }}</p>
        </div>

        <h2 *ngIf="cv.certificates.length">{{ getLabel('certificates') }}</h2>
        <div *ngFor="let cert of cv.certificates" class="preview-item">
          <div class="item-header">
            <strong>{{ cert.name }}</strong> – {{ cert.issuer }}
            <span class="item-date">{{ cert.date }}</span>
          </div>
        </div>

        <h2 *ngIf="cv.skills.length">{{ getLabel('skills') }}</h2>
        <div *ngFor="let skill of cv.skills" class="preview-item">
          <p [innerHTML]="skill"></p>
        </div>

        <h2 *ngIf="cv.languages.length">{{ getLabel('languages') }}</h2>
        <div *ngFor="let lang of cv.languages" class="preview-item">
          <p [innerHTML]="lang"></p>
        </div>
      </div>
    </div>
  </div>
</div>
EOF

# ============================================================
# 14. FRONTEND: APP COMPONENT SCSS (app.component.scss)
# ============================================================

cat > frontend/src/app/app.component.scss << 'EOF'
:host {
  display: block;
  height: 100vh;
  background: #f5f7fa;
  transition: background 0.3s ease;
}

.toolbar {
  background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
  color: #fff;
  padding: 0 24px;
  box-shadow: 0 2px 12px rgba(0,0,0,0.15);

  .title { 
    font-weight: 600; 
    font-size: 1.3rem;
    letter-spacing: -0.5px;
    color: #fff;
  }
  .spacer { flex: 1 1 auto; }
  
  .theme-toggle {
    margin-left: 8px;
    .mat-slide-toggle-thumb {
      background-color: #f5f7fa;
    }
    .mat-slide-toggle-bar {
      background-color: rgba(255,255,255,0.3);
    }
    &.mat-checked .mat-slide-toggle-bar {
      background-color: #4a9eff;
    }
  }

  .lang-toggle {
    margin-right: 16px;
    border-radius: 24px;
    overflow: hidden;
    background: rgba(255, 255, 255, 0.08);
    
    mat-button-toggle {
      min-width: 44px;
      font-size: 0.85rem;
      font-weight: 600;
      background: transparent;
      color: rgba(255,255,255,0.7);
      border: none;
      transition: all 0.2s;
      
      &.mat-button-toggle-checked {
        background: #fff;
        color: #1a1a2e;
        border-radius: 20px;
        box-shadow: 0 2px 8px rgba(0,0,0,0.2);
      }
      
      &:hover:not(.mat-button-toggle-checked) {
        color: #fff;
        background: rgba(255,255,255,0.1);
      }
    }
  }
}

.main-container {
  display: flex;
  flex-direction: row;
  gap: 24px;
  padding: 24px;
  height: calc(100vh - 64px);
  overflow: hidden;

  @media (max-width: 800px) {
    flex-direction: column;
    gap: 16px;
    padding: 16px;
  }

  .editor-panel {
    flex: 1 1 50%;
    overflow-y: auto;
    padding-right: 16px;
    height: 100%;
    background: transparent;

    h2 {
      margin-top: 0;
      font-size: 1.4rem;
      font-weight: 600;
      color: rgba(0, 0, 0, 0.87);
      margin-bottom: 16px;
    }

    .full-width { width: 100%; }

    .array-item {
      margin-bottom: 20px;
      padding: 18px;
      background: rgba(255, 255, 255, 0.85);
      backdrop-filter: blur(4px);
      border-radius: 16px;
      transition: background 0.3s, box-shadow 0.2s;
      box-shadow: 0 1px 4px rgba(0,0,0,0.04);
      border: 1px solid rgba(255,255,255,0.2);
    }

    .chip-input-row {
      display: flex;
      align-items: flex-start;
      gap: 8px;
      margin-bottom: 12px;

      .quill-editor {
        flex: 1;
        min-width: 0;

        .ql-container {
          min-height: 60px;
          border-radius: 0 0 4px 4px;
        }
        
        .ql-toolbar {
          border-radius: 4px 4px 0 0;
        }
      }

      mat-form-field {
        flex: 1;
      }
    }

    mat-divider { 
      margin: 16px 0; 
      opacity: 0.3;
    }
    
    mat-form-field {
      margin-bottom: 12px;
    }
  }

  .preview-panel {
    flex: 1 1 50%;
    overflow-y: auto;
    padding-left: 16px;
    height: 100%;

    h2 {
      margin-top: 0;
      font-size: 1.4rem;
      font-weight: 600;
      color: rgba(0, 0, 0, 0.87);
      margin-bottom: 16px;
    }

    .preview-wrapper {
      background: white;
      border-radius: 16px;
      padding: 32px;
      box-shadow: 0 8px 32px rgba(0,0,0,0.06);
      transition: background 0.3s, box-shadow 0.3s;
      min-height: 100%;
      border: 1px solid rgba(0,0,0,0.02);
    }
  }
}

.row-gap {
  display: flex;
  gap: 12px;
  .flex-half {
    flex: 1;
  }
}

.cv-paper {
  font-family: Arial, Helvetica, sans-serif;
  line-height: 1.6;
  color: #1e1e1e;
  background: white;
  padding: 20px;
  border: 1px solid #e8e8e8;
  border-radius: 8px;

  h1 {
    font-size: 26px;
    margin: 0 0 4px 0;
    font-weight: 700;
  }
  .contact-line {
    font-size: 14px;
    color: #444;
    margin-bottom: 16px;
    a { color: #1a73e8; text-decoration: none; }
  }
  h2 {
    font-size: 18px;
    margin: 20px 0 8px 0;
    border-bottom: 1px solid #ccc;
    padding-bottom: 4px;
    font-weight: 600;
  }
  .preview-item {
    margin-bottom: 12px;
    .item-header {
      font-weight: 500;
      .item-date {
        float: right;
        font-weight: 400;
        color: #555;
      }
    }
    p {
      margin: 4px 0 0 0;
      font-size: 14px;
    }
  }
}

.quill-editor {
  .ql-container {
    min-height: 120px;
    border-radius: 0 0 4px 4px;
    font-size: 14px;
    font-family: inherit;
    background: white;
  }
  
  .ql-toolbar {
    border-radius: 4px 4px 0 0;
    background: rgba(255, 255, 255, 0.05);
    border-color: rgba(0, 0, 0, 0.12);
    border: 1px solid rgba(0, 0, 0, 0.12);
    border-bottom: none;
  }

  .ql-container {
    border: 1px solid rgba(0, 0, 0, 0.12);
    border-top: none;
  }

  .array-item & {
    .ql-toolbar {
      background: rgba(255, 255, 255, 0.3);
    }
    .ql-container {
      background: rgba(255, 255, 255, 0.5);
    }
  }
}

.ai-field-container {
  display: flex;
  align-items: flex-start;
  gap: 12px;
  width: 100%;
  
  .quill-editor {
    flex: 1;
    min-width: 0;
  }
  
  .ai-inline-btn {
    margin-top: 4px;
    background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
    color: white;
    flex-shrink: 0;
    box-shadow: 0 2px 8px rgba(102, 126, 234, 0.3);
    transition: transform 0.2s, box-shadow 0.2s;
    
    &:hover {
      transform: translateY(-2px);
      box-shadow: 0 4px 12px rgba(102, 126, 234, 0.4);
    }
  }
}

body.dark-theme {
  background: #0d1117;
  color: #e6edf3;

  .main-container { background: #0d1117; }

  .toolbar {
    background: linear-gradient(135deg, #161b22 0%, #0d1117 100%);
    border-bottom: 1px solid #30363d;
    
    .title { color: #f0f6fc; }
    
    .lang-toggle {
      background: rgba(255, 255, 255, 0.06);
      
      mat-button-toggle {
        color: rgba(255,255,255,0.6);
        &.mat-button-toggle-checked {
          background: #238636;
          color: #fff;
          box-shadow: 0 2px 8px rgba(35,134,54,0.3);
        }
        &:hover:not(.mat-button-toggle-checked) {
          color: #fff;
          background: rgba(255,255,255,0.08);
        }
      }
    }
    
    .theme-toggle {
      .mat-slide-toggle-thumb {
        background-color: #f0f6fc;
      }
      .mat-slide-toggle-bar {
        background-color: rgba(255,255,255,0.2);
      }
      &.mat-checked .mat-slide-toggle-bar {
        background-color: #238636;
      }
    }
  }

  .editor-panel {
    h2 { color: #f0f6fc; }
    
    .array-item {
      background: rgba(255,255,255,0.04);
      border: 1px solid rgba(255,255,255,0.06);
      backdrop-filter: none;
      box-shadow: 0 1px 4px rgba(0,0,0,0.3);
    }
    
    .chip-input-row {
      .quill-editor {
        .ql-toolbar {
          background: #0d1117;
          border-color: #30363d;
        }
        .ql-container {
          background: #161b22;
          border-color: #30363d;
          color: #e6edf3;
        }
      }
    }

    mat-form-field {
      .mat-form-field-label {
        color: rgba(255,255,255,0.7);
      }
      .mat-form-field-outline {
        color: rgba(255,255,255,0.2);
      }
      .mat-input-element {
        color: #f0f6fc;
      }
    }
    
    mat-divider { 
      border-top-color: rgba(255,255,255,0.08);
      opacity: 1;
    }
  }

  .preview-panel {
    h2 { color: #f0f6fc; }
    
    .preview-wrapper {
      background: #161b22;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
      border: 1px solid #30363d;
    }
  }

  .cv-paper {
    background: #161b22;
    color: #e6edf3;
    border-color: #30363d;
    
    h1 { color: #f0f6fc; }
    h2 { 
      border-bottom-color: #30363d;
      color: #f0f6fc;
    }
    .contact-line {
      color: #8b949e;
      a { color: #58a6ff; }
    }
    .item-date { color: #8b949e; }
    a { color: #58a6ff; }
  }

  .quill-editor {
    .ql-toolbar {
      background: #0d1117;
      border-color: #30363d;
      
      .ql-stroke {
        stroke: #8b949e;
      }
      
      .ql-fill {
        fill: #8b949e;
      }
      
      .ql-picker {
        color: #8b949e;
      }
      
      .ql-picker-label:hover,
      .ql-picker-item:hover {
        color: #f0f6fc;
      }
      
      .ql-picker-options {
        background: #161b22;
        border-color: #30363d;
      }
    }
    
    .ql-container {
      background: #161b22;
      border-color: #30363d;
      color: #e6edf3;
    }
    
    .ql-editor {
      color: #e6edf3;
      
      &.ql-blank::before {
        color: #8b949e;
      }
    }
  }

  mat-expansion-panel {
    background: #161b22 !important;
    color: #e6edf3 !important;
    
    .mat-expansion-panel-header {
      background: transparent !important;
      color: #f0f6fc !important;
      
      &:hover {
        background: rgba(255,255,255,0.03) !important;
      }
    }
    
    .mat-expansion-indicator::after {
      color: #8b949e;
    }
  }

  ::-webkit-scrollbar-track {
    background: #0d1117;
  }
  ::-webkit-scrollbar-thumb {
    background: rgba(255,255,255,0.15);
    
    &:hover {
      background: rgba(255,255,255,0.25);
    }
  }

  .ai-inline-btn {
    background: linear-gradient(135deg, #238636 0%, #1a7a2e 100%) !important;
    box-shadow: 0 2px 8px rgba(35,134,54,0.3);
    
    &:hover {
      background: linear-gradient(135deg, #1a7a2e 0%, #0f5c22 100%) !important;
      box-shadow: 0 4px 12px rgba(35,134,54,0.4);
    }
  }

  .mat-raised-button {
    &.mat-primary {
      background: linear-gradient(135deg, #238636 0%, #1a7a2e 100%) !important;
      
      &:hover {
        background: linear-gradient(135deg, #1a7a2e 0%, #0f5c22 100%) !important;
      }
    }
    
    &.mat-warn {
      background: linear-gradient(135deg, #da3633 0%, #b6231f 100%) !important;
      
      &:hover {
        background: linear-gradient(135deg, #b6231f 0%, #8f1a17 100%) !important;
      }
    }
  }

  .spinner-overlay {
    background: rgba(13, 17, 23, 0.92);
    color: #f0f6fc;
    
    mat-spinner {
      circle {
        stroke: #238636 !important;
      }
    }
  }
}

.mat-raised-button {
  border-radius: 8px;
  font-weight: 500;
  padding: 0 16px;
  height: 36px;
  line-height: 36px;
  transition: all 0.2s;
  border: none;
  
  &.mat-primary {
    background: linear-gradient(135deg, #3157d9 0%, #2a4bb2 100%);
    color: #fff;
    
    &:hover {
      background: linear-gradient(135deg, #2a4bb2 0%, #1f3a8f 100%);
    }
  }
  
  &.mat-warn {
    background: linear-gradient(135deg, #d93157 0%, #b22a4b 100%);
    color: #fff;
    
    &:hover {
      background: linear-gradient(135deg, #b22a4b 0%, #8f1f3a 100%);
    }
  }
}

.spinner-overlay {
  position: fixed;
  top: 0;
  left: 0;
  width: 100vw;
  height: 100vh;
  background: rgba(0, 0, 0, 0.7);
  z-index: 9999;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  color: white;
  font-size: 1.2rem;
  font-weight: 500;
  
  mat-spinner {
    margin-bottom: 20px;
  }
}

::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: transparent;
}

::-webkit-scrollbar-thumb {
  background: rgba(0, 0, 0, 0.2);
  border-radius: 4px;
  
  &:hover {
    background: rgba(0, 0, 0, 0.3);
  }
}

mat-form-field.mat-focused .mat-form-field-outline {
  border-width: 2px;
}

.mat-raised-button:focus,
.mat-icon-button:focus,
.mat-mini-fab:focus {
  outline: none;
}

@media (max-width: 800px) {
  .main-container {
    padding: 12px;
    
    .editor-panel,
    .preview-panel {
      padding: 0;
    }
  }
  
  .toolbar {
    padding: 0 12px;
    
    .lang-toggle {
      margin-right: 8px;
      
      mat-button-toggle {
        min-width: 38px;
        font-size: 0.75rem;
      }
    }
  }

  .quill-editor .ql-toolbar {
    flex-wrap: wrap;
    gap: 4px;
  }

  .chip-input-row {
    flex-wrap: wrap;
    
    .quill-editor {
      flex: 1 1 100%;
    }
  }
}
EOF

# ============================================================
# 15. FRONTEND: GLOBAL STYLES (styles.scss)
# ============================================================

cat > frontend/src/styles.scss << 'EOF'
@use '@angular/material' as mat;

$light-theme: mat.define-theme((
  color: (
    theme-type: light,
    primary: mat.$violet-palette,
    tertiary: mat.$rose-palette,
  ),
  density: (
    scale: 0
  )
));

$dark-theme: mat.define-theme((
  color: (
    theme-type: dark,
    primary: mat.$blue-palette,
    tertiary: mat.$cyan-palette,
  ),
  density: (
    scale: 0
  )
));

@include mat.all-component-themes($light-theme);

html, body {
  background: #f5f7fa;
  color: #1e1e1e;
  transition: background 0.3s ease, color 0.3s ease;
}

body.dark-theme {
  @include mat.all-component-colors($dark-theme);
  background: #0d1117;
  color: #e6edf3;
}

* { 
  box-sizing: border-box; 
  margin: 0; 
}

html, body { 
  height: 100%; 
}

body {
  margin: 0;
  font-family: 'Roboto', 'Helvetica Neue', sans-serif;
}

::-webkit-scrollbar {
  width: 8px;
  height: 8px;
}

::-webkit-scrollbar-track {
  background: transparent;
}

::-webkit-scrollbar-thumb {
  background: rgba(0, 0, 0, 0.2);
  border-radius: 4px;
  
  &:hover {
    background: rgba(0, 0, 0, 0.3);
  }
}

body.dark-theme ::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.15);
  
  &:hover {
    background: rgba(255, 255, 255, 0.25);
  }
}

body.dark-theme {
  .mat-expansion-panel {
    background: #161b22 !important;
    color: #e6edf3 !important;
  }
  
  .mat-form-field .mat-form-field-label {
    color: rgba(255,255,255,0.7) !important;
  }
  
  .mat-form-field .mat-form-field-outline {
    color: rgba(255,255,255,0.2) !important;
  }
  
  .mat-form-field .mat-input-element {
    color: #f0f6fc !important;
  }
  
  .mat-snack-bar-container {
    background: #161b22 !important;
    color: #e6edf3 !important;
    border: 1px solid #30363d;
  }
  
  .mat-tooltip {
    background: #161b22 !important;
    color: #e6edf3 !important;
    border: 1px solid #30363d;
  }
}

@media (max-width: 600px) {
  body {
    font-size: 14px;
  }
}
EOF

# ============================================================
# 16. FRONTEND: app.config.ts
# ============================================================

cat > frontend/src/app/app.config.ts << 'EOF'
import { ApplicationConfig, provideZoneChangeDetection } from '@angular/core';
import { provideHttpClient } from '@angular/common/http';
import { provideAnimationsAsync } from '@angular/platform-browser/animations/async';

export const appConfig: ApplicationConfig = {
  providers: [
    provideZoneChangeDetection({ eventCoalescing: true }),
    provideAnimationsAsync(),
    provideHttpClient(),
  ]
};
EOF

# ============================================================
# 17. FRONTEND: main.ts
# ============================================================

cat > frontend/src/main.ts << 'EOF'
import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';

bootstrapApplication(AppComponent, appConfig)
  .catch((err: any) => console.error(err));
EOF

# ============================================================
# 18. ANGULAR JSON (bez server builda)
# ============================================================

cat > frontend/angular.json << 'EOF'
{
  "$schema": "./node_modules/@angular/cli/lib/config/schema.json",
  "version": 1,
  "newProjectRoot": "projects",
  "projects": {
    "frontend": {
      "projectType": "application",
      "schematics": {},
      "root": "",
      "sourceRoot": "src",
      "prefix": "app",
      "architect": {
        "build": {
          "builder": "@angular/build:application",
          "options": {
            "outputPath": "dist/frontend",
            "index": "src/index.html",
            "browser": "src/main.ts",
            "polyfills": ["zone.js"],
            "tsConfig": "tsconfig.app.json",
            "assets": ["src/favicon.ico", "src/assets"],
            "styles": ["src/styles.scss"],
            "scripts": []
          },
          "configurations": {
            "production": {
              "budgets": [
                {
                  "type": "initial",
                  "maximumWarning": "500kb",
                  "maximumError": "1mb"
                },
                {
                  "type": "anyComponentStyle",
                  "maximumWarning": "2kb",
                  "maximumError": "4kb"
                }
              ],
              "outputHashing": "all"
            },
            "development": {
              "optimization": false,
              "extractLicenses": false,
              "sourceMap": true
            }
          },
          "defaultConfiguration": "production"
        },
        "serve": {
          "builder": "@angular/build:dev-server",
          "configurations": {
            "production": {
              "buildTarget": "frontend:build:production"
            },
            "development": {
              "buildTarget": "frontend:build:development"
            }
          },
          "defaultConfiguration": "development"
        },
        "extract-i18n": {
          "builder": "@angular/build:extract-i18n",
          "options": {
            "buildTarget": "frontend:build"
          }
        },
        "test": {
          "builder": "@angular/build:karma",
          "options": {
            "polyfills": ["zone.js", "zone.js/testing"],
            "tsConfig": "tsconfig.spec.json",
            "assets": ["src/favicon.ico", "src/assets"],
            "styles": ["src/styles.scss"],
            "scripts": []
          }
        }
      }
    }
  }
}
EOF

# ============================================================
# 19. BRISANJE NEPOTREBNIH DATOTEKA
# ============================================================

rm -f frontend/src/main.server.ts 2>/dev/null || true
rm -f frontend/src/app/app.config.server.ts 2>/dev/null || true
rm -f frontend/src/app/app.routes.server.ts 2>/dev/null || true
rm -f frontend/src/app/app.module.ts 2>/dev/null || true

# ============================================================
# 20. ZAVRŠNA INSTALACIJA
# ============================================================

echo "=============================================="
echo "  Dovršavam instalaciju ovisnosti..."
echo "=============================================="

cd frontend
npm install --legacy-peer-deps --no-audit --no-fund
npm audit fix --legacy-peer-deps --no-audit --no-fund || true
cd ..

echo "=============================================="
echo "✅ SETUP ZAVRŠEN!"
echo "=============================================="
echo ""
echo "🚀 Za pokretanje aplikacije:"
echo ""
echo "1. Uredi backend/.env i postavi svoje API ključeve"
echo ""
echo "2. Pokreni backend (u terminalu 1):"
echo "   cd backend && node server.js"
echo ""
echo "3. Pokreni Angular dev server (u terminalu 2):"
echo "   cd frontend && ng serve"
echo ""
echo "4. Otvori browser na: http://localhost:4200"
echo ""
echo "📁 Podaci se spremaju u: backend/data/cv.json"
echo "🌙 Tema se pamti u localStorage"
echo ""
echo "✨ Napomene:"
echo "   - Angular 22 standalone"
echo "   - Quill WYSIWYG editor"
echo "   - AI fallback: Mistral → HF → OpenRouter"
echo "   - PDF i Markdown upload"
echo "   - HR/EN prevođenje"
echo "   - Dark/Light tema (DeepSeek inspiracija)"
echo ""
echo "Uživajte! 🎉"