// Today — resume/open session, next-up suggestions, gym tag.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { sparkline } from "../charts.js";
import { barbellSVG, dumbbellSVG, prescriptionPlateDetails } from "../barbell.js";
import { Sessions, Tracks, Gyms, Settings, Programs, Exercises, Checkins, CoachingDecisions, Intervals, intervalSnapshots, topSet, localDayKey } from "../db.js";
import { coachingReport, applyCoachingRecommendation, coachingDecision } from "../coaching-adapter.js";
import { createSessionFromTrack, createBlankSession, createSessionFromProgramDay, openSession, planningBase, previewProgramPlan, reconcileRecoveryBridge, volumeFallbackSets } from "./session.js";
import { gymTagShownOn, markGymTagShown } from "../gym-tag.js";
import { exerciseDetail } from "./settings.js";
import { openActivityLog } from "./activity.js";

const barbellPrescriptionView = (achievedLb, targetLb, unit, gym, stationDenomination = null, movementGroup = null) => {
  const bar = gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb;
  const wrap = ui.h("div", { class: "barbell-wrap", style: { paddingLeft: "0" } },
    barbellSVG(achievedLb, unit, bar, gym, null, stationDenomination, "compact",
      movementGroup === "olympic" ? "bumper" : "steel").svg);
  for (const detail of prescriptionPlateDetails(targetLb, achievedLb, unit, bar, gym, stationDenomination)) {
    wrap.append(ui.h("span", { class: `sub plate-detail${detail.kind === "target" ? " warn" : ""}`, text: detail.text }));
  }
  return wrap;
};

