import js from '@eslint/js';
import prettier from 'eslint-config-prettier';
import boundariesPlugin from 'eslint-plugin-boundaries';
import tseslint from 'typescript-eslint';

export const base = tseslint.config(
  {
    ignores: [
      '**/dist/**',
      '**/coverage/**',
      '**/.turbo/**',
      '**/.expo/**',
      '**/android/**',
      '**/ios/**',
      '**/node_modules/**',
    ],
  },
  js.configs.recommended,
  ...tseslint.configs.recommended,
  prettier,
  {
    rules: {
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
    },
  },
);

// Dependency rule from BENCHFINDER_ARCHITECTURE.md section 8:
// domain <- data-access <- features <- app. Never the reverse.
// Cross-slice traffic goes through shared code, not sibling imports.
export const mobileBoundaries = {
  plugins: { boundaries: boundariesPlugin },
  settings: {
    'boundaries/elements': [
      { type: 'app', pattern: 'app/**' },
      { type: 'feature', pattern: 'src/features/*', capture: ['slice'] },
      { type: 'shared', pattern: 'src/{components,lib,theme,i18n}/**' },
    ],
    // Without a TS-aware resolver the plugin cannot classify import targets
    // and silently skips them, which disables the rule entirely.
    'import/resolver': {
      typescript: {},
    },
  },
  rules: {
    'boundaries/dependencies': [
      'error',
      {
        default: 'disallow',
        policies: [
          {
            from: { element: { type: 'app' } },
            allow: { to: { element: { type: ['feature', 'shared'] } } },
          },
          {
            from: { element: { type: 'feature' } },
            allow: [
              {
                to: {
                  element: {
                    type: 'feature',
                    captured: { slice: '{{ from.element.captured.slice }}' },
                  },
                },
              },
              { to: { element: { type: 'shared' } } },
            ],
          },
          {
            from: { element: { type: 'shared' } },
            allow: { to: { element: { type: 'shared' } } },
          },
        ],
      },
    ],
  },
};

// packages/domain must stay dependency-free (CLAUDE.md rule 6)
export const domainPurity = {
  files: ['src/**'],
  rules: {
    'no-restricted-imports': [
      'error',
      {
        patterns: [
          {
            group: ['react', 'react-*', '@supabase/*', 'expo*', '@benchfinder/*'],
            message: 'packages/domain has zero runtime dependencies. This logic belongs elsewhere.',
          },
        ],
      },
    ],
  },
};
