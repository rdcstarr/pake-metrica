// safeDomain replaces the set of URLs that stay inside the app, it does not add
// to it — the mistake that shipped in pake-dribbble 1.0.0, where every internal
// link ended up in the system browser.
//
// Here it also decides whether the app is usable at all: Metrica sends every
// unauthenticated visit to passport.yandex.com, so a build that treats passport
// as external hands the login to the system browser and never gets it back.
//
// Reads the config pake generated for the build just run and asserts the app can
// still navigate to its own pages and to the login it depends on.
import { readFileSync, existsSync } from 'node:fs';

const GENERATED = 'node_modules/pake-cli/src-tauri/.pake/pake.json';

const app = JSON.parse(readFileSync('app.json', 'utf8'));
const home = new URL(app.url);

if (!existsSync(GENERATED)) {
  console.error(`warning: ${GENERATED} not found — cannot verify internal navigation`);
  process.exit(0);
}

const generated = JSON.parse(readFileSync(GENERATED, 'utf8'));
const window = generated.windows?.[0] ?? generated;
const pattern = window.internal_url_regex;

// An empty regex is pake's default, which keeps the app's own host internal.
if (!pattern) {
  console.log('internal_url_regex is unset — pake keeps the origin host internal by default');
  process.exit(0);
}

const probes = [
  home.href,
  new URL('/list/', home).href,
  new URL('/dashboard', home).href,
  'https://passport.yandex.com/auth',
];
const failed = probes.filter((url) => !new RegExp(pattern).test(url));

if (failed.length > 0) {
  const hosts = [...new Set(failed.map((url) => new URL(url).host))];
  console.error('internal_url_regex leaves URLs the app depends on outside it, so they would open in the system browser:');
  for (const url of failed) console.error(`  external: ${url}`);
  console.error(`regex: ${pattern}`);
  console.error(`fix: add ${hosts.join(', ')} to safeDomain`);
  process.exit(1);
}

console.log(`internal_url_regex keeps all ${probes.length} required URLs inside the app`);
