// Structural tests for the Pages deployment: the product site at the root and
// the PWA mounted underneath it at /app/.
//
// These are cheap string/filesystem checks, but they cover the two ways this
// layout breaks silently. A moved or renamed app asset produces a site that
// deploys fine and 404s in a gym; and the offline shell only works if every
// module the app imports is in the precache list, which nothing else enforces.
//
// Run: node tests/site.test.mjs
import { readFileSync, readdirSync, statSync, existsSync } from "node:fs";
import { join, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";

const WEB = fileURLToPath(new URL("../", import.meta.url));
const APP = join(WEB, "app");

let pass = 0, fail = 0;
const ok = (cond, msg) => { if (cond) pass++; else { fail++; console.error("FAIL:", msg); } };
const read = (path) => readFileSync(join(WEB, path), "utf8");

// Pages served from the site root. 404.html is deliberately excluded from the
// relative-link checks below: Pages serves it for missing URLs at any depth, so
// it has to use absolute paths.
const SITE_PAGES = ["index.html", "guide.html", "ios.html", "privacy.html"];
const ALL_PAGES = [...SITE_PAGES, "404.html"];

// ---- the deployment has both halves ----

for (const page of ALL_PAGES) {
  ok(existsSync(join(WEB, page)), `${page} exists at the site root`);
}
ok(existsSync(join(APP, "index.html")), "the PWA is mounted at app/index.html");
ok(existsSync(join(WEB, "site/site.css")), "the site stylesheet exists");
ok(!existsSync(join(WEB, "js")), "no app JavaScript is left at the site root");
ok(!existsSync(join(WEB, "styles.css")), "the app stylesheet is not at the site root");

// ---- every internal link and asset resolves ----

// Collect href/src targets, minus anchors, externals and mail links. A target
// ending in "/" is a directory, which Pages serves as its index.html.
const localTargets = (html) =>
  [...html.matchAll(/(?:href|src)="([^"]+)"/g)]
    .map((m) => m[1])
    .filter((href) => !/^(https?:|mailto:|data:|#|\/\/)/.test(href));

for (const page of SITE_PAGES) {
  const html = read(page);
  for (const target of localTargets(html)) {
    const [path] = target.split("#");
    if (!path) continue;
    const resolved = join(WEB, dirname(page), path.endsWith("/") ? `${path}index.html` : path);
    ok(existsSync(resolved), `${page} → ${target} resolves to a file that exists`);
  }
}

// 404.html cannot use relative paths, so assert the opposite there.
{
  const html = read("404.html");
  const targets = localTargets(html);
  ok(targets.length > 0, "404.html links somewhere");
  ok(targets.every((t) => t.startsWith("/cadence/")),
    "404.html uses project-absolute paths so it works at any URL depth");
  for (const target of targets) {
    const path = target.replace(/^\/cadence\//, "").split("#")[0];
    if (!path) continue;
    const resolved = join(WEB, path.endsWith("/") ? `${path}index.html` : path);
    ok(existsSync(resolved), `404.html → ${target} resolves to a file that exists`);
  }
}

// ---- the app is reachable and self-contained ----

for (const page of SITE_PAGES) {
  const html = read(page);
  ok(/(?:href)="app\/"/.test(html), `${page} links to the app at app/`);
}

{
  const appIndex = readFileSync(join(APP, "index.html"), "utf8");
  for (const asset of ["js/app.js", "styles.css", "manifest.webmanifest",
                       "icons/icon-192.png", "icons/apple-touch-icon.png"]) {
    ok(appIndex.includes(asset), `app/index.html references ${asset}`);
    ok(existsSync(join(APP, asset)), `app/${asset} exists`);
  }
  // Relative, not root-absolute: that is what lets the app move as one unit.
  ok(!/(?:href|src)="\/(?!\/)/.test(appIndex),
    "app/index.html uses relative asset paths so the whole app can be remounted");
}

// [INV-WEB-APP-SCOPE] The manifest keeps the installed app scoped to its own
// directory. Hard-coding "/cadence/app/" here would break local serving and any
// future custom domain.
{
  const manifest = JSON.parse(readFileSync(join(APP, "manifest.webmanifest"), "utf8"));
  ok(manifest.start_url === "./", "[INV-WEB-APP-SCOPE] manifest start_url is directory-relative");
  ok(manifest.scope === "./", "[INV-WEB-APP-SCOPE] manifest scope is directory-relative");
  for (const icon of manifest.icons) {
    ok(existsSync(join(APP, icon.src)), `manifest icon ${icon.src} exists`);
  }
}

// ---- the offline shell precaches every module the app can import ----

const walkJs = (dir) => readdirSync(dir).flatMap((name) => {
  const full = join(dir, name);
  return statSync(full).isDirectory() ? walkJs(full) : (name.endsWith(".js") ? [full] : []);
});

{
  const appWorker = readFileSync(join(APP, "sw.js"), "utf8");
  const modules = walkJs(join(APP, "js")).map((f) => relative(APP, f).split("\\").join("/"));
  ok(modules.length > 10, "found the app's JavaScript modules to check");
  for (const module of modules) {
    ok(appWorker.includes(`"${module}"`),
      `[INV-WEB-APP-SCOPE] offline shell precaches ${module} — an unlisted module breaks the app with no signal`);
  }
  ok(appWorker.includes("__BUILD__"),
    "app/sw.js keeps the build token the Pages deploy stamps, so installs actually update");
  ok(appWorker.includes('"./"') && appWorker.includes('"index.html"'),
    "app/sw.js precaches its own entry point");
}

// ---- the app's old scope stands down instead of serving a stale shell ----

// [INV-WEB-APP-SCOPE] The PWA used to live at the Pages root and registered a
// worker there. That registration outlives the move, so the root worker has to
// keep existing purely to retire itself.
{
  const retired = read("sw.js");
  ok(/registration\.unregister\(\)/.test(retired),
    "[INV-WEB-APP-SCOPE] the root worker unregisters itself");
  ok(/caches\.delete/.test(retired),
    "[INV-WEB-APP-SCOPE] the root worker drops the old app shell's caches");
  ok(!/addEventListener\(\s*["']fetch["']/.test(retired),
    "[INV-WEB-APP-SCOPE] the root worker serves nothing — no fetch handler");
  ok(/new URL\(\s*["']app\/["']/.test(retired),
    "[INV-WEB-APP-SCOPE] the root worker sends stranded windows to the app's new path");

  // Second safety net, on the page itself, for an install that reaches the site
  // before its worker updates.
  const index = read("index.html");
  ok(/display-mode: standalone/.test(index) && /replace\("\.\/app\/"\)/.test(index),
    "[INV-WEB-APP-SCOPE] a standalone launch of the site root redirects into the app");
}

// The site pages must not register a worker of their own: that would re-take the
// root scope the file above exists to release.
for (const page of ALL_PAGES) {
  ok(!/serviceWorker\s*\.\s*register/.test(read(page)),
    `${page} does not register a service worker`);
}

// ---- crawlability and metadata ----

for (const page of SITE_PAGES) {
  const html = read(page);
  ok(/<html lang="en">/.test(html), `${page} declares a language`);
  ok(/<meta name="viewport"[^>]+width=device-width/.test(html), `${page} is responsive`);
  ok(/<meta name="description" content="[^"]{40,}"/.test(html), `${page} has a real description`);
  ok(/<link rel="canonical" href="https:\/\/madhakish\.github\.io\/cadence\//.test(html),
    `${page} declares a canonical URL`);
  ok(/<title>[^<]{10,}<\/title>/.test(html), `${page} has a title`);
  ok(html.includes('class="skip"'), `${page} offers a skip-to-content link`);
}

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
