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

// QUILL WYSIWYG EDITOR
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

  // ============================================================
  // QUILL KONFIGURACIJA
  // ============================================================
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

  // ============================================================
  // 1. PREVOĐENJE CIJELOG CV-A
  // ============================================================

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

  // ============================================================
  // 2. AI OPTIMIZACIJA POJEDINAČNIH POLJA
  // ============================================================

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

  // ============================================================
  // 3. QUILL EVENT – ZAMJENA ZA ngModelChange (rješava problem s fokusom)
  // ============================================================

  onQuillChange(event: any): void {
    // event sadrži: { html: string, text: string, delta: any }
    // Pozivamo auto-spremanje
    this.onDataChange();
  }

  // ============================================================
  // 4. UPLOAD PDF
  // ============================================================

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

  // ============================================================
  // 5. UPLOAD MARKDOWN
  // ============================================================

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

  // ============================================================
  // 6. BRISANJE CIJELOG CV-a (RESET)
  // ============================================================

  resetCV(): void {
    const confirmReset = confirm('Jeste li sigurni da želite obrisati cijeli CV? Ova radnja se ne može poništiti.');
    
    if (confirmReset) {
      // Postavi prazan CV
      this.cv = this.getEmptyCV();
      
      // Spremi prazan CV na backend
      this.saveCV();
      
      // Osvježi UI
      this.cdr.detectChanges();
      
      this.snackBar.open('CV je uspješno obrisan!', 'OK', { duration: 3000 });
    }
  }

  // ============================================================
  // 7. OSNOVNE FUNKCIJE (LOAD, SAVE, IMPORT, EXPORT)
  // ============================================================

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

  // ============================================================
  // 8. UPRAVLJANJE NIZOVIMA
  // ============================================================

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

  // ============================================================
  // 9. MULTI-LANGUAGE LABELE
  // ============================================================

  getLabel(key: string): string {
    const labels: Record<string, Record<'hr' | 'en', string>> = {
      // Toolbar
      title: { hr: 'ATS CV Editor', en: 'ATS CV Editor' },
      exportJson: { hr: 'Izvezi JSON', en: 'Export JSON' },
      exportPdf: { hr: 'Generiraj PDF', en: 'Generate PDF' },
      importJson: { hr: 'Uvezi JSON', en: 'Import JSON' },
      importPdf: { hr: 'AI Uvoz iz PDF-a', en: 'AI Import from PDF' },
      importMarkdown: { hr: 'AI Uvoz iz Markdowna', en: 'AI Import from Markdown' },
      deleteCV: { hr: 'Obriši CV', en: 'Delete CV' },

      // Editor
      editCV: { hr: 'Uredi CV', en: 'Edit CV' },

      // Personal Info
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

      // Summary
      summary: { hr: 'Sažetak', en: 'Summary' },
      professionalSummary: { hr: 'Profesionalni sažetak', en: 'Professional Summary' },
      aiImproveSummary: { hr: 'AI Poboljšaj sažetak', en: 'AI Improve Summary' },

      // Experience
      workExperience: { hr: 'Radno iskustvo', en: 'Work Experience' },
      jobTitle: { hr: 'Naziv radnog mjesta', en: 'Job Title' },
      company: { hr: 'Tvrtka', en: 'Company' },
      start: { hr: 'Početak', en: 'Start' },
      end: { hr: 'Kraj', en: 'End' },
      description: { hr: 'Opis i postignuća', en: 'Description & Achievements' },
      aiOptimizeJob: { hr: 'AI Optimiziraj opis', en: 'AI Optimize Description' },
      addExperience: { hr: '+ Dodaj iskustvo', en: '+ Add Experience' },

      // Education
      education: { hr: 'Obrazovanje', en: 'Education' },
      degree: { hr: 'Stupanj / naziv', en: 'Degree' },
      institution: { hr: 'Institucija', en: 'Institution' },
      year: { hr: 'Godina', en: 'Year' },
      addEducation: { hr: '+ Dodaj obrazovanje', en: '+ Add Education' },

      // Projects
      projects: { hr: 'Projekti', en: 'Projects' },
      projectName: { hr: 'Naziv projekta', en: 'Project Name' },
      projectDescription: { hr: 'Opis', en: 'Description' },
      link: { hr: 'Link', en: 'URL' },
      addProject: { hr: '+ Dodaj projekt', en: '+ Add Project' },

      // Certificates
      certificates: { hr: 'Certifikati', en: 'Certificates' },
      certificateName: { hr: 'Naziv certifikata', en: 'Certificate Name' },
      issuer: { hr: 'Izdavatelj', en: 'Issuer' },
      date: { hr: 'Datum', en: 'Date' },
      addCertificate: { hr: '+ Dodaj certifikat', en: '+ Add Certificate' },

      // Skills
      skills: { hr: 'Vještine', en: 'Skills' },
      skill: { hr: 'Vještina', en: 'Skill' },
      addSkill: { hr: '+ Dodaj vještinu', en: '+ Add Skill' },

      // Languages
      languages: { hr: 'Jezici', en: 'Languages' },
      language: { hr: 'Jezik', en: 'Language' },
      addLanguage: { hr: '+ Dodaj jezik', en: '+ Add Language' },

      // Preview
      preview: { hr: 'Pregled (ATS friendly)', en: 'Preview (ATS friendly)' },

      // Buttons
      remove: { hr: 'Ukloni', en: 'Remove' },
      processing: { hr: 'AI transformira PDF...', en: 'AI processing PDF...' }
    };

    return labels[key]?.[this.language] || key;
  }
}