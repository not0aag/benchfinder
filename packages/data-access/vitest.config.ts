import { defineConfig } from 'vitest/config';

export default defineConfig({
  test: {
    include: ['src/**/*.test.ts'],
    // The repository is a thin select today; parsing is covered in
    // api-contracts. Real integration tests (testcontainers) arrive with the
    // first repository method containing logic.
    passWithNoTests: true,
  },
});
