#!/bin/bash
set -e

echo "=================================================="
echo " 🚀 Nadogradnja: AI + PDF parser + UI Popravci"
echo "=================================================="

# 1. Instalacija novih paketa na backendu
echo "📦 Instaliram backend ovisnosti (multer, pdf-parse)..."
cd backend || exit 1
npm install multer pdf-parse --save
cd .. || exit 1

# ---------- POPRAVAK FRONTEND INDEX.HTML (Ikonice) ----------
echo "🔧 Popravljam index.html (dodavanje Material Icons fonta)..."
cat > frontend/src/index.html <<'EOF'
<!doctype html>
<html lang="hr">
<head>
  <meta charset="utf-8">
  <title>ATS CV Editor</title>
  <base href="/">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <link rel="icon" type="image/x-icon" href="favicon.ico">
  <link href="https://fonts.googleapis.com/icon?family=Material+Icons" rel="stylesheet">
  <link href="https://fonts.googleapis.com/css2?family=Roboto:wght@300;400;500;700&display=swap" rel="stylesheet">
</head>
<body>
  <app-root></app-root>
</body>
</html>
EOF

# ---------- BACKEND: Novi server.js s AI i PDF podrškom ----------
echo "🧠 Nadograđujem backend/server.js..."
cat > backend/server.js <<'EOF'
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');
const multer = require('multer');
const pdfParse = require('pdf-parse');

const app = express();
const PORT = 3000;

// Konfiguracija multera za upload u memoriju
const upload = multer({ storage: multer.memoryStorage() });

app.use(cors());
app.use(express.json({ limit: '10mb' }));

const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = path.join(DATA_DIR, 'cv.json');

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

// Pomoćna funkcija za poziv Gemini API-ja
async function callGemini(prompt) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) {
    throw new Error("Upozorenje: GEMINI_API_KEY nije postavljen u okruženju.");
  }
  
  const url = `https://generativelanguage.googleapis.com/v1beta/models/gemini-1.5-flash:generateContent?key=${apiKey}`;
  const response = await fetch(url, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ parts: [{ text: prompt }] }],
      generationConfig: { responseMimeType: "application/json" }
    })
  });

  const resData = await response.json();
  if (!response.ok) throw new Error(resData.error?.message || "Greška pri pozivu AI");
  return resData.candidates[0].content.parts[0].text;
}

// Postojeći GET i POST rute
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

// 🔥 1. RUTA: Upload PDF-a i AI parsiranje u JSON strukturu
app.post('/api/cv/upload-pdf', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'Nema datoteke.' });
    
    // Ekstrakcija sirovog teksta iz PDF-a
    const pdfData = await pdfParse(req.file.buffer);
    const extractedText = pdfData.text;

    if (!process.env.GEMINI_API_KEY) {
      return res.status(400).json({ error: "Morate postaviti GEMINI_API_KEY na backendu!" });
    }

    const aiPrompt = `Analiziraj sljedeći tekst izvučen iz životopisa i strukturiraj ga strogo prema zadanom JSON formatu. 
    Format mora sadržavati polja: personal (name, email, phone, location, linkedin), summary, experience (niz objekata sa: title, company, start, end, description), education (niz sa: degree, institution, year), skills (niz stringova), languages (niz stringova), projects (niz sa: name, description, link), certificates (niz sa: name, issuer, date).
    Ako neko polje nedostaje u tekstu, ostavi ga kao prazan niz ili prazan string. Vrati isključivo čisti JSON objekt bez markdown oznaka.
    
    Tekst životopisa:
    ${extractedText}`;

    const aiResultString = await callGemini(aiPrompt);
    const structuredJson = JSON.parse(aiResultString);

    res.json(structuredJson);
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

