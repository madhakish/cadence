// Settings — units, rest, protein target, gyms, progression, exercise library,
// and data export/import (the safety net against Safari storage eviction).
import * as ui from "../ui.js";
import * as C from "../core.js";
import { CATEGORIES, EX_TYPES, BODY_SITES } from "../constants.js";
import { Settings, Gyms, Tracks, Exercises, Programs, Checkpoints, exportJSON, exportCSV, importBundle, wipeAll, ensureSeeded, syncLibrary } from "../db.js";
import { PROGRAM_TEMPLATES, createProgramFromTemplate } from "../templates.js";
import { muscleProfile, muscleBlurb, figureSVG } from "../anatomy.js";
import { Sessions } from "../db.js";

// Move a program to a rotation. Placing at/after Peak (rotation 3) with no banked
// Peak result would otherwise make the next rollover treat the skipped Peak as a
// stall and deload; seed a neutral hold (carry current state forward, no note) for
// any lift lacking pending so manual positioning never penalizes. A real Peak
// session logged in rotation 3 overwrites this hold with its grade. Mirrors the
// native ProgramEditorView.positionAtRotation.
function positionAtRotation(program, rotation) {
  program.currentWeek = rotation;
  if (rotation < 3) return;
  for (const day of program.days || []) {
    for (const lift of day.lifts || []) {
      if (lift.pending) continue;
      lift.pending = {
        state: {
          baseWeightLb: lift.baseWeightLb,
          estimatedMaxLb: lift.estimatedMaxLb,
          stallCount: lift.stallCount || 0,
          lastIncrementLb: lift.lastIncrementLb || 0,
        },
        grade: "hold",
        note: null,
      };
    }
  }
}

export async function render(host) {
  const [settings, gyms, tracks, exercises, programs, checkpoints] = await Promise.all([Settings.get(), Gyms.all(), Tracks.all(), Exercises.all(), Programs.all(), Checkpoints.all()]);
  const root = ui.h("div");
  const saveS = async () => { await Settings.save(settings); ui.prefs.unitDisplay = settings.unitDisplay; };

  // Theme
  root.append(ui.h("div", { class: "section-title", text: "Theme" }));
  root.append(ui.h("div", { class: "card" },
    ui.seg(ui.THEMES, settings.theme || "carbon", async (v) => { settings.theme = v; ui.applyTheme(v); await saveS(); })));

  // Units
  root.append(ui.h("div", { class: "section-title", text: "Units" }));
  root.append(ui.h("div", { class: "card" },
    ui.seg([{ value: "lbPrimary", label: "lb" }, { value: "kgPrimary", label: "kg" }, { value: "both", label: "Both" }],
      settings.unitDisplay, async (v) => { settings.unitDisplay = v; await saveS(); ui.nav.refresh(); })));

  // Rest timer — the smart defaults an exercise falls to when it has no rest
  // of its own, listed in the order they're checked: today's program role
  // first, then movement type. Settings.get() normalized `rest`, so every
  // bucket key is present (no view-side re-merge). Mirrors SettingsView.
  root.append(ui.h("div", { class: "section-title", text: "Rest timer" }));
  const rest = settings.rest;
  const restCard = ui.h("div", { class: "card" });
  const restRow = (label, key) => restCard.append(ui.h("div", { class: "row" }, ui.h("span", { text: label }),
    ui.stepper(rest[key], { min: 0, max: 600, step: 15, format: ui.mmss, onChange: async (v) => { rest[key] = v; await saveS(); } })));
  restCard.append(ui.h("div", { class: "sub", style: { padding: "6px 0 2px" }, text: "In a program day, by role" }));
  restRow("Complementary lifts", "secondarySeconds");
  restRow("Accessories", "accessorySeconds");
  restCard.append(ui.h("div", { class: "sub", style: { padding: "10px 0 2px" }, text: "Everything else, by movement" }));
  restRow("Squat & deadlift mains", "mainCompoundSeconds");
  restRow("Olympic lifts", "olympicSeconds");
  restRow("Other main lifts (presses…)", "mainUpperSeconds");
  restCard.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Auto-start rest after a set" }),
    ui.toggle(settings.autoStartRest, async (v) => { settings.autoStartRest = v; await saveS(); })));
  restCard.append(ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Haptics" }),
    ui.toggle(settings.haptics !== false, async (v) => { settings.haptics = v; await saveS(); })));
  root.append(restCard);
  root.append(ui.h("div", { class: "sub", style: { margin: "4px" }, text: "These are the fallback timers. An exercise with a rest of its own (set with ⏱ in the logger, or in the library) always uses that instead. 0:00 = no timer. Auto-start off = tap Rest yourself." }));

  root.append(ui.h("div", { class: "section-title", text: "Arrival" }));
  root.append(ui.h("div", { class: "card" },
    ui.h("div", { class: "row", style: { borderBottom: "0" } },
      ui.h("div", { class: "lead" },
        ui.h("span", { text: "Show gym tag on first launch of the day" }),
        ui.h("span", { class: "sub", text: "Presents the default membership tag once, then leaves Today ready for training." })),
      ui.toggle(settings.gymTagFirstLaunchOfDay === true, async (v) => { settings.gymTagFirstLaunchOfDay = v; await saveS(); }))));

  // Protein
  root.append(ui.h("div", { class: "section-title", text: "Protein" }));
  root.append(ui.h("div", { class: "card" }, ui.h("div", { class: "row" }, ui.h("span", { text: "Daily target" }),
    ui.stepper(settings.proteinTargetGrams, { min: 80, max: 300, step: 5, format: (v) => `${v} g`, onChange: async (v) => { settings.proteinTargetGrams = v; await saveS(); } }))));

  // Gyms
  root.append(ui.h("div", { class: "section-title", text: "Gyms" }));
  const gymList = ui.h("div", { class: "card list" });
  for (const g of gyms) {
    gymList.append(ui.h("div", { class: "row", onClick: () => gymEditor(g) },
      ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: g.name }),
        ui.h("span", { class: "sub", text: (g.isDefault ? "default · " : "") + (g.barcodeImage ? "tag stored" : "no tag") })),
      ui.h("span", { class: "chev" })));
  }
  root.append(gymList);
  root.append(ui.h("button", { class: "btn ghost wide", text: "+ Add gym", onClick: async () => {
    const g = { name: `Gym ${gyms.length + 1}`, isDefault: gyms.length === 0, defaultBarId: C.barId(C.BARS.bar45lb), collarWeightLb: 0, loadingPolicy: "closest", plateToggles: C.ALL_STANDARD.map((p) => ({ value: p.value, unit: p.unit, enabled: true })), barcodeImage: null, barcodeLabel: "Membership tag" };
    await Gyms.save(g); ui.nav.refresh();
  } }));

  // Progression
  // Program
  root.append(ui.h("div", { class: "section-title", text: "Program" }));
  const progList = ui.h("div", { class: "card list" });
  if (!programs.length) progList.append(ui.h("div", { class: "muted", text: "No program." }));
  for (const p of programs) {
    progList.append(ui.h("div", { class: "row", onClick: () => programEditor(p) },
      ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: p.name }),
        ui.h("span", { class: "sub", style: { display: "flex", alignItems: "center", gap: "6px" } },
          ui.wave(p.currentWeek),
          ui.h("span", { text: `${p.focus} · ${p.days.length} days · Cycle ${p.cycleNumber}${p.isActive ? " · active" : ""}` }))),
      ui.h("span", { class: "chev" })));
  }
  root.append(progList);
  root.append(ui.h("button", { class: "btn ghost wide", text: "+ Add program", onClick: () => {
    // Start from a style (templates.js) or from scratch. The first program
    // created becomes active either way.
    ui.actionSheet("Start from", [
      ...PROGRAM_TEMPLATES.map((t) => ({ label: `${t.name} — ${t.tagline}`, onClick: async () => {
        await createProgramFromTemplate(t);
        ui.nav.refresh();
      } })),
      { label: "Blank program", onClick: async () => {
        await Programs.save({ name: `Program ${programs.length + 1}`, focus: "strength", cycleNumber: 1, currentWeek: 1, nextDayIndex: 0, roundingLb: 5, isActive: programs.length === 0, days: [] });
        ui.nav.refresh();
      } },
    ]);
  } }));

  root.append(ui.h("div", { class: "section-title", text: "Progression (standalone lifts)" }));
  const trackList = ui.h("div", { class: "card list" });
  if (!tracks.length) trackList.append(ui.h("div", { class: "muted", text: "No tracked lifts." }));
  for (const t of tracks) {
    const sug = t.mode === "cycle" ? C.planFor(t) : C.linearPlan(t.baseWeightLb);
    trackList.append(ui.h("div", { class: "row", onClick: () => trackEditor(t) },
      ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: t.exerciseName }),
        ui.h("span", { class: "sub", text: `+${ui.fmtWeight(t.incrementLb)} per ${t.mode === "cycle" ? "cycle" : "session"} · next: ${ui.fmtWeight(sug.weightLb)} · ${sug.sets}×${sug.reps}` })),
      ui.h("span", { class: "chev" })));
  }
  root.append(trackList);

  // Library
  root.append(ui.h("div", { class: "section-title", text: "Library" }));
  root.append(ui.h("div", { class: "card list" },
    ui.h("div", { class: "row", onClick: () => exerciseLibrary(exercises), style: { borderBottom: "0" } },
      ui.h("span", { class: "title", text: "Exercise library" }), ui.h("span", { class: "chev" }))));

  // Data
  const downloadExport = async (kind) => {
    try {
      if (kind === "json") ui.download("cadence-export.json", await exportJSON());
      else ui.download("cadence-sets.csv", await exportCSV(), "text/csv");
    } catch (error) {
      console.error("Cadence export failed", error);
      ui.toast(`Export failed: ${error?.message || error}`);
    }
  };
  root.append(ui.h("div", { class: "section-title", text: "Data" }));
  root.append(ui.h("div", { class: "card" },
    ui.h("div", { class: "btn-row" },
      ui.h("button", { class: "btn", text: "Export JSON", onClick: () => downloadExport("json") }),
      ui.h("button", { class: "btn", text: "Export CSV", onClick: () => downloadExport("csv") }),
      ui.h("button", { class: "btn ghost", text: "Import JSON", onClick: () => importData() })),
    ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: "Export regularly — iOS Safari can clear local data. Import restores from a JSON backup." })));
  const latestCheckpoint = checkpoints[0];
  const checkpointAction = async (action) => {
    try {
      if (action === "create") {
        await Checkpoints.create("manual");
        ui.toast("Recovery checkpoint created.");
      } else {
        await Checkpoints.restoreLatest();
        await syncLibrary();
        ui.toast("Recovery checkpoint restored.");
      }
      ui.nav.refresh();
    } catch (error) {
      console.error("Cadence checkpoint operation failed", error);
      ui.toast(`Recovery failed: ${error?.message || error}`);
    }
  };
  root.append(ui.h("div", { class: "card", style: { marginTop: "10px" } },
    ui.h("div", { class: "btn-row" },
      ui.h("button", { class: "btn ghost", text: "Checkpoint now", onClick: () => checkpointAction("create") }),
      latestCheckpoint ? ui.h("button", { class: "btn ghost", text: "Restore latest", onClick: () => ui.actionSheet("Restore local checkpoint?", [
        { label: "Restore it", role: "danger", onClick: () => checkpointAction("restore") },
      ]) }) : null),
    ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: latestCheckpoint
      ? `Keeping ${checkpoints.length} of 3 local recovery points. Latest: ${new Date(latestCheckpoint.createdAt).toLocaleString()}.`
      : "Cadence keeps the last 3 local recovery points when the app backgrounds and before imports/resets." }),
    ui.h("div", { class: "sub", style: { marginTop: "4px" }, text: "Local checkpoints can undo a bad import, but Safari eviction removes them too. Downloaded JSON is the real backup." })));
  root.append(ui.h("button", { class: "btn ghost wide danger", style: { marginTop: "10px" }, text: "Reset all data", onClick: () => resetData() }));

  host.replaceChildren(root);
}

