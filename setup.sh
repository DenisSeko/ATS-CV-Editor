#!/bin/bash

# Zaustavi skriptu ako bilo koja naredba baci grešku
set -e

# Definicija boja za ljepši ispis u terminalu
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   ATS CV Editor - Napredni Setup (Angular 22)   ${NC}"
echo -e "${BLUE}==================================================${NC}"

# 1. Provjera Node.js okruženja
if ! command -v node &> /dev/null; then
    echo -e "${RED}❌ Node.js nije instaliran. Molimo instalirajte Node.js (v18.19.0+) i pokušajte ponovo.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ Node.js verzija: $(node -v)${NC}"

if ! command -v npm &> /dev/null; then
    echo -e "${RED}❌ npm nije instaliran.${NC}"
    exit 1
fi
echo -e "${GREEN}✅ npm verzija: $(npm -v)${NC}"

# 2. Kreiranje root orkestracije (Pokretanje svega jednom naredbom)
echo -e "${YELLOW}📦 Kreiram root konfiguraciju za jednostavno pokretanje...${NC}"
cat > package.json <<'EOF'
{
  "name": "ats-cv-editor-root",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start:backend": "cd backend && node server.js",
    "start:frontend": "cd frontend && npx ng serve",
    "start": "npx concurrently \"npm run start:backend\" \"npm run start:frontend\""
  },
  "dependencies": {
    "concurrently": "^8.2.2"
  }
}
EOF

echo -e "${YELLOW}📦 Instaliram alate za simultano pokretanje...${NC}"
npm install --no-audit --no-fund

# 3. Kreiranje frontend aplikacije pomoću npx (Sigurnije od globalne instalacije)
echo -e "${YELLOW}🛠️  Kreiram Angular projekt u mapi 'frontend' (verzija 22, standalone)...${NC}"
npx @angular/cli@22 new frontend --routing=false --style=scss --skip-tests --skip-install

cd frontend || exit 1

# Konfiguracija .npmrc za pouzdan rad skripti unutar frontend-a
echo "allow-scripts=true" > .npmrc

echo -e "${YELLOW}📦 Instaliram zone.js i specifične Angular 22 pakete...${NC}"
npm install zone.js --legacy-peer-deps --no-audit --no-fund

echo -e "${YELLOW}📦 Instaliram Angular Material 22, CDK i html2pdf.js...${NC}"
npm install @angular/material@22 @angular/cdk@22 html2pdf.js --legacy-peer-deps --no-audit --no-fund

echo -e "${YELLOW}📦 Instaliram @angular/build 22 za stabilan dev-server...${NC}"
npm install @angular/build@22 --legacy-peer-deps --no-audit --no-fund

cd .. || exit 1

# 4. Kreiranje Backend strukture
echo -e "${YELLOW}📦 Kreiram Express backend s datotečnim sustavom...${NC}"
mkdir -p backend/data
cd backend || exit 1
npm init -y > /dev/null 2>&1
npm install express cors --legacy-peer-deps --no-audit --no-fund
cd .. || exit 1

echo -e "${BLUE}==================================================${NC}"
echo -e "${BLUE}   Generiranje izvornog koda aplikacije...        ${NC}"
echo -e "${BLUE}==================================================${NC}"

# ---------- BACKEND: server.js ----------
cat > backend/server.js <<'EOF'
const express = require('express');
const cors = require('cors');
const fs = require('fs');
const path = require('path');

const app = express();
const PORT = 3000;

app.use(cors());
app.use(express.json({ limit: '10mb' }));

const DATA_DIR = path.join(__dirname, 'data');
const DATA_FILE = path.join(DATA_DIR, 'cv.json');

if (!fs.existsSync(DATA_DIR)) {
  fs.mkdirSync(DATA_DIR, { recursive: true });
}

