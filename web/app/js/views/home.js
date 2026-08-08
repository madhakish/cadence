// Today — resume/open session, next-up suggestions, gym tag.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { sparkline } from "../charts.js";
import { barbellSVG, dumbbellSVG, prescriptionPlateDetails } from "../barbell.js";
import { Sessions, Tracks, Gyms, Settings, Programs, Exercises, Checkins, CoachingDecisions, topSet } from "../db.js";
import { coachingReport, applyCoachingRecommendation, coachingDecision } from "../coaching-adapter.js";
import { createSessionFromTrack, createBlankSession, createSessionFromProgramDay, neatProgramWeight, openSession, reconcileRecoveryBridge } from "./session.js";

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

const barbellPrescriptionView = (achievedLb, targetLb, unit, gym) => {
  const bar = gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb;
  const wrap = ui.h("div", { class: "barbell-wrap", style: { paddingLeft: "0" } },
    barbellSVG(achievedLb, unit, bar, gym).svg);
  for (const detail of prescriptionPlateDetails(targetLb, achievedLb, unit, bar, gym)) {
    wrap.append(ui.h("span", { class: `sub plate-detail${detail.kind === "target" ? " warn" : ""}`, text: detail.text }));
  }
  return wrap;
};

export async function render(host) {
  const [openSessions, tracks, gym, settings, program, allExercises, completed, decisions, checkins] = await Promise.all([
    Sessions.openAll(), Tracks.all(), Gyms.default(), Settings.get(), Programs.active(), Exercises.all(), Sessions.completed(), CoachingDecisions.all(), Checkins.all(),
  ]);
  const recoveryCompletion = await reconcileRecoveryBridge(program, completed);
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
  const todayKey = new Date().toLocaleDateString("en-CA");
  const primaryOpen = [...openSessions].sort((a, b) => new Date(b.date) - new Date(a.date))[0];
  const nextProgramDay = program?.days?.find((day) => day.order === program.nextDayIndex) || program?.days?.[0];

  // Conditional hero: the next physical action always wins the top slot.
  if (primaryOpen) {
    const names = (primaryOpen.exercises || []).map((entry) => entry.exerciseName).filter(Boolean);
    const summary = names.length ? names.slice(0, 2).join(" · ") : "Blank session";
    root.append(ui.h("div", { class: "card today-hero" },
      ui.h("button", { class: "btn primary wide", style: { minHeight: "64px", justifyContent: "space-between" },
        text: `▶︎ Resume workout · ${summary}`, onClick: () => openSession(primaryOpen.id) }),
      ui.h("button", { class: "btn ghost danger wide", text: "Discard session", onClick: () => {
        ui.actionSheet("Discard this open session? Completed history and the program are unchanged.", [
          { label: "Discard session", role: "destructive", onClick: async () => { await Sessions.del(primaryOpen.id); ui.nav.refresh(); } },
          { label: "Cancel", role: "cancel", onClick: () => {} },
        ]);
      } })));
  } else if (program && nextProgramDay) {
    root.append(ui.h("div", { class: "card today-hero" },
      ui.h("button", { class: "row wide", style: { minHeight: "64px", textAlign: "left" },
        onClick: () => workoutPreview(program, nextProgramDay, { exMap, gym, barLb }) },
      ui.h("div", { class: "lead" }, ui.h("span", { class: "sub", text: "Next workout" }),
        ui.h("span", { class: "big", text: nextProgramDay.name }),
        ui.h("span", { class: "sub", text: `${program.name} · Cycle ${program.cycleNumber}` })),
      ui.rotation(program.currentWeek)),
      ui.h("button", { class: "btn primary wide", text: `Start ${nextProgramDay.name}`,
        onClick: async () => openSession(await createSessionFromProgramDay(program, nextProgramDay)) })));
  }

  if (program?.days?.length) {
    const days = [...program.days].sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
    root.append(ui.h("div", { class: "day-sequence", role: "status", ariaLabel: `${nextProgramDay?.name || "Next day"} is now` },
      ...days.flatMap((day, index) => [
        ui.h("span", { class: day.order === program.nextDayIndex ? "now" : "",
          text: `${day.order === program.nextDayIndex ? "NOW " : day.order < program.nextDayIndex ? "✓ " : ""}${day.name}` }),
        index < days.length - 1 ? document.createTextNode(" → ") : null,
      ].filter(Boolean))));
  }

  // The keychain replacement is prominent until today's scan, then compact.
  const gymProminent = !gym?.barcodeImage || localStorage.getItem("cadenceGymTagAutoDay") !== todayKey;
  root.append(ui.h("div", { class: "card gym-tag-hero" },
    ui.h("button", { class: `btn ${gymProminent ? "primary" : "ghost"} wide`,
      style: { minHeight: "44px", justifyContent: "space-between" },
      onClick: () => { localStorage.setItem("cadenceGymTagAutoDay", todayKey); showGymTag(gym); } },
      ui.h("span", { text: gymProminent ? "▤  Gym Tag" : "▤  Scan gym tag" }),
      gymProminent ? ui.h("span", { class: "sub", text: gym && gym.barcodeImage ? "Ready to scan ›" : "Add barcode ›" }) : null)));

  if (recoveryCompletion) {
    root.append(ui.h("div", { class: "card" },
      ui.h("div", { class: "row", style: { borderBottom: "0" } },
        ui.h("span", { class: "accent", text: `↻ ${recoveryCompletion.message}` }))));
  }

  if (settings.gymTagFirstLaunchOfDay && gym?.barcodeImage
      && localStorage.getItem("cadenceGymTagAutoDay") !== todayKey) {
    localStorage.setItem("cadenceGymTagAutoDay", todayKey);
    queueMicrotask(() => showGymTag(gym));
  }

  if (openSessions.length > 1) {
    root.append(ui.h("div", { class: "section-title", text: "Other open sessions" }));
    const openCard = ui.h("div", { class: "card list" });
    for (const open of openSessions.filter((item) => item.id !== primaryOpen.id)) {
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

  // `program &&` first: with no active program there is nothing to coach, and
  // the block below dereferences it unconditionally. An optional chain here
  // reads as a presence check but isn't one — `undefined !== false` is true.
  if (program && program.coachEnabled !== false) {
    const report = coachingReport(program, completed, exMap, checkins);
    const handled = new Set(decisions.filter((decision) => (decision.programId || decision.programID) === (program.uuid || program.id))
      .map((decision) => decision.recommendationId || decision.recommendationID));
    const visible = report.recommendations.filter((recommendation) => !handled.has(recommendation.id)).slice(0, 3);
    const latest = report.rotations.at(-1);
    const coach = ui.h("button", { class: "card row wide coach-summary",
      onClick: () => showCoachDetail({ program, report, visible, latest, allExercises }) },
        ui.h("div", { class: "lead" },
          ui.h("span", { class: `title readiness-${report.currentReadiness}`, text: `Coach · ${report.currentReadiness[0].toUpperCase() + report.currentReadiness.slice(1)}` }),
          ui.h("span", { class: "sub", text: latest?.reasons?.[0] || "Bank program days to establish an output baseline." })),
        ui.h("span", { class: "readiness-dots", ariaLabel: "Recent rotation readiness" },
          ...report.rotations.slice(-4).map((rotation) => ui.h("i", { class: `readiness-${rotation.readiness}` }))),
        ui.h("span", { class: "pill accent", text: `${visible.length} recommendation${visible.length === 1 ? "" : "s"}` }));
    root.append(coach);
  }

  // Program — the next scheduled day
  const ownedNames = new Set();
  if (program && program.days.length) {
    const day = program.days.find((d) => d.order === program.nextDayIndex) || program.days[0];
    for (const d of program.days) for (const l of d.lifts) ownedNames.add(l.exerciseName);
    root.append(ui.h("div", { class: "section-title", text: `${program.name} · Cycle ${program.cycleNumber}` }));
    // Advisory only. The preference used to be write-only — a stepper set it
    // and nothing read it back.
    const lastBanked = completed[0]?.date ? new Date(completed[0].date) : null;
    const daysSinceLast = lastBanked
      ? Math.floor((Date.now() - lastBanked.getTime()) / 86400000) : null;
    const shortfall = C.sessionSpacingShortfall(daysSinceLast, program.preferredSessionSpacingDays ?? 0);
    const card = ui.h("div", { class: "card" },
      ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px", cursor: "pointer" },
        onClick: () => workoutPreview(program, day, { exMap, gym, barLb }) },
        ui.h("span", { class: "title", text: day.name }),
        ui.h("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
          // Position only. The phase NAME moved onto the slots it actually
          // describes — this counter is shared by slots whose prescriptions
          // have nothing to do with each other.
          ui.rotation(program.currentWeek),
          // Decorative: the glyph beside it already announces the rotation, so
          // without this VoiceOver reads it twice. Matches HomeView.swift.
          ui.h("span", { class: "sub accent mono", "aria-hidden": "true",
            text: `R${Math.min(Math.max(program.currentWeek, 1), C.DELOAD_WEEK)}` }),
          ui.h("span", { class: "chev" }))));
    if (shortfall != null) {
      card.append(ui.h("div", { class: "sub", style: { padding: "2px 0 6px" },
        text: `${daysSinceLast === 0 ? "Trained today" : `${daysSinceLast} day${daysSinceLast === 1 ? "" : "s"} since your last session`}`
          + ` · you prefer ${program.preferredSessionSpacingDays}. Train anyway if today is the day that works.` }));
    }
    const lifts = orderedSlots(day.lifts, true);
    for (const l of lifts) {
      const ex = exMap.get(l.exerciseName);
      const plan = C.programPlanFor({ cycleNumber: program.cycleNumber, baseWeightLb: l.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 },
        program.roundingLb, ex?.type, ex?.movementGroup, l.role, program.focus, l.prescription || "automatic",
        { ...l, workingSets: l.doubleProgressionSets ?? 3 },
        C.volumeIncrementSets(l.stallCount ?? 0, program.maximumAddedSetsPerRotation ?? 6));
      // Preview the same snapped weight the session will store (secondary barbell lifts).
      const targetWeightLb = plan.weightLb;
      plan.weightLb = neatProgramWeight(plan.weightLb, ex, l.role === "main" || C.buildsOwnSessionShape(l.prescription || "automatic"), barLb, program.roundingLb, gym, program.currentWeek);
      card.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
        ui.h("div", { class: "lead" },
          ui.h("span", { class: "title", text: l.exerciseName }),
          ui.slotBadge(l, program.currentWeek, ex?.movementGroup, program.focus)),
        ui.h("div", { style: { textAlign: "right" } },
          ui.h("div", { class: "wt-big mono", text: ui.fmtWeight(plan.weightLb) }),
          ui.h("div", { class: "sub mono", text: `${plan.sets}×${plan.reps}` }))));
      // The bar you'll load / the pair you'll grab — every wave lift, matching
      // the preview (a complementary barbell lift is loaded just the same).
      if (ex && ex.type === "barbell" && plan.weightLb > 0) {
        card.append(barbellPrescriptionView(
          plan.weightLb, targetWeightLb, C.primaryUnit(settings.unitDisplay), gym,
        ));
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

  host.replaceChildren(root);

  async function start(track) {
    const id = await createSessionFromTrack(track);
    openSession(id);
  }
}

function showCoachDetail({ program, report, visible, latest, allExercises }) {
  ui.sheet({
    title: "Coach",
    build: (content, api) => {
      content.append(ui.h("div", { class: "card" },
        ui.h("div", { class: `title readiness-${report.currentReadiness}`,
          text: `${report.currentReadiness[0].toUpperCase() + report.currentReadiness.slice(1)} · per rotation` }),
        ui.h("div", { class: "sub", text: latest?.reasons?.[0] || "Bank program days to establish an output baseline." }),
        latest ? ui.h("div", { class: "sub mono", style: { marginTop: "6px" },
          text: `${latest.completedWorkingSets}/${latest.plannedWorkingSets} work sets · ${Math.round(latest.conditioningMinutes)} conditioning min` }) : null));
      if (!visible.length) content.append(ui.h("div", { class: "card muted", text: "No pending recommendations." }));
      for (const recommendation of visible) {
        content.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "title", text: recommendation.title }),
          ui.h("div", { class: "sub", style: { margin: "6px 0 10px" }, text: recommendation.explanation }),
          ui.h("div", { class: "btn-row" },
            ui.h("button", { class: "btn primary", text: "Apply", onClick: async () => {
              const proposed = structuredClone(program);
              try {
                const message = await applyCoachingRecommendation(proposed, recommendation, allExercises);
                await Programs.saveWithDecision(proposed,
                  coachingDecision(proposed, recommendation, "accepted", latest?.reasons || []));
                api.close(); ui.toast(message); ui.nav.refresh();
              } catch (error) {
                ui.toast(error?.message || "That change could not be applied.");
              }
            } }),
            ui.h("button", { class: "btn ghost", text: "Not now", onClick: async () => {
              await CoachingDecisions.save(coachingDecision(program, recommendation, "deferred", latest?.reasons || []));
              api.close(); ui.nav.refresh();
            } }))));
      }
    },
  });
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
      body.append(ui.h("button", { class: "btn primary wide", text: `▶︎ Start ${day.name}`, onClick: async () => {
        openSession(await createSessionFromProgramDay(program, day));
      } }));
      // Position, not phase: this header sits above slots whose prescriptions
      // may have nothing to do with each other.
      body.append(ui.h("div", { class: "sub", style: { margin: "6px 4px" },
        text: `${program.name} · Cycle ${program.cycleNumber} · ${C.rotationLabel(program.currentWeek)}` }));

      body.append(ui.h("div", { class: "section-title", text: "Lifts" }));
      const liftCard = ui.h("div", { class: "card" });
      const lifts = orderedSlots(day.lifts, true);
      if (!lifts.length) liftCard.append(ui.h("div", { class: "muted", text: "No program lifts this day." }));
      for (const l of lifts) {
        const ex = exMap.get(l.exerciseName);
        const plan = C.programPlanFor({ cycleNumber: program.cycleNumber, baseWeightLb: l.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 },
          program.roundingLb, ex?.type, ex?.movementGroup, l.role, program.focus, l.prescription || "automatic",
          { ...l, workingSets: l.doubleProgressionSets ?? 3 },
          C.volumeIncrementSets(l.stallCount ?? 0, program.maximumAddedSetsPerRotation ?? 6));
        const targetWeightLb = plan.weightLb;
        plan.weightLb = neatProgramWeight(plan.weightLb, ex, l.role === "main" || C.buildsOwnSessionShape(l.prescription || "automatic"), barLb, program.roundingLb, gym, program.currentWeek);
        liftCard.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
          ui.h("div", { class: "lead" },
            ui.h("span", { class: "title", text: l.exerciseName }),
            ui.slotBadge(l, program.currentWeek, ex?.movementGroup, program.focus)),
          ui.h("div", { style: { textAlign: "right" } },
            ui.h("div", { class: "wt-big mono", text: ui.fmtWeight(plan.weightLb) }),
            ui.h("div", { class: "sub mono", text: `${plan.sets}×${plan.reps}` }))));
        if (ex && ex.type === "barbell" && plan.weightLb > 0) {
          liftCard.append(barbellPrescriptionView(
            plan.weightLb, targetWeightLb, C.primaryUnit(ui.prefs.unitDisplay), gym,
          ));
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
          const type = exMap.get(a.exerciseName)?.type;
          const isTimed = type === "timed" || type === "conditioning";
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
