// Accessibility contract checks (issue #61). Source-level and dependency-free,
// like site.test.mjs: they pin the accessibility affordances of the app shell,
// primary navigation, logger grading controls, and plate calculator so a
// refactor cannot silently drop a label, re-disable zoom, or hide keyboard
// focus. They assert the SOURCE because this harness has no DOM; anything
// runtime-conditional is asserted where the attribute is authored.
import { readFileSync } from "node:fs";

let pass = 0, fail = 0;
function ok(cond, msg) { if (cond) { pass++; } else { fail++; console.error("FAIL:", msg); } }

const read = (path) => readFileSync(new URL(`../${path}`, import.meta.url), "utf8");

// ---- App shell: zoom, landmarks, live regions ----
const shell = read("app/index.html");
const viewport = /<meta name="viewport" content="([^"]*)"/.exec(shell)?.[1] || "";
ok(!/user-scalable\s*=\s*(no|0)/.test(viewport) && !/maximum-scale/.test(viewport),
  "the app viewport permits pinch zoom (no user-scalable=no, no maximum-scale)");
ok(/<nav id="tabbar" aria-label=/.test(shell), "the primary navigation landmark is named");
ok(/<main id="view">/.test(shell), "the content area is a main landmark");
ok(/id="toast" role="status" aria-live="polite"/.test(shell),
  "toasts announce politely to assistive tech");
ok(/id="fab" aria-label="Plate calculator"/.test(shell),
  "the icon-only plate-calculator button carries a name");

// ---- Primary navigation ----
const app = read("app/js/app.js");
ok(/setAttribute\("aria-current", "page"\)/.test(app),
  "the active tab exposes aria-current, not only a CSS class");
ok(/ui\.h\("span", \{ text: t\.label \}\)/.test(app),
  "tab buttons carry visible text labels, not icons alone");

// ---- Keyboard focus visibility ----
const css = read("app/styles.css");
ok(css.indexOf(':root, :root[data-theme="carbon"]') >= 0
  && css.indexOf(':root, :root[data-theme="carbon"]') < css.indexOf(':root[data-theme="memento"]'),
  "Carbon tokens paint before JavaScript applies the persisted theme (no light/brass flash)");
// Every selectable theme defines the same three surface levels, and every
// text/semantic token clears WCAG AA on each of them. The primary action pair
// (accent fill + its foreground) is checked separately: the foreground is a
// per-theme token, never a hard-coded near-black, so a light theme with a
// deep accent still gets a legible label.
const themeBlock = (name) => (name === "carbon"
  ? /:root, :root\[data-theme="carbon"\]\s*\{([^}]*)\}/
  : new RegExp(`:root\\[data-theme="${name}"\\]\\s*\\{([^}]*)\\}`)).exec(css)?.[1] || "";
const tokenIn = (block, name) => new RegExp(`--${name}:\\s*(#[0-9a-f]{6})`, "i").exec(block)?.[1];
const relativeLuminance = (hex) => {
  const channels = [1, 3, 5].map((start) => Number.parseInt(hex.slice(start, start + 2), 16) / 255)
    .map((value) => value <= 0.04045 ? value / 12.92 : ((value + 0.055) / 1.055) ** 2.4);
  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
};
const contrast = (a, b) => {
  const values = [relativeLuminance(a), relativeLuminance(b)].sort((x, y) => y - x);
  return (values[0] + 0.05) / (values[1] + 0.05);
};
const clearsAA = (a, b) => Boolean(a && b) && contrast(a, b) >= 4.5;
const THEMES = ["carbon", "memento", "titanium", "slate", "system"];
const systemDark = /@media \(prefers-color-scheme: dark\)\s*\{\s*:root\[data-theme="system"\]\s*\{([^}]*)\}/.exec(css)?.[1] || "";
for (const [theme, block] of [...THEMES.map((t) => [t, themeBlock(t)]), ["system (dark)", systemDark]]) {
  const surfaces = ["bg", "card", "card2"].map((name) => tokenIn(block, name));
  ok(surfaces.every(Boolean), `${theme} defines all three surface levels`);
  ok(["text", "muted", "accent", "warn", "hard", "good"].every((name) =>
    surfaces.every((surface) => clearsAA(tokenIn(block, name), surface))),
  `${theme} text and semantic tokens meet WCAG AA on every app elevation`);
  ok(clearsAA(tokenIn(block, "on-accent"), tokenIn(block, "accent")),
    `${theme} primary action foreground meets WCAG AA on its accent fill`);
}
ok(/:root\[data-theme="titanium"\]\s*\{[^}]*color-scheme:\s*light/.test(css),
  "Titanium declares itself a light theme so form controls and scrollbars follow");
