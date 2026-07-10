// Bootstrap: service worker, seed, settings, tab bar, router, FAB.
import * as ui from "./ui.js";
import { Settings, ensureSeeded, syncLibrary } from "./db.js";
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
  await syncLibrary(); // top up the exercise library on already-seeded installs
  const s = await Settings.get();
  ui.prefs.unitDisplay = s.unitDisplay;

  buildChrome();
  await navigate("home");

  registerServiceWorker();
}

// Register the SW and surface a one-tap "Refresh" when a new build is deployed.
// On a cold launch the new worker takes over on its own; this prompt is for when
// an update lands while you're using the app.
function registerServiceWorker() {
  if (!("serviceWorker" in navigator)) return;

  let reloading = false;
  navigator.serviceWorker.addEventListener("controllerchange", () => {
    if (reloading) return;
    reloading = true;
    location.reload();
  });

  navigator.serviceWorker.register("sw.js").then((reg) => {
    reg.addEventListener("updatefound", () => {
      const incoming = reg.installing;
      if (!incoming) return;
      incoming.addEventListener("statechange", () => {
        // "installed" + an existing controller ⇒ this is an update, not first install.
        if (incoming.state === "installed" && navigator.serviceWorker.controller) {
          showUpdateBanner(reg);
        }
      });
    });
  }).catch((e) => console.warn("SW registration failed", e));
}

function showUpdateBanner(reg) {
  if (document.getElementById("update-banner")) return;
  const banner = ui.h("div", { id: "update-banner" },
    ui.h("span", { text: "New version available" }),
    ui.h("button", { class: "btn sm primary", text: "Refresh", onClick: () => {
      const w = reg.waiting || reg.installing;
      if (w) w.postMessage({ type: "SKIP_WAITING" }); // triggers controllerchange → reload
    } }),
    ui.h("button", { class: "btn sm ghost", text: "Later", onClick: () => banner.remove() }));
  document.body.append(banner);
}

boot();