function gymEditor(g) {
  ui.pushScreen({
    title: g.name,
    build: (body, api) => {
      const draw = () => {
        ui.clear(body);
        const name = ui.h("input", { type: "text", value: g.name });
        name.addEventListener("change", async () => { const old = g.name; g.name = name.value || old; if (g.name !== old) { await Gyms.del(old); } await Gyms.save(g); api.setTitle(g.name); });
        body.append(ui.field("Name", name));
        body.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Default gym" }), ui.toggle(g.isDefault, async (v) => { g.isDefault = v; await Gyms.save(g); })));
        const barSel = ui.h("select", {}, ...C.ALL_BARS.map((b) => ui.h("option", { value: C.barId(b), text: C.barLabel(b), selected: C.barId(b) === g.defaultBarId })));
        barSel.addEventListener("change", async () => { g.defaultBarId = barSel.value; await Gyms.save(g); });
        body.append(ui.field("Default bar", barSel));
        body.append(ui.field("Collars (combined lb)", ui.stepper(g.collarWeightLb || 0, {
          min: 0, max: 20, step: 0.5, format: (v) => `${C.trim(v)} lb`,
          onChange: async (v) => { g.collarWeightLb = v; await Gyms.save(g); },
        })));
        const policySel = ui.h("select", {}, ...C.LOADING_POLICIES.map((policy) => ui.h("option", {
          value: policy, text: C.loadingPolicyLabel(policy), selected: policy === (g.loadingPolicy || "closest"),
        })));
        policySel.addEventListener("change", async () => { g.loadingPolicy = policySel.value; await Gyms.save(g); });
        body.append(ui.field("Loading policy", policySel));
        body.append(ui.h("div", { class: "sub", text: "Collars count toward achieved weight. The policy is applied whenever Cadence snaps a barbell target to this gym's plate inventory." }));

        body.append(ui.h("div", { class: "section-title", text: "Plate inventory" }));
        const inv = ui.h("div", { class: "card" });
        for (const t of g.plateToggles) {
          inv.append(ui.h("div", { class: "row" }, ui.h("span", { class: t.unit === "kg" ? "accent" : "", text: `${C.trim(t.value, 2)} ${t.unit}` }),
            ui.toggle(t.enabled, async (v) => { t.enabled = v; await Gyms.save(g); })));
        }
        body.append(inv);

        body.append(ui.h("div", { class: "section-title", text: "Membership tag" }));
        const tagCard = ui.h("div", { class: "card" });
        if (g.barcodeImage) tagCard.append(ui.h("img", { class: "gym-img", src: g.barcodeImage, alt: "barcode" }));
        const file = ui.h("input", { type: "file", accept: "image/*" });
        file.addEventListener("change", () => {
          const f = file.files[0]; if (!f) return;
          const r = new FileReader();
          r.onload = async () => { g.barcodeImage = r.result; await Gyms.save(g); draw(); };
          r.readAsDataURL(f);
        });
        tagCard.append(ui.field(g.barcodeImage ? "Replace photo" : "Add barcode photo", file));
        const label = ui.h("input", { type: "text", value: g.barcodeLabel || "" });
        label.addEventListener("change", async () => { g.barcodeLabel = label.value; await Gyms.save(g); });
        tagCard.append(ui.field("Tag label", label));
        if (g.barcodeImage) tagCard.append(ui.h("button", { class: "btn ghost danger wide", text: "Remove photo", onClick: async () => { g.barcodeImage = null; await Gyms.save(g); draw(); } }));
        body.append(tagCard);

        body.append(ui.h("button", { class: "btn ghost wide danger", style: { marginTop: "12px" }, text: "Delete gym", onClick: async () => { await Gyms.del(g.name); api.close(); ui.nav.refresh(); } }));
      };
      draw();
    },
  });
}

