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
