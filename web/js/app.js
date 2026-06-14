// Bootstrap: service worker, seed, settings, tab bar, router, FAB.
import * as ui from "./ui.js";
import { Settings, ensureSeeded } from "./db.js";
import * as home from "./views/home.js";
import * as history from "./views/history.js";
import * as body from "./views/body.js";
import * as signals from "./views/signals.js";
import * as settings from "./views/settings.js";
import { openPlateCalculator } from "./views/plates.js";
import { openSession } from "./views/session.js";

const TABS = [
  { id: "home", label: "Today", icon: "today", title: "Today", view: home },
  { id: "history", label: "History", icon: "history", title: "History", view: history },
  { id: "body", label: "Body", icon: "body", title: "Body", view: body },
  { id: "signals", label: "Signals", icon: "signals", title: "Signals", view: signals },
  { id: "settings", label: "Settings", icon: "settings", title: "Settings", view: settings },
];

let current = "home";
const viewEl = () => document.getElementById("view");

async function navigate(id) {
  const tab = TABS.find((t) => t.id === id) || TABS[0];
  current = tab.id;
  document.getElementById("screen-title").textContent = tab.title;
  document.getElementById("topbar-actions").replaceChildren();
  for (const b of document.querySelectorAll(".tab")) b.classList.toggle("active", b.dataset.id === tab.id);
  const host = viewEl();
  host.replaceChildren(ui.h("div", { class: "muted", style: { padding: "24px 4px" }, text: "…" }));
  try {
    await tab.view.render(host);
  } catch (err) {
    console.error(err);
    host.replaceChildren(ui.empty("⚠️", "Something went wrong loading this screen."));
  }
  host.scrollTop = 0;
}

function buildChrome() {
  const bar = document.getElementById("tabbar");
  bar.replaceChildren(...TABS.map((t) =>
    ui.h("button", { class: "tab", dataset: { id: t.id }, onClick: () => navigate(t.id) },
      ui.icon(t.icon), ui.h("span", { text: t.label }))
  ));
  const fab = document.getElementById("fab");
  fab.replaceChildren(ui.icon("plates"));
  fab.addEventListener("click", () => openPlateCalculator());
}

async function boot() {
  // wire navigation hub for the views
  ui.nav.go = navigate;
  ui.nav.refresh = () => navigate(current);
  ui.nav.openPlates = () => openPlateCalculator();
  ui.nav.openSession = (id) => openSession(id);

  await ensureSeeded();
  const s = await Settings.get();
  ui.prefs.unitDisplay = s.unitDisplay;

  buildChrome();
  await navigate("home");

  if ("serviceWorker" in navigator) {
    navigator.serviceWorker.register("sw.js").catch((e) => console.warn("SW registration failed", e));
  }
}

boot();