function pickExerciseSheet(onPick) {
  Exercises.all().then((all) => {
    ui.sheet({ title: "Pick exercise", build: (c, api) => {
      const search = ui.h("input", { type: "search", placeholder: "Exercise, movement, or equipment" });
      const results = ui.h("div");
      const paint = () => {
        ui.clear(results);
        const term = search.value.trim().toLowerCase();
        const available = all.filter((exercise) => exercise.gateStatus !== "shelved" && !exercise.isShelved);
        const visible = term ? available.filter((exercise) => [exercise.name, exercise.movementGroup, exercise.type,
          C.movementPatternName(exercise.movementPattern), ...(exercise.aliases || []), ...(exercise.strategyTags || [])]
          .some((value) => String(value || "").toLowerCase().includes(term))) : available;
        for (const cat of CATEGORIES) {
          const inCat = visible.filter((e) => e.category === cat).sort((a, b) => a.name.localeCompare(b.name));
          if (!inCat.length) continue;
          results.append(ui.h("div", { class: "section-title", text: cat }));
          for (const e of inCat) results.append(ui.h("button", { class: "btn wide ghost", style: { marginTop: "6px" }, text: e.name, onClick: () => { api.close(); onPick(e); } }));
        }
      };
      search.addEventListener("input", paint);
      c.append(search, results);
      paint();
    } });
  });
}

function removeDay(p, day) {
  p.days = p.days.filter((d) => d !== day);
  p.days.sort((a, b) => a.order - b.order).forEach((d, i) => { d.order = i; });
  if (p.nextDayIndex >= p.days.length) p.nextDayIndex = 0;
}

function orderedSlots(slots = []) {
  return [...slots].sort((a, b) => (a.order ?? 0) - (b.order ?? 0)
    || String(a.exerciseName || a.name || "").localeCompare(String(b.exerciseName || b.name || "")));
}

function moveSlot(slots, slot, delta) {
  const ordered = orderedSlots(slots);
  const from = ordered.indexOf(slot);
  const to = from + delta;
  if (from < 0 || to < 0 || to >= ordered.length) return false;
  [ordered[from], ordered[to]] = [ordered[to], ordered[from]];
  ordered.forEach((item, index) => { item.order = index; });
  return true;
}

async function activateProgram(p) {
  const all = await Programs.all();
  for (const x of all) { const want = x.id === p.id; if (x.isActive !== want) { x.isActive = want; await Programs.save(x); } }
  p.isActive = true;
}