// 🔥 2. RUTA: AI optimizacija određenog teksta (ATS poboljšanje)
app.post('/api/cv/ai-optimize', async (req, res) => {
  try {
    const { text, context } = req.body;
    if (!text) return res.status(400).json({ error: 'Tekst nedostaje.' });

    const aiPrompt = `Ti si profesionalni ATS (Applicant Tracking System) stručnjak za pisanje životopisa. 
    Preuredi sljedeći tekst kako bi zvučao profesionalnije, koristio snažne glagole akcije i bio maksimalno optimiziran za ATS skenere. 
    Zadrži jezik na kojem je napisan izvorni tekst. Vrati isključivo optimizirani tekst bez ikakvih uvodnih ili zaključnih objašnjenja.
    
    Kontekst sekcije: ${context}
    Izvorni tekst: ${text}`;

    const optimizedText = await callGemini(aiPrompt);
    res.json({ text: optimizedText.trim() });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.listen(PORT, () => console.log(`✅ Backend s AI značajkama na portu ${PORT}`));
EOF

# ---------- FRONTEND: Servis nadogradnja ----------
echo "🔧 Nadograđujem cv.service.ts..."
cat > frontend/src/app/services/cv.service.ts <<'EOF'
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

  optimizeText(text: string, context: string): Observable<{text: string}> {
    return this.http.post<{text: string}>(`${this.apiUrl}/ai-optimize`, { text, context });
  }
}
EOF

# ---------- FRONTEND: App Component TS nadogradnja ----------
echo "🔧 Nadograđujem app.component.ts..."
cat > frontend/src/app/app.component.ts <<'EOF'
import { Component, OnInit, ViewChild, ElementRef, inject } from '@angular/core';
import { CommonModule } from '@angular/common';
import { FormsModule } from '@angular/forms';
import { HttpClientModule } from '@angular/common/http';

import { MatToolbarModule } from '@angular/material/toolbar';
import { MatIconModule } from '@angular/material/icon';
import { MatButtonModule } from '@angular/material/button';
import { MatSlideToggleModule } from '@angular/material/slide-toggle';
import { MatInputModule } from '@angular/material/input';
import { MatFormFieldModule } from '@angular/material/form-field';
import { MatExpansionModule } from '@angular/material/expansion';
import { MatCardModule } from '@angular/material/card';
import { MatDividerModule } from '@angular/material/divider';
import { MatSnackBarModule, MatSnackBar } from '@angular/material/snack-bar';
import { MatTooltipModule } from '@angular/material/tooltip';
import { MatProgressSpinnerModule } from '@angular/material/progress-spinner';

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
    MatSlideToggleModule,
    MatInputModule,
    MatFormFieldModule,
    MatExpansionModule,
    MatCardModule,
    MatDividerModule,
    MatSnackBarModule,
    MatTooltipModule,
    MatProgressSpinnerModule
  ]
})
export class AppComponent implements OnInit {
  @ViewChild('previewElement') previewElement!: ElementRef;

  cv: CV = this.getEmptyCV();
  isLoading = false;
  private saveTimeout: any;

  private cvService = inject(CvService);
  public themeService = inject(ThemeService);
  private snackBar = inject(MatSnackBar);

  ngOnInit(): void {
    this.loadCV();
  }

