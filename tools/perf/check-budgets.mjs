import { readFile } from 'node:fs/promises';
import path from 'node:path';

const file = process.argv[2] ?? path.join(process.cwd(), 'docs/observability/performance-budgets.json');
const raw = await readFile(file, 'utf8');
const data = JSON.parse(raw);

const budgets = data.budgetsMs ?? {};
const measurements = data.measurementsMs ?? {};

const failures = [];
for (const [metric, budget] of Object.entries(budgets)) {
  const measured = measurements[metric];
  if (typeof measured !== 'number') {
    failures.push(`${metric}: missing measurement`);
    continue;
  }
  if (measured > budget) {
    failures.push(`${metric}: measured=${measured}ms exceeds budget=${budget}ms`);
  }
}

if (failures.length > 0) {
  console.error('performance budget check failed');
  for (const failure of failures) {
    console.error(`- ${failure}`);
  }
  process.exit(1);
}

console.log('performance budget check passed');