export async function render(host) {
  const [openSessions, tracks, gym, settings, program, allExercises, completed, decisions, checkins, intervals] = await Promise.all([
    Sessions.openAll(), Tracks.all(), Gyms.default(), Settings.get(), Programs.active(), Exercises.all(), Sessions.completed(), CoachingDecisions.all(), Checkins.all(), Intervals.all(),
  ]);
  const intervalSnaps = intervalSnapshots(intervals);
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
  const todayKey = localDayKey(new Date());
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
        onClick: () => workoutPreview(program, nextProgramDay, { exMap, gym, barLb, completed }) },
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
  const gymProminent = !gym?.barcodeImage || !gymTagShownOn(todayKey);
  root.append(ui.h("div", { class: "card gym-tag-hero" },
    ui.h("button", { class: `btn ${gymProminent ? "primary" : "ghost"} wide`,
      style: { minHeight: "44px", justifyContent: "space-between" },
      onClick: () => { markGymTagShown(todayKey); showGymTag(gym); } },
      ui.h("span", { text: gymProminent ? "▤  Gym Tag" : "▤  Scan gym tag" }),
      gymProminent ? ui.h("span", { class: "sub", text: gym && gym.barcodeImage ? "Ready to scan ›" : "Add barcode ›" }) : null)));

  if (recoveryCompletion) {
    root.append(ui.h("div", { class: "card" },
      ui.h("div", { class: "row", style: { borderBottom: "0" } },
        ui.h("span", { class: "accent", text: `↻ ${recoveryCompletion.message}` }))));
  }

  // A just-ended away interval with no session banked since deserves a
  // re-entry suggestion, not silent resumption at full loading. Advisory only
  // — it never blocks starting anything. Mirrors HomeView.returnFromAwayNote.
  if (C.recentReturnFromAway(
    Date.now(),
    completed[0]?.date ? new Date(completed[0].date).getTime() : null,
    intervalSnaps,
  )) {
    root.append(ui.h("div", { class: "card" },
      ui.h("div", { class: "row", style: { borderBottom: "0" } },
        ui.h("span", { class: "sub",
          text: "Back from time away — the first session back is re-entry, not a test. Ease in and let the log rebuild." }))));
  }

  if (settings.gymTagFirstLaunchOfDay && gym?.barcodeImage && !gymTagShownOn(todayKey)) {
    markGymTagShown(todayKey);
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
    const report = coachingReport(program, completed, exMap, checkins, intervalSnaps);
    const handled = new Set(decisions.filter((decision) => (decision.programId || decision.programID) === (program.uuid || program.id))
      .map((decision) => decision.recommendationId || decision.recommendationID));
    // No cap, matching native: the engine already prioritizes, and hiding a
    // pending recommendation on one client only made the coaches disagree.
    const visible = report.recommendations.filter((recommendation) => !handled.has(recommendation.id));
    const latest = report.rotations.at(-1);
    const coach = ui.h("button", { class: "card row wide coach-summary",
      onClick: () => showCoachDetail({ program, report, visible, latest, allExercises, completed }) },
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
    // The program switcher lives where training starts (epic #155 Stage 4):
    // resuming another block, starting a fresh one, or trying a different
    // methodology is one tap from Today instead of buried in Settings.
    const heading = ui.h("div", { class: "row", style: { alignItems: "baseline" } },
      ui.h("div", { class: "section-title", style: { flex: "1", margin: "0" },
        text: `${program.name} · Cycle ${program.cycleNumber}` }),
      ui.h("button", { class: "btn ghost sm", text: "Switch",
        "aria-label": "Switch training program", onClick: () => programSwitcher(program) }));
    root.append(heading);
    // Advisory only. The preference used to be write-only — a stepper set it
    // and nothing read it back.
    const lastBanked = completed[0]?.date ? new Date(completed[0].date) : null;
    const daysSinceLast = lastBanked
      ? Math.floor((Date.now() - lastBanked.getTime()) / 86400000) : null;
    // A declared break (rest/away/active recovery) overlapping the open time
    // excuses the gap entirely — a chosen break is not a lapse, and nagging
    // about spacing through it reads the calendar as a failure
    // (INV-INTERVAL-IS-NOT-A-GAP). Mirrors HomeView.spacingNote.
    const gapExcused = lastBanked
      && C.intervalGapExcused(lastBanked.getTime(), Date.now(), intervalSnaps);
    const shortfall = gapExcused
      ? null : C.sessionSpacingShortfall(daysSinceLast, program.preferredSessionSpacingDays ?? 0);
    const card = ui.h("div", { class: "card" },
      ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px", cursor: "pointer" },
        onClick: () => workoutPreview(program, day, { exMap, gym, barLb, completed }) },
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
    const lifts = C.orderedProgramSlots(day.lifts);
    for (const l of lifts) {
      const ex = exMap.get(l.exerciseName);
      // The shared preview pipeline: honest planningBase, volume-fallback
      // sets, and the same snapped weight the started session will store.
      const { plan, targetWeightLb } = previewProgramPlan(l, ex, program, program.currentWeek, {
        base: planningBase(l, ex, program, completed),
        addedSets: volumeFallbackSets(l, program), barLb, gym,
      });
      card.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
        ui.h("div", { class: "lead" },
          ex ? ui.h("button", { class: "title title-button", text: l.exerciseName,
            "aria-label": `${l.exerciseName} — history, program cycle, and settings`,
            onClick: () => exerciseDetail(ex) })
            : ui.h("span", { class: "title", text: l.exerciseName }),
          ui.slotBadge(l, program.currentWeek, ex?.movementGroup, program.focus)),
        ui.h("div", { style: { textAlign: "right" } },
          ui.h("div", { class: "wt-big mono", text: ui.fmtWeight(plan.weightLb) }),
          ui.h("div", { class: "sub mono", text: `${plan.sets}×${plan.reps}` }))));
      // The bar you'll load / the pair you'll grab — every wave lift, matching
      // the preview (a complementary barbell lift is loaded just the same).
      if (ex && ex.type === "barbell" && plan.weightLb > 0) {
        card.append(barbellPrescriptionView(
          plan.weightLb, targetWeightLb, C.primaryUnit(settings.unitDisplay), gym,
          ex.stationDenomination ?? null, ex.movementGroup,
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

  root.append(ui.h("div", { class: "section-title", text: "Ad-hoc work" }));
  root.append(ui.h("button", { class: "card row wide adhoc-entry", onClick: () => openActivityLog() },
    ui.h("div", { class: "lead" },
      ui.h("span", { class: "title", text: "Wood Splitting" }),
      ui.h("span", { class: "sub", text: "Duration, effort, maul and wood counts" }),
      ui.h("span", { class: "sub", text: "History only · never advances training" })),
    ui.h("span", { class: "adhoc-plus accent", text: "+", "aria-hidden": "true" })));

  host.replaceChildren(root);

  async function start(track) {
    const id = await createSessionFromTrack(track);
    openSession(id);
  }
}

function showCoachDetail({ program, report, visible, latest, allExercises, completed }) {
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
                const message = await applyCoachingRecommendation(proposed, recommendation, allExercises, completed);
                await Programs.saveWithDecision(proposed,
                  coachingDecision(proposed, recommendation, "accepted", latest?.reasons || [], program));
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
function workoutPreview(program, day, { exMap, gym, barLb, completed = [] }) {
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
      const lifts = C.orderedProgramSlots(day.lifts);
      if (!lifts.length) liftCard.append(ui.h("div", { class: "muted", text: "No program lifts this day." }));
      for (const l of lifts) {
        const ex = exMap.get(l.exerciseName);
        // The shared preview pipeline — the preview and the started session
        // must never disagree.
        const { plan, targetWeightLb } = previewProgramPlan(l, ex, program, program.currentWeek, {
          base: planningBase(l, ex, program, completed),
          addedSets: volumeFallbackSets(l, program), barLb, gym,
        });
        liftCard.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
          ui.h("div", { class: "lead" },
            ex ? ui.h("button", { class: "title title-button", text: l.exerciseName,
              "aria-label": `${l.exerciseName} — history, program cycle, and settings`,
              onClick: () => exerciseDetail(ex) })
              : ui.h("span", { class: "title", text: l.exerciseName }),
            ui.slotBadge(l, program.currentWeek, ex?.movementGroup, program.focus)),
          ui.h("div", { style: { textAlign: "right" } },
            ui.h("div", { class: "wt-big mono", text: ui.fmtWeight(plan.weightLb) }),
            ui.h("div", { class: "sub mono", text: `${plan.sets}×${plan.reps}` }))));
        if (ex && ex.type === "barbell" && plan.weightLb > 0) {
          liftCard.append(barbellPrescriptionView(
            plan.weightLb, targetWeightLb, C.primaryUnit(ui.prefs.unitDisplay), gym,
            ex.stationDenomination ?? null, ex.movementGroup,
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
        for (const a of C.orderedProgramSlots(day.accessories)) {
          const accessoryExercise = exMap.get(a.exerciseName);
          const type = accessoryExercise?.type;
          // The target clamped into the window this slot actually runs on — a
          // bodyweight identity has no load step, so its window top is
          // advisory and the card must show the reps it earned.
          const accReps = C.repWindow(a.minReps, a.maxReps, a.currentReps,
            C.hasLoadStep(a.incrementLb, accessoryExercise)).current;
          const isTimed = type === "timed" || type === "conditioning";
          accCard.append(ui.h("div", { class: "row", style: { borderBottom: "0", padding: "4px 0" } },
            accessoryExercise ? ui.h("button", { class: "title title-button", text: a.exerciseName,
              "aria-label": `${a.exerciseName} — history, program cycle, and settings`,
              onClick: () => exerciseDetail(accessoryExercise) })
              : ui.h("span", { class: "title", text: a.exerciseName }),
            ui.h("span", { class: "sub mono", text: isTimed
              ? `${a.sets} × ${C.cardioDurationLabel(a.targetSeconds || 30)}`
              : (a.weightLb > 0 ? `${a.sets}×${accReps} @ ${ui.fmtWeight(a.weightLb)}` : `${a.sets}×${accReps}`) })));
        }
        body.append(accCard);
      }
    },
  });
}

// Resume another block, start a fresh block of any methodology, or switch
// styles — all seeded from current global history, never a weight prompt
// (epic #155 Stage 4). Activation itself is owned by views/settings.js so
// every rule (exclusivity, cursor preservation, the open-session refusal)
// has exactly one implementation.
async function programSwitcher(active) {
  const [{ activateProgram, assertNoForeignOpenSession }, { PROGRAM_TEMPLATES, createProgramFromTemplate }]
    = await Promise.all([import("./settings.js"), import("../templates.js")]);
  const programs = await Programs.all();
  ui.sheet({ title: "Switch program", build: (c, api) => {
    const fail = (error) => ui.toast(error?.message || "Couldn't switch programs.");
    const resumable = programs.filter((p) => p.id !== active?.id);
    if (resumable.length) {
      c.append(ui.h("div", { class: "section-title", text: "Resume" }));
      for (const p of resumable) {
        c.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row", style: { cursor: "pointer" }, onClick: async () => {
            try {
              await activateProgram(p);
              await Programs.save(p);
              api.close();
              ui.nav.refresh();
            } catch (error) { fail(error); }
          } },
            ui.h("span", { class: "title", text: p.name }),
            // Resuming picks up exactly where this block left off.
            ui.h("span", { class: "sub", text: `Cycle ${p.cycleNumber} · rotation ${p.currentWeek}` }))));
      }
    }
    c.append(ui.h("div", { class: "section-title", text: "Start a new block" }));
    for (const template of PROGRAM_TEMPLATES) {
      c.append(ui.h("div", { class: "card" },
        ui.h("div", { class: "row", style: { cursor: "pointer" }, onClick: async () => {
          try {
            await assertNoForeignOpenSession(null);
            const id = await createProgramFromTemplate(template);
            const created = await Programs.get(id);
            await activateProgram(created);
            await Programs.save(created);
            api.close();
            ui.nav.refresh();
          } catch (error) { fail(error); }
        } },
          ui.h("span", { class: "title", text: template.name }),
          ui.h("span", { class: "sub", text: template.tagline || "" }))));
    }
    c.append(ui.h("div", { class: "muted", style: { marginTop: "8px" },
      text: "Your history, PRs and charts stay whole either way — a new block "
        + "starts from the weights you have already earned." }));
    c.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "8px" },
      text: "Close", onClick: () => api.close() }));
  } });
}