const defaultCV = {
  personal: {
    name: 'Ivan Horvat',
    email: 'ivan.horvat@email.com',
    phone: '+385 91 123 4567',
    location: 'Zagreb, Hrvatska',
    linkedin: 'https://linkedin.com/in/ivanhorvat'
  },
  summary: 'Viši programer s 5+ godina iskustva u razvoju web aplikacija. Strastven prema čistom kodu i automatizaciji.',
  experience: [
    { title: 'Vodeći programer', company: 'Tech d.o.o.', start: '2020', end: 'danas', description: 'Vođenje tima od 5 developera, razvoj mikroservisa, implementacija CI/CD.' },
    { title: 'Programer', company: 'Soft Solutions', start: '2017', end: '2020', description: 'Razvoj frontend i backend rješenja za bankarske klijente.' }
  ],
  education: [
    { degree: 'Magistar informatike', institution: 'Sveučilište u Zagrebu', year: '2017' }
  ],
  skills: ['JavaScript', 'Python', 'React', 'Node.js', 'Docker', 'AWS', 'Git', 'Agile metodologije'],
  languages: ['Hrvatski (materinji)', 'Engleski (tečno)', 'Njemački (osnovno)'],
  projects: [
    { name: 'ATS CV Editor', description: 'Web aplikacija za uređivanje životopisa prilagođena ATS sustavima.', link: 'https://github.com/example/ats-cv' }
  ],
  certificates: [
    { name: 'AWS Certified Developer', issuer: 'Amazon', date: '2022' }
  ]
};

app.get('/api/cv', (req, res) => {
  try {
    if (fs.existsSync(DATA_FILE)) {
      const data = fs.readFileSync(DATA_FILE, 'utf8');
      res.json(JSON.parse(data));
    } else {
      res.json(defaultCV);
    }
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.post('/api/cv', (req, res) => {
  try {
    fs.writeFileSync(DATA_FILE, JSON.stringify(req.body, null, 2));
    res.json({ success: true, message: 'CV spremljen!' });
  } catch (err) {
    res.status(500).json({ error: err.message });
  }
});

app.use(express.static(path.join(__dirname, '../frontend/dist/frontend')));

app.listen(PORT, () => {
  console.log(`✅ Backend pokrenut na http://localhost:${PORT}`);
  console.log(`📁 Podaci se spremaju u ${DATA_FILE}`);
});
EOF

# ---------- FRONTEND ČIŠĆENJE ----------
rm -f frontend/src/main.server.ts frontend/src/app/app.config.server.ts frontend/src/app/app.routes.server.ts 2>/dev/null || true
rm -f frontend/src/app/app.module.ts 2>/dev/null || true

# ---------- FRONTEND: angular.json ----------
cat > frontend/angular.json <<'EOF'
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

# ---------- FRONTEND: Model ----------
mkdir -p frontend/src/app/models
cat > frontend/src/app/models/cv.model.ts <<'EOF'
export interface Personal {
  name: string;
  email: string;
  phone: string;
  location: string;
  linkedin: string;
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

# ---------- FRONTEND: Servisi ----------
mkdir -p frontend/src/app/services

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
}
EOF

cat > frontend/src/app/services/theme.service.ts <<'EOF'
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
    }
  }

  toggleTheme(): void {
    this.setDarkMode(!this.darkMode);
  }

  setDarkMode(enabled: boolean): void {
    this.darkMode = enabled;
    if (enabled) {
      this.renderer.addClass(document.body, 'dark-theme');
      localStorage.setItem('theme', 'dark');
    } else {
      this.renderer.removeClass(document.body, 'dark-theme');
      localStorage.setItem('theme', 'light');
    }
  }

  isDarkMode(): boolean {
    return this.darkMode;
  }
}
EOF

# ---------- FRONTEND: app.config.ts ----------
cat > frontend/src/app/app.config.ts <<'EOF'
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

# ---------- FRONTEND: main.ts ----------
cat > frontend/src/main.ts <<'EOF'
import { bootstrapApplication } from '@angular/platform-browser';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';

