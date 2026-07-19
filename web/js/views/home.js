// Today — resume/open session, next-up suggestions, gym tag, protein.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { sparkline } from "../charts.js";
import { barbellSVG, dumbbellSVG } from "../barbell.js";
import { Sessions, Tracks, Gyms, Settings, Protein, Programs, Exercises, iso, topSet } from "../db.js";
import { createSessionFromTrack, createBlankSession, createSessionFromProgramDay, neatProgramWeight, openSession } from "./session.js";

const orderedSlots = (slots = [], roleAwareLegacy = false) => {
  const allLegacy = slots.length > 1 && slots.every((slot) => (slot.order ?? 0) === (slots[0].order ?? 0));
  return [...slots].sort((a, b) => {
    if (allLegacy && roleAwareLegacy) {
      const role = (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1);
      if (role) return role;
    }
    return (a.order ?? 0) - (b.order ?? 0) || a.exerciseName.localeCompare(b.exerciseName);
  });
};

export async function render(host) {
  const [openSessions, tracks, gym, settings, proteinTotal, program, allExercises, completed] = await Promise.all([
    Sessions.openAll(), Tracks.all(), Gyms.default(), Settings.get(), Protein.todayTotal(), Programs.active(), Exercises.all(), Sessions.completed(),
  ]);
  // Last 8 top working weights for a lift, oldest→newest (sparkline source).
  const topsFor = (name) => completed
    .map((s) => ({
      d: new Date(s.date),
      // max across ALL entries of the lift that day (a session can hold the
      // same exercise in two sections)
      top: Math.max(...(s.exercises || []).filter((x) => x.exerciseName === name)
        .map((x) => topSet(x)).filter(Boolean).map((t) => t.weightLb), -Infinity),
    }))
    .filter((x) => x.top > -Infinity)
    .sort((a, b) => a.d - b.d)
    .map((x) => x.top)
    .slice(-8);
  const exMap = new Map(allExercises.map((e) => [e.name, e]));
  const barLb = C.barLb(gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb);
  const root = ui.h("div");

  // Arrival is the first workflow, even though it lasts only seconds: this is
  // the keychain replacement and must beat all training content to the screen.
  root.append(ui.h("div", { class: "card gym-tag-hero" },
    ui.h("button", { class: "btn primary wide", style: { minHeight: "58px", justifyContent: "space-between" },
      onClick: () => showGymTag(gym) },
      ui.h("span", { text: "▤  Gym Tag" }),
      ui.h("span", { class: "sub", text: gym && gym.barcodeImage ? "Ready to scan ›" : "Add barcode ›" }))));

  const todayKey = new Date().toLocaleDateString("en-CA");
  if (settings.gymTagFirstLaunchOfDay && gym?.barcodeImage
      && localStorage.getItem("cadenceGymTagAutoDay") !== todayKey) {
    localStorage.setItem("cadenceGymTagAutoDay", todayKey);
    queueMicrotask(() => showGymTag(gym));
  }

  if (openSessions.length) {
    root.append(ui.h("div", { class: "section-title", text: "Open sessions" }));
    const openCard = ui.h("div", { class: "card list" });
    for (const open of openSessions) {
      const names = (open.exercises || []).map((entry) => entry.exerciseName).filter(Boolean);
      const summary = names.length ? names.slice(0, 2).join(" · ") : "Blank session";
      openCard.append(ui.h("div", { class: "row" },
        ui.h("button", { class: "btn primary", style: { flex: "1" }, text: `▶︎ ${summary} — ${ui.fmtDate(open.date)}`, onClick: () => openSession(open.id) }),
        ui.h("button", { class: "btn ghost danger", "aria-label": `Discard ${summary}`, text: "Discard", onClick: () => {
          ui.actionSheet("Discard this open session? Completed history and the program are unchanged.", [
            { label: "Discard session", role: "destructive", onClick: async () => { await Sessions.del(open.id); ui.nav.refresh(); } },
            { label: "Cancel", role: "cancel", onClick: () => {} },
          ]);
        } })));
    }
    root.append(openCard);
  }

  // Program — the next scheduled day
  const ownedNames = new Set();
  if (program && program.days.length) {
    const day = program.days.find((d) => d.order === program.nextDayIndex) || program.days[0];
    for (const d of program.days) for (const l of d.lifts) ownedNames.add(l.exerciseName);
    const phase = C.PHASES[program.currentWeek] || C.PHASES[1];
    root.append(ui.h("div", { class: "section-title", text: `${program.name} · Cycle ${program.cycleNumber}` }));
    const card = ui.h("div", { class: "card" },
      ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px", cursor: "pointer" },
        onClick: () => workoutPreview(program, day, { exMap, gym, barLb }) },
        ui.h("span", { class: "title", text: day.name }),
        ui.h("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
          ui.wave(program.currentWeek),
          ui.h("span", { class: "sub accent", text: phase.name }),
          ui.h("span", { class: "chev" }))));
    const lifts = orderedSlots(day.lifts, true);
    for (const l of lifts) {
      const ex = exMap.get(l.exerciseName);
      const plan = C.programPlanFor({ cycleNumber: program.cycleNumber, baseWeightLb: l.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 },
        program.roundingLb, ex?.type, ex?.movementGroup, l.role, program.focus, l.prescription || "automatic");
      // Preview the same snapped weight the session will store (secondary barbell lifts).
      plan.weightLb = neatProgramWeight(plan.weightLb, ex, l.role === "main", barLb, program.roundingLb, gym);
      card.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
        ui.h("div", { class: "lead" },
          ui.h("span", { class: "title", text: l.exerciseName }),
          ui.h("span", { class: "sub", text: l.role })),
        ui.h("div", { style: { textAlign: "right" } },
          ui.h("div", { class: "wt-big mono", text: ui.fmtWeight(plan.weightLb) }),
          ui.h("div", { class: "sub mono", text: `${plan.sets}×${plan.reps}` }))));
      // The bar you'll load / the pair you'll grab — every wave lift, matching
      // the preview (a complementary barbell lift is loaded just the same).
      if (ex && ex.type === "barbell" && plan.weightLb > 0) {
        card.append(ui.h("div", { class: "barbell-wrap", style: { paddingLeft: "0" } },
          barbellSVG(plan.weightLb, C.primaryUnit(settings.unitDisplay), gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb, gym).svg));
      } else if (ex && ex.type === "dumbbell" && plan.weightLb > 0) {
        card.append(ui.h("div", { class: "barbell-wrap", style: { paddingLeft: "0" } },
          dumbbellSVG(plan.weightLb, C.primaryUnit(settings.unitDisplay)), ui.h("span", { class: "sub", text: C.primaryUnit(settings.unitDisplay) })));
      }
    }
    if (day.accessories.length) card.append(ui.h("div", { class: "sub", style: { marginTop: "6px" }, text: `+ ${day.accessories.map((a) => a.exerciseName).join(", ")}` }));
    card.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "10px" }, text: `Start ${day.name}`, onClick: async () => openSession(await createSessionFromProgramDay(program, day)) }));
    root.append(card);
  }

  // Next up — standalone tracked lifts not owned by the program
  // (workoutPreview is defined below the view builder)
  const orphanTracks = tracks.filter((t) => !ownedNames.has(t.exerciseName));
  root.append(ui.h("div", { class: "section-title", text: program ? "Other tracked lifts" : "Next up" }));
  const list = ui.h("div", { class: "card list" });
  orphanTracks.sort((a, b) => a.exerciseName.localeCompare(b.exerciseName));
  if (!orphanTracks.length) list.append(ui.h("div", { class: "muted", text: program ? "All your tracked lifts are in the program." : "No tracked lifts yet. Add progression in Settings." }));
  for (const t of orphanTracks) {
    const sug = t.mode === "cycle" ? C.planFor({ cycleNumber: t.cycleNumber, baseWeightLb: t.baseWeightLb, nextPhase: t.nextPhase, incrementLb: t.incrementLb }) : C.linearPlan(t.baseWeightLb);
    const tops = topsFor(t.exerciseName);
    list.append(ui.h("div", { class: "row", onClick: () => start(t) },
      ui.h("div", { class: "lead" },
        ui.h("span", { class: "title", text: t.exerciseName }),
        ui.h("span", { class: "sub accent", text: C.sessionPlanLabel(sug) }),
        t.mode === "cycle" ? ui.h("span", { class: "sub", text: `Cycle ${t.cycleNumber} · advances when you bank it` }) : null),
      tops.length >= 2 ? sparkline(tops) : null,
      ui.h("span", { class: "chev" })));
  }
  root.append(list);
  root.append(ui.h("button", { class: "btn ghost wide", text: "Blank session", onClick: async () => openSession(await createBlankSession()) }));

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
  let wakeLock = null;
  navigator.wakeLock?.request("screen").then((lock) => { wakeLock = lock; }).catch(() => {});
  ui.sheet({
    title: gym ? gym.name : "Gym tag",
    onClose: () => { wakeLock?.release().catch(() => {}); },
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

// Full read-only preview of a program day — browse the whole workout without
// creating a session; the Start button up top is what commits. Same preview
// math as the Today card, so preview and started session never disagree.
// (iOS mirror: WorkoutPreviewView.)
function workoutPreview(program, day, { exMap, gym, barLb }) {
  ui.pushScreen({
    title: day.name,
    build: (body) => {
      const phase = C.PHASES[program.currentWeek] || C.PHASES[1];
      body.append(ui.h("button", { class: "btn primary wide", text: `▶︎ Start ${day.name}`, onClick: async () => {
        openSession(await createSessionFromProgramDay(program, day));
      } }));
      body.append(ui.h("div", { class: "sub", style: { margin: "6px 4px" },
        text: `${program.name} · Cycle ${program.cycleNumber} · ${phase.name}` }));

      body.append(ui.h("div", { class: "section-title", text: "Lifts" }));
      const liftCard = ui.h("div", { class: "card" });
      const lifts = orderedSlots(day.lifts, true);
      if (!lifts.length) liftCard.append(ui.h("div", { class: "muted", text: "No wave lifts this day." }));
      for (const l of lifts) {
        const ex = exMap.get(l.exerciseName);
        const plan = C.programPlanFor({ cycleNumber: program.cycleNumber, baseWeightLb: l.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 },
          program.roundingLb, ex?.type, ex?.movementGroup, l.role, program.focus, l.prescription || "automatic");
        plan.weightLb = neatProgramWeight(plan.weightLb, ex, l.role === "main", barLb, program.roundingLb, gym);
        liftCard.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
          ui.h("div", { class: "lead" },
            ui.h("span", { class: "title", text: l.exerciseName }),
            ui.h("span", { class: "sub", text: l.role })),
          ui.h("div", { style: { textAlign: "right" } },
            ui.h("div", { class: "wt-big mono", text: ui.fmtWeight(plan.weightLb) }),
            ui.h("div", { class: "sub mono", text: `${plan.sets}×${plan.reps}` }))));
        if (ex && ex.type === "barbell" && plan.weightLb > 0) {
          liftCard.append(ui.h("div", { class: "barbell-wrap", style: { paddingLeft: "0" } },
            barbellSVG(plan.weightLb, C.primaryUnit(ui.prefs.unitDisplay), gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb, gym).svg));
        } else if (ex && ex.type === "dumbbell" && plan.weightLb > 0) {
          liftCard.append(ui.h("div", { class: "barbell-wrap", style: { paddingLeft: "0" } },
            dumbbellSVG(plan.weightLb, C.primaryUnit(ui.prefs.unitDisplay)), ui.h("span", { class: "sub", text: C.primaryUnit(ui.prefs.unitDisplay) })));
        }
      }
      body.append(liftCard);

      if (day.accessories.length) {
        body.append(ui.h("div", { class: "section-title", text: "Accessories" }));
        const accCard = ui.h("div", { class: "card" });
        for (const a of orderedSlots(day.accessories)) {
          const isTimed = exMap.get(a.exerciseName)?.type === "timed";
          accCard.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
            ui.h("span", { class: "title", text: a.exerciseName }),
            ui.h("span", { class: "sub mono", text: isTimed
              ? `${a.sets} × ${C.cardioDurationLabel(a.targetSeconds || 30)}`
              : (a.weightLb > 0 ? `${a.sets}×${a.currentReps} @ ${ui.fmtWeight(a.weightLb)}` : `${a.sets}×${a.currentReps}`) })));
        }
        body.append(accCard);
      }
    },
  });
}