async function programEditor(p) {
  const exerciseByName = new Map((await Exercises.all()).map((exercise) => [exercise.name, exercise]));
  const warningsFor = () => {
    const warnings = [];
    const rotation = new Map(), patterns = new Map();
    let intervalSlots = 0;
    const addSets = (group, pattern, sets) => {
      if (group) rotation.set(group, (rotation.get(group) || 0) + sets);
      if (pattern) patterns.set(pattern, (patterns.get(pattern) || 0) + sets);
    };
    for (const day of p.days || []) {
      if (!(day.lifts || []).some((lift) => lift.role === "main")) warnings.push(`${day.name} has no main lift.`);
      for (const lift of day.lifts || []) {
        if (!(lift.baseWeightLb > 0)) warnings.push(`${lift.exerciseName} needs a rotation-1 base weight.`);
        if (lift.estimatedMaxLb > 0 && lift.baseWeightLb > lift.estimatedMaxLb) warnings.push(`${lift.exerciseName}'s base is above its estimated 1RM.`);
        else {
          const ceiling = C.focusParams(p.focus).tm;
          if (lift.estimatedMaxLb > 0 && ceiling > 0 && lift.baseWeightLb > lift.estimatedMaxLb * ceiling) warnings.push(`${lift.exerciseName}'s base is above the ${Math.round(ceiling * 100)}% training-max ceiling; verify its estimated 1RM or lower the base.`);
        }
        const exercise = exerciseByName.get(lift.exerciseName);
        if (exercise) {
          const plan = C.programPlanFor(
          { cycleNumber: 1, baseWeightLb: lift.baseWeightLb, nextPhase: 1, incrementLb: 0 },
          p.roundingLb, exercise.type, exercise.movementGroup, lift.role, p.focus, lift.prescription || "automatic",
          { ...lift, workingSets: lift.doubleProgressionSets ?? 3 });
          // Published methodology slots deliberately shape their own weekly
          // balance (squat 3×/week, one heavy pull); the press/pull and
          // squat/hinge heuristics would permanently flag the canon, so those
          // sums skip methodology slots — but NOT generic double-progression
          // rows, and pattern coverage (vertical pulling) counts every slot.
          const style = lift.prescription || "automatic";
          const methodologySlot = C.buildsOwnSessionShape(style) && style !== "doubleProgression";
          const pattern = exercise.movementPattern || C.movementPattern(exercise.name, exercise.movementGroup);
          if (!methodologySlot) addSets(exercise.movementGroup, pattern, plan.sets);
          else addSets(null, pattern, plan.sets);
          if ((exercise.movementPattern || C.movementPattern(exercise.name, exercise.movementGroup)) === "olympicPower" && plan.reps > 3) warnings.push(`${lift.exerciseName} is power work; keep programmed sets at 1–3 reps.`);
        }
      }
      for (const accessory of day.accessories || []) {
        const exercise = exerciseByName.get(accessory.exerciseName);
        const durationBased = exercise?.type === "timed" || exercise?.type === "conditioning";
        if (!durationBased && accessory.minReps > accessory.maxReps) warnings.push(`${accessory.exerciseName}'s minimum reps exceed its maximum.`);
        else if (!durationBased && (accessory.currentReps < accessory.minReps || accessory.currentReps > accessory.maxReps)) warnings.push(`${accessory.exerciseName}'s current reps are outside its rep range.`);
        const pattern = exercise?.movementPattern || C.movementPattern(accessory.exerciseName, exercise?.movementGroup);
        addSets(exercise?.movementGroup, pattern, accessory.sets);
        if (pattern === "olympicPower" && accessory.currentReps > 3) warnings.push(`${accessory.exerciseName} is power work; keep programmed sets at 1–3 reps.`);
        if (exercise?.type === "conditioning" && accessory.conditioningEffort === "interval") intervalSlots += 1;
      }
      const hasPower = (day.lifts || []).some((lift) => exerciseByName.get(lift.exerciseName)?.movementPattern === "olympicPower");
      const hasIntervals = (day.accessories || []).some((accessory) => exerciseByName.get(accessory.exerciseName)?.type === "conditioning" && accessory.conditioningEffort === "interval");
      if (hasPower && hasIntervals) warnings.push(`Move intervals off ${day.name}; power work and intervals should not share a session.`);
    }
    if (intervalSlots > 1) warnings.push(`The rotation has ${intervalSlots} interval blocks; keep one interval dose and make the rest easy conditioning.`);
    const press = rotation.get("press") || 0, pull = rotation.get("pull") || 0;
    if (press >= 8 && pull * 5 < press * 4) warnings.push(`Per-rotation pulling volume (${pull} sets) trails pressing (${press}); consider more rows or pull-ups.`);
    if ((patterns.get("verticalPull") || 0) < 3) warnings.push(`Vertical pulling is ${patterns.get("verticalPull") || 0}/3 sets per rotation.`);
    const squat = rotation.get("squat") || 0, hinge = rotation.get("hinge") || 0;
    if (Math.max(squat, hinge) >= 8 && Math.min(squat, hinge) * 2 < Math.max(squat, hinge)) warnings.push(`Per-rotation squat/hinge volume is uneven (${squat}/${hinge} sets).`);
    const orderedDays = [...(p.days || [])].sort((a, b) => a.order - b.order);
    orderedDays.forEach((day, index) => {
      if (!orderedDays.length) return;
      const next = orderedDays[(index + 1) % orderedDays.length];
      const nextIsHingeLed = (next.lifts || []).some((lift) => lift.role === "main"
        && (exerciseByName.get(lift.exerciseName)?.movementPattern
          || C.movementPattern(lift.exerciseName, exerciseByName.get(lift.exerciseName)?.movementGroup)) === "hipHinge");
      const hasFatiguingHamstrings = (day.accessories || []).some((accessory) => {
        const exercise = exerciseByName.get(accessory.exerciseName);
        const pattern = exercise?.movementPattern
          || C.movementPattern(accessory.exerciseName, exercise?.movementGroup);
        return pattern === "kneeFlexion" || pattern === "hipExtension";
      });
      if (nextIsHingeLed && hasFatiguingHamstrings) {
        warnings.push(`Move hamstring isolation/back extensions off ${day.name}; it immediately precedes hinge-led ${next.name}.`);
      }
    });
    return warnings;
  };
  ui.pushScreen({
    title: p.name,
    build: (body, api) => {
      const draw = () => {
        ui.clear(body);
        const warnings = warningsFor();
        if (warnings.length) body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "title warn", text: "Coach check" }),
          ...warnings.map((warning) => ui.h("div", { class: "sub warn", style: { marginTop: "6px" }, text: `⚠ ${warning}` }))));
        const nameInput = ui.h("input", { type: "text", value: p.name });
        nameInput.addEventListener("change", async () => { p.name = nameInput.value || p.name; api.setTitle(p.name); await Programs.save(p); });
        body.append(ui.field("Program name", nameInput));
        body.append(ui.field("Training focus", ui.seg(
          [{ value: "strength", label: "Strength" }, { value: "hypertrophy", label: "Hypertrophy" }, { value: "maintain", label: "Maintain" }],
          p.focus, async (v) => { p.focus = v; await Programs.save(p); })));
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row" }, ui.h("span", { text: "Rounding" }),
            ui.stepper(p.roundingLb, { min: 2.5, max: 10, step: 2.5, format: ui.fmtWeight, onChange: async (v) => { p.roundingLb = v; await Programs.save(p); } })),
          ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Active (drives Today)" }),
            ui.toggle(p.isActive, async (v) => { if (v) await activateProgram(p); else p.isActive = false; await Programs.save(p); }))));
        body.append(ui.h("div", { class: "section-title", text: "Deterministic coach" }));
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row" }, ui.h("span", { text: "Coaching proposals" }),
            ui.toggle(p.coachEnabled !== false, async (v) => { p.coachEnabled = v; await Programs.save(p); })),
          ui.h("div", { class: "row" }, ui.h("span", { text: "Preferred spacing" }),
            ui.stepper(p.preferredSessionSpacingDays ?? 3, { min: 2, max: 7, step: 1, format: (v) => `${v} days`, onChange: async (v) => { p.preferredSessionSpacingDays = v; await Programs.save(p); } })),
          ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Max work added / rotation" }),
            ui.stepper(p.maximumAddedSetsPerRotation ?? 6, { min: 0, max: 10, step: 1, format: (v) => `${v} sets`, onChange: async (v) => { p.maximumAddedSetsPerRotation = v; await Programs.save(p); } })),
          ui.h("div", { class: "sub", style: { margin: "8px" }, text: "Uses completed output by full program rotation. Nothing changes until you apply a proposal." })));
        body.append(ui.h("div", { class: "section-title", text: "Where you are" }));
        const PHASE = ["", "Volume", "Load", "Peak", "Deload"];
        const sortedDays = [...p.days].sort((a, b) => a.order - b.order);
        const pos = ui.h("div", { class: "card" });
        pos.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Cycle" }),
          ui.stepper(p.cycleNumber, { min: 1, max: 99, step: 1, onChange: async (v) => { p.cycleNumber = v; await Programs.save(p); } })));
        pos.append(ui.h("div", { class: "row", style: { borderBottom: sortedDays.length ? undefined : "0" } }, ui.h("span", { text: "Rotation" }),
          ui.stepper(p.currentWeek, { min: 1, max: 4, step: 1, format: (v) => `${v} of 4 · ${PHASE[v]}`, onChange: async (v) => { positionAtRotation(p, v); await Programs.save(p); } })));
        if (sortedDays.length) {
          const daySel = ui.h("select", {}, ...sortedDays.map((d) => ui.h("option", { value: String(d.order), text: d.name, selected: d.order === p.nextDayIndex })));
          daySel.addEventListener("change", async () => { p.nextDayIndex = Number(daySel.value); await Programs.save(p); });
          pos.append(ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Next day" }), daySel));
        }
        body.append(pos);
        body.append(ui.h("div", { class: "sub", style: { margin: "4px" }, text: "Set your position mid-cycle. Rotations 1–3 are working (volume/load/peak), rotation 4 is the rest rotation, then the cycle bumps. Lifts progress automatically — weights are the rotation-1 base." }));
        body.append(ui.h("div", { class: "section-title", text: "Days" }));
        const list = ui.h("div", { class: "card list" });
        const days = [...p.days].sort((a, b) => a.order - b.order);
        if (!days.length) list.append(ui.h("div", { class: "muted", text: "No days. Add one below." }));
        for (const day of days) {
          list.append(ui.h("div", { class: "row" },
            ui.h("div", { class: "lead", style: { cursor: "pointer", flex: "1" }, onClick: () => programDayEditor(p, day) },
              ui.h("span", { class: "title", text: day.name }),
              ui.h("span", { class: "sub", text: orderedSlots(day.lifts).map((l) => l.exerciseName).join(" + ") || "empty" })),
            ui.h("button", { class: "btn sm ghost", text: "↑", ariaLabel: `Move ${day.name} earlier`, onClick: async () => { if (moveSlot(p.days, day, -1)) { p.nextDayIndex = Math.min(p.nextDayIndex, p.days.length - 1); await Programs.save(p); draw(); } } }),
            ui.h("button", { class: "btn sm ghost", text: "↓", ariaLabel: `Move ${day.name} later`, onClick: async () => { if (moveSlot(p.days, day, 1)) { p.nextDayIndex = Math.min(p.nextDayIndex, p.days.length - 1); await Programs.save(p); draw(); } } }),
            ui.h("button", { class: "btn sm ghost danger", text: "Delete", onClick: async () => { removeDay(p, day); await Programs.save(p); draw(); } })));
        }
        body.append(list);
        body.append(ui.h("button", { class: "btn ghost wide", text: "+ Add day", onClick: async () => {
          p.days.push({ name: `Day ${p.days.length + 1}`, order: p.days.length, lifts: [], accessories: [] });
          await Programs.save(p); draw();
        } }));
        body.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "8px" }, text: "Duplicate program", onClick: async () => {
          const all = await Programs.all();
          const base = `${p.name} Copy`;
          let name = base, suffix = 2;
          while (all.some((program) => program.name === name)) name = `${base} ${suffix++}`;
          const copy = structuredClone(p);
          delete copy.id; delete copy.uuid;
          copy.name = name; copy.isActive = false;
          for (const day of copy.days || []) for (const slot of [...(day.lifts || []), ...(day.accessories || [])]) delete slot.id;
          await Programs.save(copy); ui.toast(`Created ${name}.`); ui.nav.refresh();
        } }));
        body.append(ui.h("button", { class: "btn ghost wide danger", style: { marginTop: "12px" }, text: "Delete program", onClick: () => {
          ui.actionSheet("Delete this program?", [{ label: "Delete", role: "danger", onClick: async () => { await Programs.del(p.id); api.close(); ui.nav.refresh(); } }]);
        } }));
      };
      draw();
    },
  });
}