bootstrapApplication(AppComponent, appConfig)
  .catch((err: any) => console.error(err));
EOF

# ---------- FRONTEND: App Component ----------
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
  ]
})
export class AppComponent implements OnInit {
  @ViewChild('previewElement') previewElement!: ElementRef;

  cv: CV = this.getEmptyCV();
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
      error: () => { this.snackBar.open('Greška pri učitavanju CV-a', 'OK', { duration: 3000 }); }
    });
  }

  onDataChange(): void {
    clearTimeout(this.saveTimeout);
    this.saveTimeout = setTimeout(() => this.saveCV(), 500);
  }

  saveCV(): void {
    this.cvService.saveCV(this.cv).subscribe({
      next: () => { /* Tiho spremanje na backend */ },
      error: () => { this.snackBar.open('Greška pri spremanju', 'OK', { duration: 3000 }); }
    });
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
        const data = JSON.parse(e.target?.result as string);
        this.cv = data;
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
      filename: 'CV.pdf',
      image: { type: 'jpeg', quality: 0.98 },
      html2canvas: { scale: 2, letterRendering: true, useCORS: true },
      jsPDF: { unit: 'in', format: 'a4', orientation: 'portrait' }
    } as any;
    html2pdf().set(opt).from(element).save();
  }

  addSkill(): void {
    this.cv.skills.push('');
    this.onDataChange();
  }

  removeSkill(index: number): void {
    this.cv.skills.splice(index, 1);
    this.onDataChange();
  }

  addLanguage(): void {
    this.cv.languages.push('');
    this.onDataChange();
  }

  removeLanguage(index: number): void {
    this.cv.languages.splice(index, 1);
    this.onDataChange();
  }
}
EOF

# ---------- FRONTEND: App Component HTML ----------
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
  <mat-slide-toggle
    [checked]="themeService.isDarkMode()"
    (toggleChange)="themeService.toggleTheme()"
    class="theme-toggle"
  >
    {{ themeService.isDarkMode() ? '🌙' : '☀️' }}
  </mat-slide-toggle>
</mat-toolbar>

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
      <mat-form-field appearance="fill" class="full-width">
        <mat-label>Profesionalni sažetak</mat-label>
        <textarea matInput rows="4" [(ngModel)]="cv.summary" (ngModelChange)="onDataChange()"></textarea>
      </mat-form-field>
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
        <mat-form-field appearance="fill" class="full-width">
          <mat-label>Opis</mat-label>
          <textarea matInput rows="2" [(ngModel)]="exp.description" (ngModelChange)="onDataChange()"></textarea>
        </mat-form-field>
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

# ---------- FRONTEND: App Component SCSS ----------
cat > frontend/src/app/app.component.scss <<'EOF'
@use '@angular/material' as mat;

:host {
  display: block;
  height: 100vh;
  background: #f5f5f5;
  transition: background 0.3s;
}

.toolbar {
  .title { font-weight: 500; font-size: 1.2rem; }
  .spacer { flex: 1 1 auto; }
  .theme-toggle { margin-left: 8px; }
}

.main-container {
  display: flex;
  flex-direction: row;
  gap: 20px;
  padding: 20px;
  height: calc(100vh - 64px);
  overflow: hidden;

  @media (max-width: 800px) {
    flex-direction: column;
  }

  .editor-panel {
    flex: 1 1 50%;
    overflow-y: auto;
    padding-right: 10px;
    height: 100%;
    background: transparent;

    h2 { margin-top: 0; }

    .full-width { width: 100%; }

    .array-item {
      margin-bottom: 16px;
      padding: 12px;
      background: rgba(255,255,255,0.4);
      border-radius: 8px;
      transition: background 0.3s;
    }

    .chip-input-row {
      display: flex;
      align-items: center;
      gap: 8px;
      mat-form-field { flex: 1; }
    }

    mat-divider { margin: 12px 0; }
  }

  .preview-panel {
    flex: 1 1 50%;
    overflow-y: auto;
    padding-left: 10px;
    height: 100%;

    h2 { margin-top: 0; }

    .preview-wrapper {
      background: white;
      border-radius: 12px;
      padding: 24px;
      box-shadow: 0 4px 20px rgba(0,0,0,0.08);
      transition: background 0.3s, box-shadow 0.3s;
    }
  }
}