  getEmptyCV(): CV {
    return {
      personal: { name: '', email: '', phone: '', location: '', linkedin: '' },
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
      next: (data) => { this.cv = data; },
      error: () => { this.snackBar.open('Greška pri učitavanju', 'OK', { duration: 3000 }); }
    });
  }

  onDataChange(): void {
    clearTimeout(this.saveTimeout);
    this.saveTimeout = setTimeout(() => this.saveCV(), 500);
  }

  saveCV(): void {
    this.cvService.saveCV(this.cv).subscribe({
      next: () => {},
      error: () => { this.snackBar.open('Greška pri spremanju', 'OK', { duration: 3000 }); }
    });
  }

  // 🔥 Nova metoda za AI optimizaciju pojedinačnih polja teksta
  optimizeField(context: string, currentValue: string, callback: (optimized: string) => void) {
    if (!currentValue.trim()) {
      this.snackBar.open('Polje je prazno, nema se što optimizirati!', 'OK', { duration: 3000 });
      return;
    }
    this.snackBar.open('AI optimizira tekst...', 'Molimo pričekajte', { duration: 2000 });
    this.cvService.optimizeText(currentValue, context).subscribe({
      next: (res) => {
        callback(res.text);
        this.onDataChange();
        this.snackBar.open('Tekst uspješno optimiziran!', 'OK', { duration: 3000 });
      },
      error: (err) => this.snackBar.open(err.error?.error || 'Greška s AI modulom', 'OK', { duration: 4000 })
    });
  }

  // 🔥 Nova metoda za obradu uploadanog PDF-a i automatsko pretvaranje u CV obrazac
  onImportPdf(event: Event): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;

    this.isLoading = true;
    this.snackBar.open('AI analizira i parsira vaš PDF...', 'Učitavanje', { duration: 4000 });

    this.cvService.uploadPdfAndParse(file).subscribe({
      next: (parsedCv) => {
        this.cv = parsedCv;
        this.saveCV();
        this.isLoading = false;
        this.snackBar.open('🚀 PDF uspješno parsiran i učitan u editor!', 'Zatvori', { duration: 4000 });
      },
      error: (err) => {
        this.isLoading = false;
        this.snackBar.open(err.error?.error || 'Greška pri parsiranju PDF-a', 'OK', { duration: 5000 });
      }
    });
    (event.target as HTMLInputElement).value = '';
  }

  addItem(array: keyof CV, template: any): void {
    (this.cv[array] as any[]).push(template);
    this.onDataChange();
  }

  removeItem(array: keyof CV, index: number): void {
    (this.cv[array] as any[]).splice(index, 1);
    this.onDataChange();
  }

  trackByIndex(index: number): number { return index; }

  onImportJson(event: Event): void {
    const file = (event.target as HTMLInputElement).files?.[0];
    if (!file) return;
    const reader = new FileReader();
    reader.onload = (e) => {
      try {
        this.cv = JSON.parse(e.target?.result as string);
        this.saveCV();
        this.snackBar.open('CV uspješno uvezen!', 'OK', { duration: 3000 });
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
    a.download = 'cv-data.json';
    a.click();
    URL.revokeObjectURL(url);
  }

  exportPdf(): void {
    const element = this.previewElement.nativeElement;
    const opt = {
      margin: 0.5,
      filename: `${this.cv.personal.name || 'CV'}.pdf`,
      image: { type: 'jpeg', quality: 0.98 },
      html2canvas: { scale: 2, letterRendering: true, useCORS: true },
      jsPDF: { unit: 'in', format: 'a4', orientation: 'portrait' }
    };
    html2pdf().set(opt).from(element).save();
  }

  addSkill(): void { this.cv.skills.push(''); this.onDataChange(); }
  removeSkill(index: number): void { this.cv.skills.splice(index, 1); this.onDataChange(); }
  addLanguage(): void { this.cv.languages.push(''); this.onDataChange(); }
  removeLanguage(index: number): void { this.cv.languages.splice(index, 1); this.onDataChange(); }
}
EOF

# ---------- FRONTEND: App Component HTML nadogradnja ----------
echo "🔧 Nadograđujem app.component.html..."
cat > frontend/src/app/app.component.html <<'EOF'
<mat-toolbar color="primary" class="toolbar">
  <span class="title">📄 ATS CV Editor</span>
  <span class="spacer"></span>
  
  <button mat-icon-button (click)="exportJson()" matTooltip="Izvezi JSON">
    <mat-icon>download</mat-icon>
  </button>
  <button mat-icon-button (click)="exportPdf()" matTooltip="Generiraj PDF">
    <mat-icon>picture_as_pdf</mat-icon>
  </button>
  <label mat-icon-button matTooltip="Uvezi JSON" style="cursor: pointer;">
    <mat-icon>upload_file</mat-icon>
    <input type="file" accept=".json" (change)="onImportJson($event)" style="display:none">
  </label>
  
  <label mat-icon-button matTooltip="AI Uvoz iz starog PDF-a" style="cursor: pointer; color: #ffeb3b;">
    <mat-icon>auto_awesome</mat-icon>
    <input type="file" accept=".pdf" (change)="onImportPdf($event)" style="display:none">
  </label>

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
  <p>AI upravo transformira vaš PDF u ATS format...</p>
</div>

<div class="main-container">
  <div class="editor-panel">
    <h2>✏️ Uredi CV</h2>

    <mat-expansion-panel expanded>
      <mat-expansion-panel-header>👤 Osobni podaci</mat-expansion-panel-header>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>Ime i prezime</mat-label>
        <input matInput [(ngModel)]="cv.personal.name" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>Email</mat-label>
        <input matInput type="email" [(ngModel)]="cv.personal.email" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>Telefon</mat-label>
        <input matInput [(ngModel)]="cv.personal.phone" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>Lokacija</mat-label>
        <input matInput [(ngModel)]="cv.personal.location" (ngModelChange)="onDataChange()">
      </mat-form-field>
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>LinkedIn URL</mat-label>
        <input matInput [(ngModel)]="cv.personal.linkedin" (ngModelChange)="onDataChange()">
      </mat-form-field>
    </mat-expansion-panel>

    <mat-expansion-panel>
      <mat-expansion-panel-header>📝 Sažetak</mat-expansion-panel-header>
      <div class="ai-field-container">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Profesionalni sažetak</mat-label>
          <textarea matInput rows="4" [(ngModel)]="cv.summary" (ngModelChange)="onDataChange()"></textarea>
        </mat-form-field>
        <button mat-mini-fab color="accent" class="ai-inline-btn" matTooltip="AI Poboljšaj sažetak" (click)="optimizeField('Profesionalni sažetak/O meni', cv.summary, (val) => cv.summary = val)">
          <mat-icon>auto_awesome</mat-icon>
        </button>
      </div>
    </mat-expansion-panel>

    <mat-expansion-panel>
      <mat-expansion-panel-header>💼 Radno iskustvo</mat-expansion-panel-header>
      <div *ngFor="let exp of cv.experience; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Naziv radnog mjesta</mat-label>
          <input matInput [(ngModel)]="exp.title" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Tvrtka</mat-label>
          <input matInput [(ngModel)]="exp.company" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <div class="row-gap">
          <mat-form-field appearance="fill" class="flex-half">
            <mat-label>Početak</mat-label>
            <input matInput [(ngModel)]="exp.start" (ngModelChange)="onDataChange()">
          </mat-form-field>
          <mat-form-field appearance="fill" class="flex-half">
            <mat-label>Kraj</mat-label>
            <input matInput [(ngModel)]="exp.end" (ngModelChange)="onDataChange()">
          </mat-form-field>
        </div>
        <div class="ai-field-container">
          <mat-form-field appearance="fill" class="full-width">
            <mat-label>Opis i postignuća</mat-label>
            <textarea matInput rows="3" [(ngModel)]="exp.description" (ngModelChange)="onDataChange()"></textarea>
          </mat-form-field>
          <button mat-mini-fab color="accent" class="ai-inline-btn" matTooltip="AI Optimiziraj opis posla" (click)="optimizeField('Opis posla / odgovornosti za poziciju ' + exp.title, exp.description, (val) => exp.description = val)">
            <mat-icon>auto_awesome</mat-icon>
          </button>
        </div>
        <button mat-raised-button color="warn" (click)="removeItem('experience', i)">Ukloni</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('experience', { title:'', company:'', start:'', end:'', description:'' })">
        + Dodaj iskustvo
      </button>
    </mat-expansion-panel>

    <mat-expansion-panel>
      <mat-expansion-panel-header>🎓 Obrazovanje</mat-expansion-panel-header>
      <div *ngFor="let edu of cv.education; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Stupanj / naziv</mat-label>
          <input matInput [(ngModel)]="edu.degree" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Institucija</mat-label>
          <input matInput [(ngModel)]="edu.institution" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Godina</mat-label>
          <input matInput [(ngModel)]="edu.year" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-raised-button color="warn" (click)="removeItem('education', i)">Ukloni</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('education', { degree:'', institution:'', year:'' })">
        + Dodaj obrazovanje
      </button>
    </mat-expansion-panel>

    <mat-expansion-panel>
      <mat-expansion-panel-header>🚀 Projekti</mat-expansion-panel-header>
      <div *ngFor="let proj of cv.projects; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Naziv projekta</mat-label>
          <input matInput [(ngModel)]="proj.name" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Opis</mat-label>
          <textarea matInput rows="2" [(ngModel)]="proj.description" (ngModelChange)="onDataChange()"></textarea>
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Link</mat-label>
          <input matInput [(ngModel)]="proj.link" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-raised-button color="warn" (click)="removeItem('projects', i)">Ukloni</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('projects', { name:'', description:'', link:'' })">
        + Dodaj projekt
      </button>
    </mat-expansion-panel>

    <mat-expansion-panel>
      <mat-expansion-panel-header>📜 Certifikati</mat-expansion-panel-header>
      <div *ngFor="let cert of cv.certificates; let i = index" class="array-item">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Naziv certifikata</mat-label>
          <input matInput [(ngModel)]="cert.name" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Izdavatelj</mat-label>
          <input matInput [(ngModel)]="cert.issuer" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Datum</mat-label>
          <input matInput [(ngModel)]="cert.date" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-raised-button color="warn" (click)="removeItem('certificates', i)">Ukloni</button>
        <mat-divider></mat-divider>
      </div>
      <button mat-raised-button color="primary" (click)="addItem('certificates', { name:'', issuer:'', date:'' })">
        + Dodaj certifikat
      </button>
    </mat-expansion-panel>

    <mat-expansion-panel>
      <mat-expansion-panel-header>🛠️ Vještine</mat-expansion-panel-header>
      <div *ngFor="let skill of cv.skills; let i = index" class="chip-input-row">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Vještina #{{ i+1 }}</mat-label>
          <input matInput [(ngModel)]="cv.skills[i]" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-icon-button color="warn" (click)="removeSkill(i)">
          <mat-icon>close</mat-icon>
        </button>
      </div>
      <button mat-raised-button color="primary" (click)="addSkill()">+ Dodaj vještinu</button>
    </mat-expansion-panel>

    <mat-expansion-panel>
      <mat-expansion-panel-header>🌐 Jezici</mat-expansion-panel-header>
      <div *ngFor="let lang of cv.languages; let i = index" class="chip-input-row">
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Jezik #{{ i+1 }}</mat-label>
          <input matInput [(ngModel)]="cv.languages[i]" (ngModelChange)="onDataChange()">
        </mat-form-field>
        <button mat-icon-button color="warn" (click)="removeLanguage(i)">
          <mat-icon>close</mat-icon>
        </button>
      </div>
      <button mat-raised-button color="primary" (click)="addLanguage()">+ Dodaj jezik</button>
    </mat-expansion-panel>
  </div>

  <div class="preview-panel">
    <h2>👁️ Pregled (ATS friendly)</h2>
    <div class="preview-wrapper">
      <div #previewElement id="cvPreview" class="cv-paper">
        <h1>{{ cv.personal.name || 'Ime i prezime' }}</h1>
        <div class="contact-line">
          <span *ngIf="cv.personal.email">{{ cv.personal.email }}</span>
          <span *ngIf="cv.personal.phone"> | {{ cv.personal.phone }}</span>
          <span *ngIf="cv.personal.location"> | {{ cv.personal.location }}</span>
          <span *ngIf="cv.personal.linkedin"> | <a [href]="cv.personal.linkedin" target="_blank">LinkedIn</a></span>
        </div>

        <h2 *ngIf="cv.summary">Sažetak</h2>
        <p *ngIf="cv.summary">{{ cv.summary }}</p>

        <h2 *ngIf="cv.experience.length">Radno iskustvo</h2>
        <div *ngFor="let exp of cv.experience" class="preview-item">
          <div class="item-header">
            <strong>{{ exp.title }}</strong> – {{ exp.company }}
            <span class="item-date">{{ exp.start }} – {{ exp.end }}</span>
          </div>
          <p *ngIf="exp.description">{{ exp.description }}</p>
        </div>

        <h2 *ngIf="cv.education.length">Obrazovanje</h2>
        <div *ngFor="let edu of cv.education" class="preview-item">
          <div class="item-header">
            <strong>{{ edu.degree }}</strong> – {{ edu.institution }}
            <span class="item-date">{{ edu.year }}</span>
          </div>
        </div>

        <h2 *ngIf="cv.projects.length">Projekti</h2>
        <div *ngFor="let proj of cv.projects" class="preview-item">
          <div class="item-header">
            <strong>{{ proj.name }}</strong>
            <span *ngIf="proj.link"><a [href]="proj.link" target="_blank">(link)</a></span>
          </div>
          <p *ngIf="proj.description">{{ proj.description }}</p>
        </div>

        <h2 *ngIf="cv.certificates.length">Certifikati</h2>
        <div *ngFor="let cert of cv.certificates" class="preview-item">
          <div class="item-header">
            <strong>{{ cert.name }}</strong> – {{ cert.issuer }}
            <span class="item-date">{{ cert.date }}</span>
          </div>
        </div>

        <h2 *ngIf="cv.skills.length">Vještine</h2>
        <p *ngIf="cv.skills.length">{{ cv.skills.join(', ') }}</p>

        <h2 *ngIf="cv.languages.length">Jezici</h2>
        <p *ngIf="cv.languages.length">{{ cv.languages.join(', ') }}</p>
      </div>
    </div>
  </div>
</div>
EOF

# ---------- FRONTEND: Dodatni SCSS stilovi za AI elemente ----------
echo "🔧 Dodajem CSS stilove za AI komponente..."
cat >> frontend/src/app/app.component.scss <<'EOF'

.ai-field-container {
  display: flex;
  align-items: flex-start;
  gap: 10px;
  width: 100%;
  
  mat-form-field {
    flex: 1;
  }
  
  .ai-inline-btn {
    margin-top: 8px;
    background-color: #7b1fa2;
    color: white;
    flex-shrink: 0;
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
EOF

echo "=================================================="
echo " 🌟 NADOGRADNJA USPIJELA!"
echo "=================================================="
