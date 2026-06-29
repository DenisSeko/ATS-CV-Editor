# 📄 ATS CV Editor

Web aplikacija za kreiranje, uređivanje i izvoz životopisa optimiziranih za **ATS** (Applicant Tracking Systems).  
Koristi AI za parsiranje PDF/Markdown, optimizaciju teksta i prevođenje.

---

## ✨ Značajke

- **WYSIWYG** uređivanje (Quill editor)
- AI parsiranje **PDF** i **Markdown** datoteka
- AI optimizacija teksta
- Prevođenje (**HR/EN**)
- **Dark/Light** tema
- Auto-spremanje
- JSON import/export
- PDF generacija

---

## 🚀 Brzo pokretanje

```bash
# Kloniraj
git clone https://github.com/DenisSeko/ATS-CV-Editor.git
cd ATS-CV-Editor

# Instaliraj
cd backend && npm install
cd ../frontend && npm install

# Pokreni
cd ../backend && node server.js  # terminal 1
cd ../frontend && ng serve        # terminal 2
