// Copy whatever pake produced into dist/ under names that never change, so
// https://github.com/<repo>/releases/latest/download/<name> is a permanent URL
// and install.sh needs no GitHub API call (which is rate limited to 60/hour
// per IP for unauthenticated callers).
import { readFileSync, mkdirSync, copyFileSync } from 'node:fs';
import { join } from 'node:path';

const STABLE_NAMES = {
  linux:   { deb: 'metrica-linux-amd64.deb', appimage: 'metrica-linux-amd64.AppImage' },
  macos:   { dmg: 'metrica-macos-arm64.dmg' },
  windows: { msi: 'metrica-windows-x64.msi' },
};

const platform = process.argv[2];
const names = STABLE_NAMES[platform];
if (!names) {
  console.error(`usage: collect.mjs <${Object.keys(STABLE_NAMES).join('|')}>`);
  process.exit(2);
}

// pake writes exactly one JSON object to stdout; anything else means it died
// before the contract kicked in, and the raw text says more than a parse error.
let result;
try {
  result = JSON.parse(readFileSync('result.json', 'utf8'));
} catch (cause) {
  let raw = '';
  try { raw = readFileSync('result.json', 'utf8'); } catch {}
  console.error(`pake produced no parsable JSON result: ${cause.message}`);
  console.error(raw.trim() ? `raw output: ${raw.slice(0, 500)}` : 'raw output was empty');
  process.exit(1);
}

// pake reports a failed build in the JSON body, not only in the exit code.
if (!result.ok) {
  console.error(`pake failed: ${result.error?.code} — ${result.error?.message}`);
  if (result.error?.hint) console.error(`hint: ${result.error.hint}`);
  process.exit(1);
}

// On Linux a multi-target build can succeed with fewer outputs than requested:
// the formats that failed land in warnings, so they must be read, not assumed empty.
for (const warning of result.warnings ?? []) console.error(`warning: ${warning}`);

mkdirSync('dist', { recursive: true });

let collected = 0;
for (const output of result.outputs ?? []) {
  const stable = names[String(output.format).toLowerCase()];
  if (!stable) {
    console.error(`skipping unmapped format: ${output.format} (${output.path})`);
    continue;
  }
  copyFileSync(output.path, join('dist', stable));
  console.log(`${output.format} -> dist/${stable} (${output.sizeBytes} bytes)`);
  collected++;
}

if (collected === 0) {
  console.error('pake reported success but produced nothing this platform can publish');
  process.exit(1);
}
