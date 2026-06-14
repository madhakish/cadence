// Today — resume/open session, next-up suggestions, gym tag, protein.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { Sessions, Tracks, Gyms, Settings, Protein, iso } from "../db.js";
import { createSessionFromTrack, createBlankSession, openSession } from "./session.js";

export async function render(host) {
  const [open, tracks, gym, settings, proteinTotal] = await Promise.all([
    Sessions.open(), Tracks.all(), Gyms.default(), Settings.get(), Protein.todayTotal(),
  ]);
  const root = ui.h("div");

  if (open) {
    root.append(ui.h("div", { class: "card" },
      ui.h("button", { class: "btn primary wide", text: `▶︎ Resume session — ${ui.fmtDate(open.date)}`, onClick: () => openSession(open.id) })));
  }

  // Next up
  root.append(ui.h("div", { class: "section-title", text: "Next up" }));
  const list = ui.h("div", { class: "card list" });
  tracks.sort((a, b) => a.exerciseName.localeCompare(b.exerciseName));
  if (!tracks.length) list.append(ui.h("div", { class: "muted", text: "No tracked lifts yet. Add progression in Settings." }));
  for (const t of tracks) {
    const sug = t.mode === "cycle" ? C.planFor({ cycleNumber: t.cycleNumber, baseWeightLb: t.baseWeightLb, nextPhase: t.nextPhase, incrementLb: t.incrementLb }) : C.linearPlan(t.baseWeightLb);
    list.append(ui.h("div", { class: "row", onClick: () => start(t) },
      ui.h("div", { class: "lead" },
        ui.h("span", { class: "title", text: t.exerciseName }),
        ui.h("span", { class: "sub accent", text: C.sessionPlanLabel(sug) }),
        t.mode === "cycle" ? ui.h("span", { class: "sub", text: `Cycle ${t.cycleNumber} · advances when you bank it` }) : null),
      ui.h("span", { class: "chev" })));
  }
  root.append(list);
  root.append(ui.h("button", { class: "btn ghost wide", text: "Blank session", onClick: async () => openSession(await createBlankSession()) }));

  // Gym tag
  root.append(ui.h("div", { class: "section-title", text: "Gym" }));
  root.append(ui.h("div", { class: "card" },
    ui.h("button", { class: "btn wide", text: "🎫 Gym tag", onClick: () => showGymTag(gym) }),
    ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: gym && gym.barcodeImage ? "Full brightness, ready to scan." : "Add a barcode photo in Settings → Gyms." })));

  // Protein
  root.append(ui.h("div", { class: "section-title", text: "Protein" }));
  const total = ui.h("span", { class: "big mono", text: `${Math.round(proteinTotal)} g` });
  const card = ui.h("div", { class: "card" },
    ui.h("div", { class: "row", style: { borderBottom: "0" } }, total, ui.h("span", { class: "muted", text: `/ ${Math.round(settings.proteinTargetGrams)} g today` })),
    ui.h("div", { class: "btn-row" },
      ui.h("button", { class: "btn sm", text: "Shake ~45g", onClick: () => logProtein(45, "Shake") }),
      ui.h("button", { class: "btn sm", text: "Meat ~50g", onClick: () => logProtein(50, "Meat") }),
      ui.h("button", { class: "btn sm ghost", text: "More →", onClick: () => ui.nav.go("body") })));
  root.append(card);

  host.replaceChildren(root);

  async function start(track) {
    const id = await createSessionFromTrack(track);
    openSession(id);
  }
  async function logProtein(grams, label) {
    await Protein.add({ date: iso(new Date()), grams, label });
    ui.toast(`+${grams}g ${label.toLowerCase()}`);
    ui.nav.refresh();
  }
}

function showGymTag(gym) {
  ui.sheet({
    title: gym ? gym.name : "Gym tag",
    build: (c) => {
      if (gym && gym.barcodeImage) {
        c.append(ui.h("img", { class: "gym-img", src: gym.barcodeImage, alt: "Membership barcode" }));
        c.append(ui.h("div", { class: "muted", style: { textAlign: "center", marginTop: "8px" }, text: gym.barcodeLabel || "Membership tag" }));
        c.append(ui.h("div", { class: "muted", style: { textAlign: "center", fontSize: "12px", marginTop: "4px" }, text: "Turn screen brightness up to scan." }));
      } else {
        c.append(ui.empty("🎫", "No tag stored. Add a barcode photo in Settings → Gyms."));
      }
    },
  });
}