async function programDayEditor(p, day) {
  const exerciseByName = new Map((await Exercises.all()).map((exercise) => [exercise.name, exercise]));
  ui.pushScreen({
    title: day.name,
    build: (body, api) => {
      const draw = () => {
        ui.clear(body);
        const nameInput = ui.h("input", { type: "text", value: day.name });
        nameInput.addEventListener("change", async () => { day.name = nameInput.value || day.name; api.setTitle(day.name); await Programs.save(p); });
        body.append(ui.field("Day name", nameInput));

        body.append(ui.h("div", { class: "section-title", text: "Lifts" }));
        const openDetail = async (name) => { const ex = await Exercises.byName(name); if (ex) exerciseDetail(ex); };
        for (const l of orderedSlots(day.lifts)) {
          body.append(ui.h("div", { class: "card" },
            ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
              ui.h("span", { class: "title", text: l.exerciseName, style: { cursor: "pointer" }, onClick: () => openDetail(l.exerciseName) }),
              ui.h("button", { class: "btn sm ghost", text: "↑", ariaLabel: `Move ${l.exerciseName} earlier`, onClick: async () => { if (moveSlot(day.lifts, l, -1)) { await Programs.save(p); draw(); } } }),
              ui.h("button", { class: "btn sm ghost", text: "↓", ariaLabel: `Move ${l.exerciseName} later`, onClick: async () => { if (moveSlot(day.lifts, l, 1)) { await Programs.save(p); draw(); } } }),
              ui.h("button", { class: "btn sm ghost danger", text: "Remove", onClick: async () => { day.lifts = day.lifts.filter((x) => x !== l); await Programs.save(p); draw(); } })),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Role" }),
              ui.seg([{ value: "main", label: "Main" }, { value: "complementary", label: "Comp." }], l.role, async (v) => { l.role = v; await Programs.save(p); })),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Prescription" }), (() => {
              const select = ui.h("select", {}, ...[
                ["automatic", "Automatic"], ["wave", "Strength wave"], ["offsetWave", "Strength wave — offsets"],
                ["secondary", "Secondary strength"], ["hypertrophy", "Hypertrophy"], ["technique", "Technique"],
                ["doubleProgression", "Double progression"],
                ["linearFives", "Linear fives"], ["texasVolume", "Texas — volume day"],
                ["texasLight", "Texas — light day"], ["texasIntensity", "Texas — intensity day"],
                ["fiveThreeOne", "5/3/1 wave"], ["maxEffort", "Max effort"], ["dynamicEffort", "Dynamic effort"],
              ].map(([value, label]) => ui.h("option", { value, text: label, selected: (l.prescription || "automatic") === value })));
              select.addEventListener("change", async () => { l.prescription = select.value; await Programs.save(p); draw(); });
              return select;
            })()),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Warm-up" }), (() => {
              const select = ui.h("select", {}, ...[
                ["automatic", "Automatic"], ["full", "Full ramp"], ["short", "Short ramp"], ["none", "No warm-up"],
              ].map(([value, label]) => ui.h("option", { value, text: label, selected: (l.warmupPolicy || "automatic") === value })));
              select.addEventListener("change", async () => { l.warmupPolicy = select.value; await Programs.save(p); });
              return select;
            })()),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Rotation-1 base" }),
              ui.stepper(l.baseWeightLb, { min: 0, max: 1000, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: ui.fmtWeight, onChange: async (v) => { l.baseWeightLb = v; await Programs.save(p); } })),
            l.prescription === "offsetWave" ? ui.h("div", { class: "row" }, ui.h("span", { text: "Load / peak offsets" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(l.loadOffsetLb ?? 0, { min: 0, max: 100, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { l.loadOffsetLb = v; await Programs.save(p); } }),
                ui.stepper(l.peakOffsetLb ?? 0, { min: 0, max: 150, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { l.peakOffsetLb = v; await Programs.save(p); } }))) : null,
            ["linearFives", "texasVolume", "texasLight", "texasIntensity"].includes(l.prescription)
              ? ui.h("div", { class: "row" }, ui.h("span", { text: "Working sets" }),
                ui.stepper(l.doubleProgressionSets ?? 3, { min: 1, max: 10, onChange: async (v) => { l.doubleProgressionSets = v; await Programs.save(p); } })) : null,
            l.prescription === "doubleProgression" ? ui.h("div", { class: "row" }, ui.h("span", { text: "Sets / rep window" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(l.doubleProgressionSets ?? 3, { min: 1, max: 8, onChange: async (v) => { l.doubleProgressionSets = v; await Programs.save(p); } }),
                ui.stepper(l.minimumReps ?? 5, { min: 1, max: 20, onChange: async (v) => { l.minimumReps = v; await Programs.save(p); } }),
                ui.stepper(l.maximumReps ?? 8, { min: 1, max: 30, onChange: async (v) => { l.maximumReps = v; await Programs.save(p); } }))) : null,
            ui.h("div", { class: "row" }, ui.h("span", { text: "Peak top single" }),
              ui.toggle(!!l.peakSingleEnabled, async (v) => { l.peakSingleEnabled = v; await Programs.save(p); draw(); })),
            l.peakSingleEnabled ? ui.h("div", { class: "row" }, ui.h("span", { text: "Last clean / step" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(l.lastPeakSingleLb ?? 0, { min: 0, max: 1200, step: 5, format: ui.fmtWeight, onChange: async (v) => { l.lastPeakSingleLb = v; await Programs.save(p); } }),
                ui.stepper(l.peakSingleIncrementLb ?? 5, { min: 2.5, max: 25, step: 2.5, format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { l.peakSingleIncrementLb = v; await Programs.save(p); } }))) : null,
            ui.h("div", { class: "row" }, ui.h("span", { text: "Phase primer single" }),
              ui.toggle(l.phasePrimerEnabled !== false, async (v) => { l.phasePrimerEnabled = v; await Programs.save(p); })),
            ui.h("div", { class: "row" }, ui.h("span", { text: "One-tap drop (0 = auto)" }),
              ui.stepper(l.dropIncrementLb ?? 0, { min: 0, max: 50, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: ui.fmtWeight, onChange: async (v) => { l.dropIncrementLb = v; await Programs.save(p); } })),
            ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Est. 1RM" }),
              ui.stepper(l.estimatedMaxLb, { min: 0, max: 1200, step: 5, format: ui.fmtWeight, onChange: async (v) => { l.estimatedMaxLb = v; await Programs.save(p); } }))));
        }
        body.append(ui.h("button", { class: "btn ghost wide", text: "+ Add lift", onClick: () => pickExerciseSheet(async (e) => {
          day.lifts.push({ exerciseName: e.name, role: "complementary", order: day.lifts.length, prescription: "automatic", warmupPolicy: "automatic", baseWeightLb: 45, estimatedMaxLb: 52, stallCount: 0, lastIncrementLb: 0 });
          await Programs.save(p); draw();
        }) }));

        body.append(ui.h("div", { class: "section-title", text: "Accessories" }));
        for (const a of orderedSlots(day.accessories)) {
          const exerciseType = exerciseByName.get(a.exerciseName)?.type;
          const isTimed = exerciseType === "timed" || exerciseType === "conditioning";
          const isConditioning = exerciseType === "conditioning";
          body.append(ui.h("div", { class: "card" },
            ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
              ui.h("span", { class: "title", text: a.exerciseName, style: { cursor: "pointer" }, onClick: () => openDetail(a.exerciseName) }),
              ui.h("button", { class: "btn sm ghost", text: "↑", ariaLabel: `Move ${a.exerciseName} earlier`, onClick: async () => { if (moveSlot(day.accessories, a, -1)) { await Programs.save(p); draw(); } } }),
              ui.h("button", { class: "btn sm ghost", text: "↓", ariaLabel: `Move ${a.exerciseName} later`, onClick: async () => { if (moveSlot(day.accessories, a, 1)) { await Programs.save(p); draw(); } } }),
              ui.h("button", { class: "btn sm ghost danger", text: "Remove", onClick: async () => { day.accessories = day.accessories.filter((x) => x !== a); await Programs.save(p); draw(); } })),
            isTimed ? null : ui.h("div", { class: "row" }, ui.h("span", { text: "Weight" }),
              ui.stepper(a.weightLb, { min: 0, max: 500, step: 2.5, format: ui.fmtWeight, onChange: async (v) => { a.weightLb = v; await Programs.save(p); } })),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Sets" }),
              ui.stepper(a.sets, { min: 1, max: 8, format: (v) => `${v}`, onChange: async (v) => { a.sets = v; await Programs.save(p); } })),
            isTimed ? ui.h("div", { class: "row" }, ui.h("span", { text: isConditioning ? "Duration" : "Hold time" }),
              ui.stepper(a.targetSeconds || 30, { min: 5, max: 1800, step: 5, format: C.cardioDurationLabel, onChange: async (v) => { a.targetSeconds = v; await Programs.save(p); } })) : ui.h("div", { class: "row" }, ui.h("span", { text: "Rep range" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(a.minReps, { min: 1, max: 20, format: (v) => `${v}`, onChange: async (v) => { a.minReps = v; if (a.currentReps < v) a.currentReps = v; await Programs.save(p); } }),
                ui.stepper(a.maxReps, { min: 1, max: 30, format: (v) => `${v}`, onChange: async (v) => { a.maxReps = v; await Programs.save(p); } }))),
            isConditioning ? ui.h("div", { class: "card" },
              ui.h("div", { class: "row" }, ui.h("span", { text: "Effort" }), (() => {
                const select = ui.h("select", {}, ...[["easy", "Easy / conversational"], ["interval", "Intervals"], ["mixed", "Mixed"]]
                  .map(([value, text]) => ui.h("option", { value, text, selected: value === (a.conditioningEffort || "easy") })));
                select.addEventListener("change", async () => { a.conditioningEffort = select.value; await Programs.save(p); });
                return select;
              })()),
              ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Target RPE (0 = none)" }),
                ui.stepper(a.targetRPE || 0, { min: 0, max: 10, onChange: async (v) => { a.targetRPE = v; await Programs.save(p); } })))
              : isTimed ? ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Progress by" }),
              ui.stepper(a.durationStepSeconds ?? 5, { min: 0, max: 60, step: 5, format: (v) => `+${v} sec`, onChange: async (v) => { a.durationStepSeconds = v; await Programs.save(p); } })) : ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Load step (0 = bodyweight)" }),
              ui.stepper(a.incrementLb, { min: 0, max: 25, step: 2.5, format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { a.incrementLb = v; await Programs.save(p); } }))));
        }
        body.append(ui.h("button", { class: "btn ghost wide", text: "+ Add accessory", onClick: () => pickExerciseSheet(async (e) => {
          day.accessories.push({ exerciseName: e.name, order: day.accessories.length,
            sets: e.type === "conditioning" ? 1 : 3, minReps: 8, maxReps: 12, currentReps: 8,
            targetSeconds: e.type === "conditioning" ? 1_200 : 30, durationStepSeconds: 5,
            weightLb: 0, incrementLb: 0, stallCount: 0, capacityManaged: true, maximumSets: 6,
            conditioningEffort: "easy", targetRPE: 0 });
          await Programs.save(p); draw();
        }) }));
      };
      draw();
    },
  });
}