ok(!/color:\s*#0b0b0c|color:\s*#16090a|color:\s*#041018/.test(css),
  "no accent-filled control hard-codes its foreground; they read --on-accent");
ok(/button:focus-visible[^{]*\{/.test(css), "buttons have a visible keyboard-focus style");
ok(/--focus:\s*var\(--accent\)/.test(css), "one --focus token, defined once, follows the active theme's accent");
ok(!/focus(?:-visible)?[^{]*\{[^}]*var\(--accent\)/.test(css),
  "every focus ring reads --focus, never the accent directly");
ok(/input:focus|input:focus-visible/.test(css), "text inputs have a visible focus style");

// ---- Logger grading controls: one labelling pattern for quality and RIR ----
const session = read("app/js/views/session.js");
ok(/aria-label[^\n]*Set quality: \$\{quality \|\| "not graded"\}/.test(session),
  "the quality button names itself and its state");
ok(/aria-label[^\n]*Reps in reserve: \$\{rir \? C\.SET_RIR_LABELS\[rir\] : "not graded"\}/.test(session),
  "the RIR button names itself and its state in words");
ok((session.match(/class: "microlabel"/g) || []).length >= 2,
  "both grading buttons carry an always-visible micro-caption (one pattern, not two)");
ok(/aria-label[^\n]*Set status: \$\{s\.status\}/.test(session),
  "the status button announces its state");
ok(/\.flagbtn\.labeled \.microlabel/.test(css),
  "the grading micro-caption is styled inside the 44px tap target");

// ---- Plate calculator / loadout graphics ----
const barbell = read("app/js/barbell.js");
ok(/role: "img"/.test(barbell) && /aria-label[^\n]*barbell/i.test(barbell),
  "the barbell graphic is an image with a spoken load");
ok(/plateBadgeSVG/.test(barbell) && /aria-label[^\n]*plate/i.test(barbell),
  "readable plate denomination badges also carry spoken labels");
ok(/\["white", "yellow", "green"\]\.includes\(token\) \? "#24262a" : "#fff"/.test(barbell),
  "yellow, white, and green plates use the high-contrast dark denomination ink");
ok(/aria-label[^\n]*Dumbbell/.test(barbell), "the dumbbell graphic carries a spoken load");
const plates = read("app/js/views/plates.js");
ok(/Achieved total, bar included/.test(barbell)
  && /\[solution\.totalLb, "lb", true\][\s\S]*\[C\.kgFromLb\(solution\.totalLb\), "kg", false\]/.test(barbell)
  && /loadoutSummary\(targetLb, solution\)/.test(plates),
  "the shared calculator/session total is announced and displayed pounds first, then kilograms");
ok(/prefers-reduced-motion: reduce/.test(css), "motion can be reduced at the operating-system level");
ok(/tabindex: "0"[\s\S]*data-plate-denomination/.test(barbell),
  "every rendered plate denomination is keyboard inspectable");

// ---- Session lifecycle: destructive discard is confirmed ----
const home = read("app/js/views/home.js");
ok((home.match(/Discard this open session\?/g) || []).length >= 2,
  "discarding an open session (hero and list) always confirms first");
ok(/Bank completed work\?/.test(session),
  "banking with unfinished sets asks before crediting only completed work");

console.log(`\n${pass} a11y contract assertions passed, ${fail} failed`);
process.exit(fail ? 1 : 0);
