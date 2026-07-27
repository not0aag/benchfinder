import { base, mobileBoundaries } from '@benchfinder/config/eslint';
import reactHooks from 'eslint-plugin-react-hooks';

export default [
  ...base,
  {
    files: ['**/*.{ts,tsx}'],
    plugins: { 'react-hooks': reactHooks },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react-hooks/exhaustive-deps': 'error',
    },
  },
  mobileBoundaries,
];