function trackEditor(t) {
  ui.pushScreen({
    title: t.exerciseName,
    build: (body) => {
      const draw = () => {
        ui.clear(body);
        body.append(ui.field("Mode", ui.seg([{ value: "cycle", label: "4-rotation cycle" }, { value: "linear", label: "Linear" }], t.mode, async (m) => { t.mode = m; await Tracks.save(t); draw(); })));
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row" }, ui.h("span", { text: "Increment" }), ui.stepper(t.incrementLb, { min: 2.5, max: 25, step: 2.5, format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { t.incrementLb = v; await Tracks.save(t); refreshSug(); } })),
          ui.h("div", { class: "row" }, ui.h("span", { text: t.mode === "cycle" ? "Rotation-1 weight" : "Current weight" }), ui.stepper(t.baseWeightLb, { min: 0, max: 1000, step: 5, format: ui.fmtWeight, onChange: async (v) => { t.baseWeightLb = v; await Tracks.save(t); refreshSug(); } }))));
        if (t.mode === "cycle") {
          const sel = ui.h("select", {}, ...[1, 2, 3, 4].map((p) => ui.h("option", { value: p, text: C.PHASES[p].name, selected: p === t.nextPhase })));
          sel.addEventListener("change", async () => { t.nextPhase = Number(sel.value); await Tracks.save(t); refreshSug(); });
          body.append(ui.field("Next phase", sel));
          body.append(ui.h("div", { class: "muted", text: `Cycle ${t.cycleNumber}` }));
        }
        body.append(ui.h("div", { class: "section-title", text: "Next suggestion" }));
        const sug = ui.h("div", { class: "big accent" });
        body.append(sug);
        function refreshSug() { const p = t.mode === "cycle" ? C.planFor(t) : C.linearPlan(t.baseWeightLb); sug.textContent = `${ui.fmtWeight(p.weightLb)} · ${p.sets}×${p.reps}`; }
        refreshSug();
      };
      draw();
    },
  });
}

function exerciseLibrary(exercises) {
  ui.pushScreen({
    title: "Exercise library",
    build: (body) => {
      const search = ui.h("input", { type: "search", placeholder: "Exercise, movement, or equipment" });
      const results = ui.h("div");
      body.append(ui.h("button", { class: "btn primary wide", text: "+ New exercise", onClick: () => newExerciseSheet(exercises, () => paint()) }));
      const paint = () => {
        ui.clear(results);
        const term = search.value.trim().toLowerCase();
        const visible = term ? exercises.filter((e) => [e.name, e.movementGroup, e.type,
          C.movementPatternName(e.movementPattern), ...(e.aliases || []), ...(e.strategyTags || [])]
          .some((value) => String(value || "").toLowerCase().includes(term))) : exercises;
        for (const cat of CATEGORIES) {
          const inCat = visible.filter((e) => e.category === cat).sort((a, b) => a.name.localeCompare(b.name));
          if (!inCat.length) continue;
          results.append(ui.h("div", { class: "section-title", text: cat }));
          const card = ui.h("div", { class: "card list" });
          for (const e of inCat) {
            const meta = [C.movementPatternName(e.movementPattern), e.type, C.loadBasisLabel(C.resolvedLoadBasis(e)),
              e.isUnilateral ? "per side" : null, e.gateStatus && e.gateStatus !== "open" ? e.gateStatus : null]
              .filter(Boolean).join(" · ");
            card.append(ui.h("div", { class: "row", onClick: () => exerciseDetail(e) },
              ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: e.name }),
                ui.h("span", { class: "sub", text: meta })),
              ui.h("span", { class: "chev" })));
          }
          results.append(card);
        }
      };
      search.addEventListener("input", paint);
      body.append(search, results);
      paint();
    },
  });
}

