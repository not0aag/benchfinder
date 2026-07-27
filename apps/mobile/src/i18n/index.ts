import { getLocales } from 'expo-localization';
import i18n from 'i18next';
import { initReactI18next } from 'react-i18next';

import en from './locales/en.json';

export const defaultNS = 'translation';
export const resources = {
  en: { translation: en },
} as const;

// Initialized synchronously so route components can call useTranslation on first render.
void i18n.use(initReactI18next).init({
  resources,
  lng: getLocales()[0]?.languageCode ?? 'en',
  fallbackLng: 'en',
  defaultNS,
  interpolation: {
    // React already escapes rendered strings
    escapeValue: false,
  },
});

export { default as i18n } from 'i18next';
