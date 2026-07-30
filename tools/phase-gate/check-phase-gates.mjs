import { readFile } from 'node:fs/promises';
import path from 'node:path';

const file = process.argv[2] ?? path.join(process.cwd(), 'docs/governance/phase-gates.json');

function fail(message) {
  console.error(`phase-gate check failed: ${message}`);
  process.exit(1);
}

const raw = await readFile(file, 'utf8');
const data = JSON.parse(raw);

if (!Number.isInteger(data.currentPhase)) {
  fail('currentPhase must be an integer');
}
if (!Array.isArray(data.phases) || data.phases.length === 0) {
  fail('phases must be a non-empty array');
}

const phases = [...data.phases].sort((a, b) => a.phase - b.phase);
const current = phases.find((p) => p.phase === data.currentPhase);
if (!current) {
  fail(`currentPhase ${data.currentPhase} is missing from phases[]`);
}

for (const phase of phases) {
  if (!Array.isArray(phase.criteria) || phase.criteria.length === 0) {
    fail(`phase ${phase.phase} has no criteria`);
  }
  for (const criterion of phase.criteria) {
    if (typeof criterion.done !== 'boolean') {
      fail(`phase ${phase.phase} criterion ${criterion.id ?? '<unknown>'} missing boolean done`);
    }
  }
}

for (const phase of phases) {
  const allDone = phase.criteria.every((criterion) => criterion.done);

  if (phase.phase < data.currentPhase && !allDone) {
    fail(`phase ${phase.phase} is before currentPhase but has incomplete criteria`);
  }

  if (phase.phase > data.currentPhase && phase.criteria.some((criterion) => criterion.done)) {
    fail(`phase ${phase.phase} has completed criteria before current phase is advanced`);
  }
}

if (data.currentPhase < Math.max(...phases.map((p) => p.phase))) {
  const laterPhasesStarted = phases
    .filter((phase) => phase.phase > data.currentPhase)
    .some((phase) => phase.criteria.some((criterion) => criterion.done));

  if (laterPhasesStarted) {
    fail('later phase work started before current phase completion');
  }
}

console.log(`phase-gate check passed for currentPhase=${data.currentPhase}`);
