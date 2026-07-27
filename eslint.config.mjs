import { base } from '@benchfinder/config/eslint';

// Root-level config files only. Packages carry their own eslint.config.mjs;
// ESLint resolves the nearest config per file.
export default [...base];
