import { Injectable } from '@angular/core';
import { HttpClient } from '@angular/common/http';
import { Observable } from 'rxjs';
import { CV } from '../models/cv.model';

@Injectable({ providedIn: 'root' })
export class CvService {
  private apiUrl = 'http://localhost:3000/api/cv';

  constructor(private http: HttpClient) {}

  /**
   * Dohvaća CV sa backend-a
   */
  getCV(): Observable<CV> {
    return this.http.get<CV>(this.apiUrl);
  }

  /**
   * Sprema CV na backend
   */
  saveCV(cv: CV): Observable<any> {
    return this.http.post(this.apiUrl, cv);
  }

  /**
   * Uploada PDF datoteku i parsira je u CV JSON
   */
  uploadPdfAndParse(file: File): Observable<CV> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<CV>(`${this.apiUrl}/upload-pdf`, formData);
  }

  /**
   * Uploada Markdown datoteku i parsira je u CV JSON
   */
  uploadMarkdownAndParse(file: File): Observable<CV> {
    const formData = new FormData();
    formData.append('file', file);
    return this.http.post<CV>(`${this.apiUrl}/upload-markdown`, formData);
  }

  /**
   * AI optimizacija pojedinačnog teksta
   */
  optimizeText(text: string, context: string): Observable<{ text: string }> {
    return this.http.post<{ text: string }>(`${this.apiUrl}/ai-optimize`, { text, context });
  }

  /**
   * Prevođenje cijelog CV-a na zadani jezik
   */
  translateCV(cv: any, targetLang: 'hr' | 'en'): Observable<CV> {
    return this.http.post<CV>(`${this.apiUrl}/translate`, {
      cvData: cv,
      targetLang
    });
  }
}