.row-gap {
  display: flex;
  gap: 10px;
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
  border: 1px solid #ddd;
  border-radius: 4px;

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

body.dark-theme {
  background: #303030;
  color: #eee;

  .main-container { background: #303030; }
  .editor-panel .array-item { background: rgba(255,255,255,0.06); }
  .preview-panel .preview-wrapper {
    background: #424242;
    box-shadow: 0 4px 20px rgba(0,0,0,0.5);
  }
  .cv-paper {
    background: #424242;
    color: #eee;
    border-color: #666;
    h2 { border-bottom-color: #666; }
    .item-date { color: #aaa; }
    .contact-line { color: #bbb; }
    a { color: #8ab4f8; }
  }
  mat-expansion-panel {
    background: #383838 !important;
    color: #eee;
  }
  mat-form-field { background: transparent; }
}
EOF

# ---------- FRONTEND: Global Styles ----------
rm -f frontend/src/styles.scss
cat > frontend/src/styles.scss <<'EOF'
@use '@angular/material' as mat;

html {
  color-scheme: light dark;
  @include mat.theme((
    color: mat.$violet-palette,
    typography: Roboto,
    density: 0
  ));
}

body {
  background: var(--mat-sys-surface);
  color: var(--mat-sys-on-surface);
  margin: 0;
  font-family: Roboto, "Helvetica Neue", sans-serif;
  transition: background 0.3s;
}

.dark-theme {
  background: #303030;
  color: white;
}

* { box-sizing: border-box; margin: 0; }
html, body { height: 100%; }

::-webkit-scrollbar { width: 6px; }
::-webkit-scrollbar-track { background: transparent; }
::-webkit-scrollbar-thumb { background: #888; border-radius: 10px; }
::-webkit-scrollbar-thumb:hover { background: #555; }
EOF

# 5. Završni koraci i čišćenje repozitorija
echo -e "${YELLOW}==================================================${NC}"
echo -e "${YELLOW}   Dovršavam instalaciju ovisnosti...             ${NC}"
echo -e "${YELLOW}==================================================${NC}"

cd frontend || exit 1
npm install --legacy-peer-deps --no-audit --no-fund
npm audit fix --legacy-peer-deps --no-audit --no-fund || true
cd .. || exit 1

echo -e "${GREEN}==================================================${NC}"
echo -e "${GREEN} ✅ SETUP ZAVRŠEN (Angular 22 Standalone, FINAL)  ${NC}"
echo -e "${GREEN}==================================================${NC}"
echo ""
echo -e "${BLUE}🚀 Sve komponente su uspješno povezane i konfigurirane!${NC}"
echo ""
echo -e "Zahvaljujući automatskoj root konfiguraciji, aplikaciju sada"
echo -e "možete pokrenuti unutar ${GREEN}samo jednog terminala${NC}."
echo ""
echo -e "${YELLOW}Za pokretanje sustava upišite:${NC}"
echo -e "   ${GREEN}npm start${NC}"
echo ""
echo -e "🌍 Nakon toga otvorite browser na: ${BLUE}http://localhost:4200${NC}"
echo ""
echo -e "📌 ${YELLOW}Značajke sustava:${NC}"
echo -e "   - Angular 22 standalone arhitektura (bez suvišnih modula)"
echo -e "   - zone.js polyfill pogreške su trajno riješene"
echo -e "   - @angular/build 22 postavljen kao primarni dev-server paket"
echo -e "   - @angular/material 22 implementira napredni M3 token theming sustav"
echo -e "   - html2pdf.js integriran s klijentske strane za čist izvoz bez backend renderinga"
echo ""