function newExerciseSheet(exercises, onSaved) {
  ui.sheet({
    title: "New exercise",
    build: (c, api) => {
      const name = ui.h("input", { type: "text", placeholder: "Exercise name" });
      const category = ui.h("select", {}, ...CATEGORIES.map((value) => ui.h("option", { value, text: value, selected: value === "Accessory" })));
      const type = ui.h("select", {}, ...EX_TYPES.map((value) => ui.h("option", { value, text: value, selected: value === "dumbbell" })));
      const movementGroup = ui.h("input", { type: "text", placeholder: "press, pull, squat, hinge…" });
      const movementPattern = ui.h("select", {}, ...C.MOVEMENT_PATTERNS.map((value) => ui.h("option", {
        value, text: C.movementPatternName(value), selected: value === "unknown",
      })));
      const aliases = ui.h("input", { type: "text", placeholder: "comma-separated alternate names" });
      const notes = ui.h("textarea", { rows: 2, placeholder: "Notes" });
      let unilateral = false;
      c.append(ui.field("Name", name), ui.field("Category", category), ui.field("Type", type),
        ui.field("Movement group", movementGroup), ui.field("Movement pattern", movementPattern),
        ui.field("Aliases", aliases),
        ui.h("div", { class: "row" }, ui.h("span", { text: "Unilateral (per side)" }), ui.toggle(false, (value) => { unilateral = value; })),
        ui.field("Notes", notes));
      c.append(ui.h("button", { class: "btn primary wide", style: { marginTop: "10px" }, text: "Add", onClick: async () => {
        const trimmed = name.value.trim();
        if (!trimmed) { ui.toast("Enter an exercise name."); return; }
        if (exercises.some((exercise) => exercise.name.toLowerCase() === trimmed.toLowerCase())) { ui.toast("That exercise already exists."); return; }
        const exercise = {
          name: trimmed, category: category.value, type: type.value,
          movementGroup: movementGroup.value.trim().toLowerCase(), isUnilateral: unilateral,
          movementPattern: movementPattern.value,
          secondaryMovementPattern: null,
          aliases: aliases.value.split(",").map((value) => value.trim()).filter(Boolean), strategyTags: [],
          loadBasis: C.inferredLoadBasis(type.value), implementCount: C.inferredImplementCount(type.value),
          defaultRestSeconds: 0, notes: notes.value, isShelved: false, shelvedNote: "", watchSite: null,
          gateStatus: "open", gateSite: null, reEntryCriteria: [], completedReEntryCriteria: [],
          reEntryTestWeightLb: 0, reEntryTestSets: 3, reEntryTestReps: 5,
          createdAt: new Date().toISOString(),
        };
        await Exercises.save(exercise); exercises.push(exercise); exercises.sort((a, b) => a.name.localeCompare(b.name));
        api.close(); onSaved();
      } }));
    },
  });
}

// Program membership, last-performed, and progress for one exercise —
// assembled async and filled into `wrap` so the screen renders instantly.
async function exerciseInsight(wrap, e) {
  const [programs, completed] = await Promise.all([Programs.all(), Sessions.completed()]);
  const memberships = [];
  for (const p of programs) {
    for (const d of p.days || []) {
      for (const l of d.lifts || []) if (l.exerciseName === e.name) memberships.push(`${p.name} · ${d.name} (${l.role})`);
      for (const a of d.accessories || []) if (a.exerciseName === e.name) memberships.push(`${p.name} · ${d.name} (accessory)`);
    }
  }
  const hist = []; // newest first (Sessions.completed sorts desc)
  for (const s of completed) {
    const matching = s.exercises.filter((x) => x.exerciseName === e.name);
    const w = matching.flatMap((se) => se.sets.filter((x) => !x.isWarmup && x.status === "completed"));
    if (!w.length) continue;
    const top = w.reduce((b, x) => (!b || x.weightLb > b.weightLb ? x : b), null);
    const longestSeconds = e.type === "timed" ? Math.max(...w.map((set) => set.durationSeconds || 0)) : null;
    const prog = s.programTag
      ? (s.programTag.programName || programs.find((p) => p.id === s.programTag.programId)?.name || "a program")
      : null;
    hist.push({ date: s.date, top, longestSeconds, prog });
  }
  const card = ui.h("div", { class: "card" });
  const last = hist[0];
  card.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Last done" }),
    ui.h("span", { class: "sub", text: last
      ? `${ui.fmtDate(last.date)} — ${e.type === "timed" ? C.cardioDurationLabel(last.longestSeconds) : `${ui.fmtWeight(last.top.weightLb)}${C.loadBasisSuffix(last.top.loadBasis || C.resolvedLoadBasis(e))} × ${last.top.reps}`}${last.prog ? ` · ${last.prog}` : ""}`
      : "not yet" })));
  card.append(ui.h("div", { class: "row" }, ui.h("span", { text: "In programs" }),
    ui.h("span", { class: "sub", style: { textAlign: "right", whiteSpace: "pre-line" }, text: memberships.join("\n") || "none" })));
  if (e.type !== "timed" && hist.length >= 2) {
    const series = [...hist].reverse().slice(-24).map((h) => h.top.weightLb);
    card.append(ui.h("div", { class: "row", style: { borderBottom: "0" } },
      ui.h("span", { text: `Top set, last ${series.length}` }), ui.spark(series)));
  }
  wrap.append(card);
}

function exerciseDetail(e) {
  ui.pushScreen({
    title: e.name,
    build: (body) => {
      const draw = () => {
        ui.clear(body);
        // Muscles first: primary movers red, supporting blue.
        const profile = muscleProfile(e.name, e.movementGroup);
        if (profile) {
          const svg = figureSVG(profile);
          svg.style.maxWidth = "280px"; svg.style.width = "100%";
          body.append(ui.h("div", { class: "card", style: { textAlign: "center", padding: "12px" } },
            svg, ui.h("div", { class: "sub", style: { marginTop: "6px" }, text: muscleBlurb(profile) })));
        }
        const insightWrap = ui.h("div", {});
        body.append(insightWrap);
        exerciseInsight(insightWrap, e);
        const categorySel = ui.h("select", {}, ...CATEGORIES.map((value) => ui.h("option", { value, text: value, selected: value === e.category })));
        categorySel.addEventListener("change", async () => { e.category = categorySel.value; await Exercises.save(e); });
        body.append(ui.field("Category", categorySel));
        const typeSel = ui.h("select", {}, ...EX_TYPES.map((t) => ui.h("option", { value: t, text: t, selected: t === e.type })));
        typeSel.addEventListener("change", async () => { e.type = typeSel.value; await Exercises.save(e); });
        body.append(ui.field("Type", typeSel));
        const basisSel = ui.h("select", {}, ...C.LOAD_BASES.map((basis) => ui.h("option", {
          value: basis, text: C.loadBasisLabel(basis), selected: basis === C.resolvedLoadBasis(e),
        })));
        basisSel.addEventListener("change", async () => { e.loadBasis = basisSel.value; await Exercises.save(e); draw(); });
        body.append(ui.field("Entered load means", basisSel));
        if (C.resolvedLoadBasis(e) === "perImplement") {
          body.append(ui.field("Implements used", ui.stepper(C.resolvedImplementCount(e), {
            min: 1, max: 4, step: 1, onChange: async (v) => { e.implementCount = v; await Exercises.save(e); },
          })));
        }
        const groupInput = ui.h("input", { type: "text", value: e.movementGroup || "", placeholder: "press, pull, squat, hinge…" });
        groupInput.addEventListener("change", async () => { e.movementGroup = groupInput.value.trim().toLowerCase(); await Exercises.save(e); });
        body.append(ui.field("Movement group", groupInput));
        const patternSel = ui.h("select", {}, ...C.MOVEMENT_PATTERNS.map((pattern) => ui.h("option", {
          value: pattern, text: C.movementPatternName(pattern), selected: pattern === e.movementPattern,
        })));
        patternSel.addEventListener("change", async () => { e.movementPattern = patternSel.value; await Exercises.save(e); });
        body.append(ui.field("Primary movement pattern", patternSel));
        const secondarySel = ui.h("select", {}, ui.h("option", { value: "", text: "None", selected: !e.secondaryMovementPattern }),
          ...C.MOVEMENT_PATTERNS.filter((pattern) => pattern !== "unknown").map((pattern) => ui.h("option", {
            value: pattern, text: C.movementPatternName(pattern), selected: pattern === e.secondaryMovementPattern,
          })));
        secondarySel.addEventListener("change", async () => { e.secondaryMovementPattern = secondarySel.value || null; await Exercises.save(e); });
        body.append(ui.field("Secondary pattern", secondarySel));
        const aliases = ui.h("input", { type: "text", value: (e.aliases || []).join(", "), placeholder: "alternate names" });
        aliases.addEventListener("change", async () => { e.aliases = aliases.value.split(",").map((value) => value.trim()).filter(Boolean); await Exercises.save(e); });
        const tags = ui.h("input", { type: "text", value: (e.strategyTags || []).join(", "), placeholder: "low-fatigue, shoulder-friendly…" });
        tags.addEventListener("change", async () => { e.strategyTags = tags.value.split(",").map((value) => value.trim()).filter(Boolean); await Exercises.save(e); });
        body.append(ui.field("Aliases", aliases), ui.field("Programming tags", tags));
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row" }, ui.h("span", { text: "Unilateral (per side)" }), ui.toggle(e.isUnilateral, async (v) => { e.isUnilateral = v; await Exercises.save(e); })),
          // 0 = no rest of its own → the timer falls to the configurable rest
          // buckets in Settings; any value set here wins everywhere.
          // `|| 0`: a raw-imported record can lack the field — an undefined
          // seed would render NaN:NaN and persist NaN on the first tap.
          ui.h("div", { class: "row" }, ui.h("span", { text: "Rest" }), ui.stepper(e.defaultRestSeconds || 0, { min: 0, max: 600, step: 15, format: (v) => (v === 0 ? "Default" : ui.mmss(v)), onChange: async (v) => { e.defaultRestSeconds = v; await Exercises.save(e); } }))));
        const siteSel = ui.h("select", {}, ui.h("option", { value: "", text: "None", selected: !e.watchSite }), ...BODY_SITES.map((s) => ui.h("option", { value: s, text: s, selected: s === e.watchSite })));
        siteSel.addEventListener("change", async () => { e.watchSite = siteSel.value || null; await Exercises.save(e); });
        body.append(ui.field("Watch site", siteSel));

        body.append(ui.h("div", { class: "section-title", text: "Availability & re-entry" }));
        const gateStatus = ui.h("select", {}, ...[["open", "Open"], ["watch", "Watch"], ["shelved", "Shelved"], ["re-entry", "Re-entry test"]]
          .map(([value, text]) => ui.h("option", { value, text, selected: value === (e.gateStatus || (e.isShelved ? "shelved" : "open")) })));
        gateStatus.addEventListener("change", async () => {
          e.gateStatus = gateStatus.value; e.isShelved = gateStatus.value === "shelved";
          await Exercises.save(e); draw();
        });
        const gateSite = ui.h("select", {}, ui.h("option", { value: "", text: "No site", selected: !e.gateSite }),
          ...BODY_SITES.map((site) => ui.h("option", { value: site, text: site, selected: site === e.gateSite })));
        gateSite.addEventListener("change", async () => { e.gateSite = gateSite.value || null; await Exercises.save(e); });
        body.append(ui.field("Status", gateStatus), ui.field("Site", gateSite));
        if ((e.gateStatus || "open") !== "open") {
          const criteria = ui.h("textarea", { rows: 3, value: (e.reEntryCriteria || []).join("\n"),
            placeholder: "One objective criterion per line" });
          criteria.addEventListener("change", async () => {
            e.reEntryCriteria = criteria.value.split("\n").map((value) => value.trim()).filter(Boolean);
            e.completedReEntryCriteria = (e.completedReEntryCriteria || []).filter((item) => e.reEntryCriteria.includes(item));
            await Exercises.save(e); draw();
          });
          body.append(ui.field("Re-entry criteria", criteria));
          for (const criterion of e.reEntryCriteria || []) {
            body.append(ui.h("div", { class: "row" }, ui.h("span", { class: "sub", text: criterion }),
              ui.toggle((e.completedReEntryCriteria || []).includes(criterion), async (checked) => {
                const completed = new Set(e.completedReEntryCriteria || []);
                if (checked) completed.add(criterion); else completed.delete(criterion);
                e.completedReEntryCriteria = [...completed];
                if ((e.reEntryCriteria || []).length && e.reEntryCriteria.every((item) => completed.has(item))) {
                  e.gateStatus = "re-entry"; e.isShelved = false;
                }
                await Exercises.save(e);
              })));
          }
          body.append(ui.h("div", { class: "card" },
            ui.h("div", { class: "sub", text: "Light re-entry test" }),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Load" }), ui.stepper(e.reEntryTestWeightLb || 0, {
              min: 0, max: 1000, step: 5, format: ui.fmtWeight, onChange: async (value) => { e.reEntryTestWeightLb = value; await Exercises.save(e); },
            })),
            ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Sets × reps" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(e.reEntryTestSets || 3, { min: 1, max: 10, onChange: async (value) => { e.reEntryTestSets = value; await Exercises.save(e); } }),
                ui.stepper(e.reEntryTestReps || 5, { min: 1, max: 20, onChange: async (value) => { e.reEntryTestReps = value; await Exercises.save(e); } })))));
        }

        const notes = ui.h("textarea", { rows: 3, placeholder: "Notes", value: e.notes || "" });
        notes.addEventListener("change", async () => { e.notes = notes.value; await Exercises.save(e); });
        body.append(ui.field("Notes", notes));
      };
      draw();
    },
  });
}

function importData() {
  const file = ui.h("input", { type: "file", accept: "application/json,.json" });
  file.addEventListener("change", () => {
    const f = file.files[0]; if (!f) return;
    const r = new FileReader();
    r.onload = async () => {
      // syncLibrary right after the restore: a pre-migration backup re-arms
      // the retired-rest-stamp clear, which otherwise wouldn't run until the
      // next full page load — leaving the rest steppers dead in the meantime.
      try { await importBundle(JSON.parse(r.result)); await syncLibrary(); ui.toast("Imported."); ui.nav.refresh(); }
      catch (error) {
        console.error("Cadence import failed", error);
        ui.toast(`Import failed: ${error?.message || error}`);
      }
    };
    r.onerror = () => ui.toast(`Import failed: ${r.error?.message || "couldn't read the file"}`);
    r.readAsText(f);
  });
  ui.sheet({ title: "Import JSON backup", build: (c, api) => {
    c.append(ui.h("div", { class: "muted", text: "This replaces everything the backup contains: sessions, bodyweight, protein, check-ins, milestones, programs, lift progression, gyms (incl. barcode + plates), the exercise library, and settings. Data missing from the backup is left untouched." }));
    c.append(ui.field("Backup file", file));
    c.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "8px" }, text: "Close", onClick: () => api.close() }));
  } });
}

function resetData() {
  ui.actionSheet("Reset all data?", [
    { label: "Erase and re-seed", role: "danger", onClick: async () => {
      await Checkpoints.create("before-reset");
      await wipeAll({ preserveCheckpoints: true });
      const s = await Settings.get(); s.seededAt = null; await Settings.save(s);
      await ensureSeeded();
      ui.toast("Reset. Recovery point kept."); ui.nav.refresh();
    } },
  ]);
}
