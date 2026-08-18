// Settings — units, rest, year of birth, gyms, progression, exercise library,
// and data export/import (the safety net against Safari storage eviction).
import * as ui from "../ui.js";
import * as C from "../core.js";
import { CATEGORIES, EX_TYPES, BODY_SITES, COPY } from "../constants.js";
import { Settings, Gyms, Tracks, Exercises, Programs, Checkpoints, Intervals, BACKUP_ENUMS, exportJSON, exportCSV, importBundle, wipeAll, ensureSeeded, syncLibrary, localDayKey } from "../db.js";
import { PROGRAM_TEMPLATES, createProgramFromTemplate, bootstrapLiftFromHistory, bootstrapAccessoryFromHistory } from "../templates.js";
import { exportProgramText, importProgramText, programFilename, validateProgramFile } from "../program-file.js";
import { muscleProfile, figureSVG, muscleLegend } from "../anatomy.js";
import { Sessions } from "../db.js";
// Module cycle with session.js is safe: these are hoisted function exports
// used only at runtime (session.js likewise imports exerciseDetail from here).
import { planningBase, previewProgramPlan, volumeFallbackSets } from "./session.js";

// Move a program to a rotation. Placing at/after Peak (rotation 3) with no banked
// Peak result would otherwise make the next rollover treat the skipped Peak as a
// stall and deload; seed a neutral hold (carry current state forward, no note) for
// any lift lacking pending so manual positioning never penalizes. A real Peak
// session logged in rotation 3 overwrites this hold with its grade. Mirrors the
// native ProgramEditorView.positionAtRotation.
async function positionAtRotation(program, rotation) {
  program.currentWeek = rotation;
  if (rotation === C.DELOAD_WEEK) {
    const exerciseByName = new Map((await Exercises.all()).map((exercise) => [exercise.name, exercise]));
    const recoveryOrders = C.recoveryDayOrders((program.days || []).map((day) => {
      const mainName = (day.lifts || []).find((lift) => lift.role === "main")?.exerciseName;
      return { order: day.order ?? 0, mainMovementGroup: exerciseByName.get(mainName)?.movementGroup };
    }));
    program.nextDayIndex = recoveryOrders[0] ?? program.nextDayIndex;
  }
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
  const [settings, gyms, tracks, exercises, programs, checkpoints, intervals] = await Promise.all([Settings.get(), Gyms.all(), Tracks.all(), Exercises.all(), Programs.all(), Checkpoints.all(), Intervals.all()]);
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

  // About you. The only thing age is used for, said plainly — a health app
  // asking for a birthday without saying why is how people learn to distrust
  // one. Bounded by the same plausible-lifespan window the importer enforces,
  // so the picker cannot produce a value a backup would reject.
  root.append(ui.h("div", { class: "section-title", text: "About you" }));
  const thisYear = new Date().getFullYear();
  const yearSelect = ui.h("select", { class: "input" },
    ui.h("option", { value: "0", text: "Not set" }),
    ...Array.from({ length: 121 }, (_, i) => {
      const year = thisYear - i;
      return ui.h("option", { value: String(year), text: String(year) });
    }));
  yearSelect.value = String(settings.birthYear || 0);
  yearSelect.onchange = async () => { settings.birthYear = parseInt(yearSelect.value, 10) || 0; await saveS(); };
  root.append(ui.h("div", { class: "card" },
    ui.h("div", { class: "row" }, ui.h("span", { text: "Year of birth" }), yearSelect),
    ui.h("div", { class: "muted", text: "Used only to adjust the per-meal protein figure on the Body screen — muscle responds less to a given dose with age. Nothing else reads it, and it never affects your program." })));

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

  // Training breaks — declared spans over the calendar. A chosen gap must
  // never read as a lapse (INV-INTERVAL-IS-NOT-A-GAP). Mirrors SettingsView.
  root.append(ui.h("div", { class: "section-title", text: "Training breaks" }));
  const intervalList = ui.h("div", { class: "card list" });
  if (!intervals.length) intervalList.append(ui.h("div", { class: "muted", text: "No declared breaks." }));
  for (const interval of [...intervals].reverse()) {
    const range = interval.startDate === interval.endDate
      ? interval.startDate : `${interval.startDate} – ${interval.endDate}`;
    intervalList.append(ui.h("div", { class: "row", onClick: () => intervalEditor(interval) },
      ui.h("div", { class: "lead" },
        ui.h("span", { class: "title", text: C.TRAINING_INTERVAL_KIND_LABELS[interval.kind] || interval.kind }),
        ui.h("span", { class: "sub", text: range + (interval.note ? ` · ${interval.note}` : "") })),
      ui.h("span", { class: "chev" })));
  }
  root.append(intervalList);
  root.append(ui.h("button", { class: "btn ghost wide", text: "+ Add break", onClick: async () => {
    const today = localDayKey(new Date());
    await Intervals.save({ kind: "rest", startDate: today, endDate: today, enteredAsDays: true, note: "" });
    ui.nav.refresh();
  } }));
  root.append(ui.h("div", { class: "sub", style: { margin: "4px" }, text: "Declared breaks — deload, rest, away, active recovery — keep a chosen gap from reading as a lapse. Work banked during an active-recovery break stays in history but never advances progression or PR baselines." }));

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

function dominantPrescriptions(template) {
  const counts = new Map();
  for (const day of template.days || []) for (const lift of day.lifts || []) {
    const style = C.resolvedPrescriptionStyle(
      lift.prescription || "automatic", null, lift.role || "main", template.focus || "strength",
    );
    counts.set(style, (counts.get(style) || 0) + 1);
  }
  if (!counts.size) return "Accessory progression";
  return [...counts.entries()]
    .sort(([aStyle, aCount], [bStyle, bCount]) => bCount - aCount || aStyle.localeCompare(bStyle))
    .slice(0, 2)
    .map(([style]) => C.prescriptionShortName(style))
    .join(" + ");
}

function openTemplateSheet() {
  ui.sheet({
    title: "Start from a template",
    build: (content, api) => {
      for (const template of PROGRAM_TEMPLATES) {
        content.append(ui.h("button", {
          class: "card wide", style: { marginTop: "8px", textAlign: "left" },
          onClick: async () => {
            await createProgramFromTemplate(template);
            api.close();
            ui.nav.refresh();
          },
        },
        ui.h("span", { style: { display: "flex", flexDirection: "column", gap: "4px" } },
          ui.h("span", { class: "title", text: template.name }),
          ui.h("span", { class: "sub", text: template.tagline }),
          ui.h("span", { class: "sub", text: `${template.days.length} days · ${template.focus} · ${dominantPrescriptions(template)}` }))));
      }
      content.append(ui.h("button", { class: "btn wide ghost", style: { marginTop: "12px" },
        text: "Cancel", onClick: () => api.close() }));
    },
  });
}

export function openAddProgramSheet(programs) {
  ui.sheet({
    title: "Add program",
    build: (content, api) => {
      content.append(
        ui.h("button", { class: "btn wide primary", style: { marginTop: "8px" },
          text: "Start from a template", onClick: () => { api.close(); openTemplateSheet(); } }),
        ui.h("button", { class: "btn wide", style: { marginTop: "8px" }, text: "Blank program", onClick: async () => {
          let number = programs.length + 1;
          const names = new Set(programs.map((program) => program.name));
          while (names.has(`Program ${number}`)) number += 1;
          await Programs.save({ name: `Program ${number}`, focus: "strength", cycleNumber: 1,
            currentWeek: 1, nextDayIndex: 0, roundingLb: 5,
            isActive: programs.length === 0, days: [] });
          api.close();
          ui.nav.refresh();
        } }),
        ui.h("button", { class: "btn wide", style: { marginTop: "8px" },
          text: "Import a program file", onClick: () => { api.close(); importProgram(); } }),
        ui.h("button", { class: "btn wide ghost", style: { marginTop: "12px" },
          text: "Cancel", onClick: () => api.close() }),
      );
    },
  });
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

// One picker surface for every selection workflow (issues #63/#66): search
// (always available), equipment filter chips, shelved marking, and a detail
// preview (ⓘ) that opens OVER the picker — the search text and active filter
// survive the inspection, so picking after reading never restarts the hunt.
// Shared by the program editor's slot pickers and the logger's add-exercise
// sheet.
export function exercisePickerList(all, onPick, { availableOnly = false } = {}) {
  const wrap = ui.h("div");
  const search = ui.h("input", { type: "search", placeholder: "Exercise, movement, or equipment" });
  const chips = ui.h("div", { class: "btn-row", style: { flexWrap: "wrap", gap: "6px", margin: "8px 0" }, role: "group", "aria-label": "Filter by equipment" });
  const results = ui.h("div");
  let typeFilter = null;
  const paint = () => {
    ui.clear(chips);
    for (const type of [null, ...EX_TYPES]) {
      chips.append(ui.h("button", {
        class: `btn sm ${typeFilter === type ? "primary" : "ghost"}`,
        text: type === null ? "All" : type,
        "aria-pressed": String(typeFilter === type),
        onClick: () => { typeFilter = typeFilter === type ? null : type; paint(); },
      }));
    }
    ui.clear(results);
    // Raw query in: the shared matcher owns normalization and returns true on
    // empty, so no pre-trim/lowercase or empty-branch here.
    const pool = availableOnly ? all.filter(C.exerciseIsAvailableForProgramming) : all;
    const visible = pool.filter((exercise) => (typeFilter === null || exercise.type === typeFilter)
      && C.exerciseMatchesSearch(exercise, search.value));
    for (const cat of CATEGORIES) {
      const inCat = visible.filter((e) => e.category === cat).sort((a, b) => a.name.localeCompare(b.name));
      if (!inCat.length) continue;
      results.append(ui.h("div", { class: "section-title", text: cat }));
      for (const e of inCat) {
        results.append(ui.h("div", { class: "row", style: { borderBottom: "0", gap: "6px", padding: "3px 0" } },
          ui.h("button", { class: "btn wide ghost", style: { flex: "1", justifyContent: "space-between" },
            onClick: () => onPick(e) },
          ui.h("span", { text: e.name }),
          e.isShelved ? ui.h("span", { class: "pill hard", text: COPY.shelved }) : ui.h("span")),
          ui.h("button", { class: "btn sm ghost", text: "ⓘ",
            "aria-label": `${e.name} — muscles, history, and settings`,
            onClick: () => exerciseDetail(e) })));
      }
    }
    if (!visible.length) results.append(ui.h("div", { class: "muted", text: "No exercises match." }));
  };
  search.addEventListener("input", paint);
  wrap.append(search, chips, results);
  paint();
  return wrap;
}

function pickExerciseSheet(onPick) {
  Exercises.all().then((all) => {
    ui.sheet({ title: "Pick exercise", build: (c, api) => {
      c.append(exercisePickerList(all, (e) => { api.close(); onPick(e); }, { availableOnly: true }));
    } });
  });
}

function removeDay(p, day) {
  // nextDayIndex addresses a day by its ORDER VALUE, not a list position.
  // Remember which day it points at before renumbering — clamping after a
  // renumber silently re-addresses the schedule on sparse-order programs
  // (imported files keep verbatim orders). Mirrors SettingsView.deleteDays.
  const pointed = p.days.find((d) => d.order === p.nextDayIndex);
  p.days = p.days.filter((d) => d !== day);
  p.days.sort((a, b) => a.order - b.order).forEach((d, i) => { d.order = i; });
  p.nextDayIndex = pointed && pointed !== day ? pointed.order : 0;
}

function orderedSlots(slots = []) {
  // Program slots (lifts AND accessories) always go through the shared
  // role-aware ordering — its ordinal tiebreak is deliberate so the editor
  // shows the same sequence as home/session/native/export regardless of the
  // browser's collation. Only day lists (name-keyed, no exerciseName) keep a
  // local sort.
  if (slots.some((slot) => slot.exerciseName != null)) return C.orderedProgramSlots(slots);
  return [...slots].sort((a, b) => (a.order ?? 0) - (b.order ?? 0)
    || String(a.name || "").localeCompare(String(b.name || "")));
}

function moveSlot(slots, slot, delta) {
  const ordered = orderedSlots(slots);
  const from = ordered.indexOf(slot);
  const to = from + delta;
  if (from < 0 || to < 0 || to >= ordered.length) return false;
  // Role-first ordering is enforced at display time: a move across the
  // main/complementary boundary would re-render in the same place while
  // silently rewriting every authored order, so refuse it — with a reason,
  // not a dead-feeling button. Mirrors SettingsView.moveLifts.
  if ((ordered[from].role || null) !== (ordered[to].role || null)) {
    ui.toast("Main work stays ahead of complementary work.");
    return false;
  }
  [ordered[from], ordered[to]] = [ordered[to], ordered[from]];
  ordered.forEach((item, index) => { item.order = index; });
  return true;
}

async function activateProgram(p) {
  const all = await Programs.all();
  for (const x of all) { const want = x.id === p.id; if (x.isActive !== want) { x.isActive = want; await Programs.save(x); } }
  p.isActive = true;
}

export async function programEditor(p) {
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
        // A bodyweight lift's base IS zero — pull-ups start unloaded by
        // design, so the missing-base warning would fire forever on a slot
        // that is configured exactly right.
        const liftExercise = exerciseByName.get(lift.exerciseName);
        if (!(lift.baseWeightLb > 0)
          && (!liftExercise || C.resolvedLoadBasis(liftExercise) !== "bodyweight")) {
          warnings.push(`${lift.exerciseName} needs a rotation-1 base weight.`);
        }
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
        // A loaded accessory with no increment can never add weight — it
        // climbs reps past its own maximum forever. Flag it rather than let
        // the slot quietly stop progressing.
        // resolvedLoadBasis mirrors the native Exercise.loadBasis getter:
        // explicit value, else inferred from equipment. A raw read would be
        // undefined for records that predate the explicit field.
        if (exercise && C.accessoryCannotProgressLoad(exercise.type, C.resolvedLoadBasis(exercise), accessory.weightLb, accessory.incrementLb)) {
          warnings.push(`${accessory.exerciseName} carries load but has no increment, so it can never add weight. Set an increment.`);
        }
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
        // Values from the backup enum (the same list import/export validates
        // against), labels from the core map — a third policy added to db.js
        // must appear here without touching this view.
        const equipment = ui.h("select", {}, ...BACKUP_ENUMS.equipmentPolicies.map((value) => ui.h("option", {
          value, text: C.EQUIPMENT_POLICY_LABELS[value] || value,
          selected: value === (p.equipmentPolicy || "any"),
        })));
        equipment.addEventListener("change", async () => {
          p.equipmentPolicy = equipment.value;
          await Programs.save(p);
        });
        body.append(ui.field("Equipment", equipment));
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
        const sortedDays = [...p.days].sort((a, b) => a.order - b.order);
        const pos = ui.h("div", { class: "card" });
        pos.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Cycle" }),
          ui.stepper(p.cycleNumber, { min: 1, max: 99, step: 1, onChange: async (v) => { p.cycleNumber = v; await Programs.save(p); } })));
        pos.append(ui.h("div", { class: "row", style: { borderBottom: sortedDays.length ? undefined : "0" } }, ui.h("span", { text: "Rotation" }),
          // Position, not phase — this pointer is shared by every slot in the
          // program, and most styles never run a Volume/Load/Peak wave. The
          // per-slot badges say what each one does. Mirrors SettingsView.
          ui.stepper(p.currentWeek, { min: 1, max: C.DELOAD_WEEK, step: 1, format: (v) => `${v} of ${C.DELOAD_WEEK}`, onChange: async (v) => { await positionAtRotation(p, v); await Programs.save(p); } })));
        if (sortedDays.length) {
          const daySel = ui.h("select", {}, ...sortedDays.map((d) => ui.h("option", { value: String(d.order), text: d.name, selected: d.order === p.nextDayIndex })));
          daySel.addEventListener("change", async () => { p.nextDayIndex = Number(daySel.value); await Programs.save(p); });
          pos.append(ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Next day" }), daySel));
        }
        body.append(pos);
        body.append(ui.h("div", { class: "sub", style: { margin: "4px" }, text: "Set your position mid-cycle. Rotations 1–3 are complete authored passes (volume/load/peak); recovery is one representative lower and upper exposure, then rollover. Weights are the rotation-1 base." }));
        body.append(ui.h("div", { class: "section-title", text: "Days" }));
        const list = ui.h("div", { class: "card list" });
        const days = [...p.days].sort((a, b) => a.order - b.order);
        if (!days.length) list.append(ui.h("div", { class: "muted", text: "No days. Add one below." }));
        for (const day of days) {
          list.append(ui.h("div", { class: "row" },
            ui.h("div", { class: "lead", style: { cursor: "pointer", flex: "1" }, onClick: () => programDayEditor(p, day) },
              ui.h("div", { style: { display: "flex", alignItems: "center", gap: "8px" } },
                ui.h("span", { class: "title", text: day.name }),
                ui.h("span", { class: "pill accent", text: C.DAY_TRAINING_INTENT_LABELS[day.trainingIntent || "general"] })),
              ui.h("span", { class: "sub", text: orderedSlots(day.lifts).map((l) => l.exerciseName).join(" + ") || "empty" })),
            // The schedule pointer follows ITS day through a renumbering
            // move, never a clamped position (mirrors SettingsView.moveDays).
            ui.h("button", { class: "btn sm ghost", text: "↑", ariaLabel: `Move ${day.name} earlier`, onClick: async () => { const pointed = p.days.find((d) => d.order === p.nextDayIndex); if (moveSlot(p.days, day, -1)) { if (pointed) p.nextDayIndex = pointed.order; await Programs.save(p); draw(); } } }),
            ui.h("button", { class: "btn sm ghost", text: "↓", ariaLabel: `Move ${day.name} later`, onClick: async () => { const pointed = p.days.find((d) => d.order === p.nextDayIndex); if (moveSlot(p.days, day, 1)) { if (pointed) p.nextDayIndex = pointed.order; await Programs.save(p); draw(); } } }),
            ui.h("button", { class: "btn sm ghost danger", text: "Delete", onClick: async () => { removeDay(p, day); await Programs.save(p); draw(); } })));
        }
        body.append(list);
        body.append(ui.h("button", { class: "btn ghost wide", text: "+ Add day", onClick: async () => {
          p.days.push({ name: `Day ${p.days.length + 1}`, order: p.days.length,
            trainingIntent: "general", lifts: [], accessories: [] });
          await Programs.save(p); draw();
        } }));
        // The plan, not a snapshot: no stall counters, no stashed peak grade,
        // no wave position, no slot ids. Those are this lifter's state, not
        // properties of the program.
        body.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "8px" }, text: "Export program", onClick: () => {
          // Validate what we are about to hand over. A blank name or a day with
          // no slots writes a file every Cadence importer rejects, and the
          // lifter finds out on the other device.
          const text = exportProgramText(p);
          const problems = validateProgramFile(JSON.parse(text));
          if (problems.length) { ui.toast(`Not exported — ${problems[0]}`); return; }
          ui.download(programFilename(p), text, "application/json");
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
        const intent = ui.h("select", {}, ...BACKUP_ENUMS.dayTrainingIntents.map((value) => ui.h("option", {
          value, text: C.DAY_TRAINING_INTENT_LABELS[value] || value,
          selected: value === (day.trainingIntent || "general"),
        })));
        intent.addEventListener("change", async () => {
          day.trainingIntent = intent.value;
          await Programs.save(p);
        });
        body.append(ui.field("Training intent", intent));

        body.append(ui.h("div", { class: "section-title", text: "Lifts" }));
        // The editor's exercise edits (rest, load basis, station plates)
        // change the exposure previews below, so Back redraws the day. Same
        // accessible title-button the logger uses — one affordance, not a
        // keyboard-invisible span here and a real button there.
        const openDetail = async (name) => { const ex = await Exercises.byName(name); if (ex) exerciseDetail(ex, { onClose: draw }); };
        const detailTitle = (name) => ui.h("button", { class: "title title-button", text: name,
          "aria-label": `${name} — muscles, history, and settings`, onClick: () => openDetail(name) });
        for (const l of orderedSlots(day.lifts)) {
          const orderedDays = [...(p.days || [])].sort((a, b) => (a.order ?? 0) - (b.order ?? 0));
          const recoveryOrders = C.recoveryDayOrders(orderedDays.map((candidate) => {
            const mainName = orderedSlots(candidate.lifts).find((lift) => lift.role === "main")?.exerciseName;
            return { order: candidate.order ?? 0, mainMovementGroup: exerciseByName.get(mainName)?.movementGroup };
          }));
          const schedule = {
            targetDayOrder: day.order ?? 0,
            nextDayOrder: p.nextDayIndex ?? 0,
            allDayOrders: orderedDays.map((candidate) => candidate.order ?? 0),
            recoveryDayOrders: recoveryOrders,
            // Production synchronizes only twins still at the same base. A
            // manually diverged slot is an independent progression and must not
            // inflate this preview.
            synchronizedDayOrders: orderedDays.filter((candidate) =>
              (candidate.lifts || []).some((slot) => slot.exerciseName === l.exerciseName
                && (slot.prescription || "automatic") === (l.prescription || "automatic")
                && Math.abs((slot.baseWeightLb ?? 0) - (l.baseWeightLb ?? 0)) < 0.001))
              .map((candidate) => candidate.order ?? 0),
          };
          // The preview is the only OUTPUT on this card, so a stepper that
          // saves without refreshing it leaves the lifter reading the previous
          // walk — which defeats the point of showing the 188-vs-190 lb
          // rounding difference at all. A full draw() would be worse: these
          // steppers are pressed repeatedly, and rebuilding the whole editor
          // under a held control fights the hand doing the pressing. So the
          // preview node is swapped in place instead.
          const exercise = exerciseByName.get(l.exerciseName);
          let preview = ui.exposurePreview(l, p, exercise, 4, schedule);
          const refresh = () => {
            // Rebuild the schedule too: editing this base can intentionally
            // split or rejoin a synchronized progression.
            schedule.synchronizedDayOrders = orderedDays.filter((candidate) =>
              (candidate.lifts || []).some((slot) => slot.exerciseName === l.exerciseName
                && (slot.prescription || "automatic") === (l.prescription || "automatic")
                && Math.abs((slot.baseWeightLb ?? 0) - (l.baseWeightLb ?? 0)) < 0.001))
              .map((candidate) => candidate.order ?? 0);
            const next = ui.exposurePreview(l, p, exercise, 4, schedule);
            preview.replaceWith(next);
            preview = next;
          };
          body.append(ui.h("div", { class: "card" },
            ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
              detailTitle(l.exerciseName),
              ui.h("button", { class: "btn sm ghost", text: "↑", ariaLabel: `Move ${l.exerciseName} earlier`, onClick: async () => { if (moveSlot(day.lifts, l, -1)) { await Programs.save(p); draw(); } } }),
              ui.h("button", { class: "btn sm ghost", text: "↓", ariaLabel: `Move ${l.exerciseName} later`, onClick: async () => { if (moveSlot(day.lifts, l, 1)) { await Programs.save(p); draw(); } } }),
              ui.h("button", { class: "btn sm ghost danger", text: "Remove", onClick: async () => { day.lifts = day.lifts.filter((x) => x !== l); await Programs.save(p); draw(); } })),
            // What this slot actually does, resolved through the engine — the
            // picker below can still say "Automatic".
            ui.h("div", { class: "row", style: { borderBottom: "0", paddingTop: "0" } },
              ui.slotBadge(l, p.currentWeek, exerciseByName.get(l.exerciseName)?.movementGroup ?? null, p.focus)),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Role" }),
              // draw(): the deload row's visibility resolves through role.
              ui.seg([{ value: "main", label: "Main" }, { value: "complementary", label: "Comp." }], l.role, async (v) => { l.role = v; await Programs.save(p); draw(); })),
            ui.h("div", { class: "row" }, ui.h("span", { text: "Prescription" }), (() => {
              const select = ui.h("select", {}, ...C.selectablePrescriptions([
                ["automatic", "Automatic"], ["wave", "Strength wave"], ["offsetWave", "Strength wave — offsets"],
                ["secondary", "Secondary volume"], ["hypertrophy", "Hypertrophy"], ["technique", "Technique"],
                ["doubleProgression", "Double progression"],
                ["linearFives", "Linear progression"], ["texasVolume", "Texas — volume day"],
                ["texasLight", "Texas — light day"], ["texasIntensity", "Texas — intensity day"],
                ["fiveThreeOne", "5/3/1 wave"], ["maxEffort", "Max effort"], ["dynamicEffort", "Dynamic effort"],
              ], l.prescription || "automatic").map(([value, label]) => ui.h("option", { value, text: label, selected: (l.prescription || "automatic") === value })));
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
            ui.h("div", { class: "row" }, ui.h("span", { text: ({
              maxEffort: "Current target", dynamicEffort: "Wave step-1 base", fiveThreeOne: "Training max",
            })[C.resolvedPrescriptionStyle(l.prescription || "automatic", exerciseByName.get(l.exerciseName)?.movementGroup ?? null, l.role, p.focus)] || "Rotation-1 base" }),
              // A hand-set base is its own truth: clearing the last earned
              // increment switches off the honest-base repair (planningBase)
              // for this slot until the next machine advance re-earns it.
              ui.stepper(l.baseWeightLb, { min: 0, max: 1000, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: ui.fmtWeight, onChange: async (v) => { l.baseWeightLb = v; l.lastIncrementLb = 0; await Programs.save(p); refresh(); } })),
            l.prescription === "offsetWave" ? ui.h("div", { class: "row" }, ui.h("span", { text: "Load / peak offsets" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(l.loadOffsetLb ?? 0, { min: 0, max: 100, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { l.loadOffsetLb = v; await Programs.save(p); refresh(); } }),
                ui.stepper(l.peakOffsetLb ?? 0, { min: 0, max: 150, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { l.peakOffsetLb = v; await Programs.save(p); refresh(); } }))) : null,
            // Every wave-shaped style deloads at this slot's own intensity.
            // Gated on the RESOLVED style so the knob never appears where the
            // engine would ignore it (automatic on a complementary slot
            // resolves secondary, whose 75% is fixed). Mirrors SettingsView.
            ["wave", "offsetWave"].includes(C.resolvedPrescriptionStyle(l.prescription || "automatic", exerciseByName.get(l.exerciseName)?.movementGroup ?? null, l.role, p.focus))
              ? ui.h("div", { class: "row" }, ui.h("span", { text: "Recovery intensity" }),
                ui.stepper(l.deloadMultiplier ?? 0.775, { min: 0.5, max: 0.9, step: 0.025, format: (v) => `${C.trim(v * 100, 1)}%`, onChange: async (v) => { l.deloadMultiplier = Math.round(v * 1000) / 1000; await Programs.save(p); refresh(); } })) : null,
            ["linearFives", "texasVolume", "texasLight", "texasIntensity"].includes(l.prescription)
              ? ui.h("div", { class: "row" }, ui.h("span", { text: "Working sets" }),
                ui.stepper(l.doubleProgressionSets ?? 3, { min: 1, max: 10, onChange: async (v) => { l.doubleProgressionSets = v; await Programs.save(p); refresh(); } })) : null,
            l.prescription === "linearFives"
              ? ui.h("div", { class: "row" }, ui.h("span", { text: "Working reps" }),
                ui.seg([{ value: 5, label: "5 reps" }, { value: 3, label: "3 reps" }],
                  (l.currentReps ?? 5) <= 3 ? 3 : 5,
                  async (v) => { l.currentReps = v; await Programs.save(p); refresh(); })) : null,
            l.prescription === "doubleProgression" ? ui.h("div", { class: "row" }, ui.h("span", { text: "Sets / rep window" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(l.doubleProgressionSets ?? 3, { min: 1, max: 8, onChange: async (v) => { l.doubleProgressionSets = v; await Programs.save(p); refresh(); } }),
                ui.stepper(l.minimumReps ?? 5, { min: 1, max: 20, onChange: async (v) => { l.minimumReps = v; await Programs.save(p); refresh(); } }),
                ui.stepper(l.maximumReps ?? 8, { min: 1, max: 30, onChange: async (v) => { l.maximumReps = v; await Programs.save(p); refresh(); } }))) : null,
            l.prescription === "maxEffort" ? ui.h("div", { class: "sub", text: "The base is today's top-single target. Build through 90% and a near-max single, then rotate to a different special variation next week." }) : null,
            l.prescription === "dynamicEffort" ? ui.h("div", { class: "sub", text: "The base is wave week 1: 50% for squat/pull or 40% for bench. Speed work waves for three weeks, then resets." }) : null,
            !C.buildsOwnSessionShape(C.resolvedPrescriptionStyle(l.prescription || "automatic", exerciseByName.get(l.exerciseName)?.movementGroup ?? null, l.role, p.focus))
              ? ui.h("div", { class: "row" }, ui.h("span", { text: "Peak top single" }),
                ui.toggle(!!l.peakSingleEnabled, async (v) => { l.peakSingleEnabled = v; await Programs.save(p); draw(); })) : null,
            l.peakSingleEnabled && !C.buildsOwnSessionShape(C.resolvedPrescriptionStyle(l.prescription || "automatic", exerciseByName.get(l.exerciseName)?.movementGroup ?? null, l.role, p.focus)) ? ui.h("div", { class: "row" }, ui.h("span", { text: "Last clean / step" }),
              ui.h("div", { class: "btn-row" },
                ui.stepper(l.lastPeakSingleLb ?? 0, { min: 0, max: 1200, step: 5, format: ui.fmtWeight, onChange: async (v) => { l.lastPeakSingleLb = v; await Programs.save(p); refresh(); } }),
                ui.stepper(l.peakSingleIncrementLb ?? 5, { min: 2.5, max: 25, step: 2.5, format: (v) => `+${ui.fmtWeight(v)}`, onChange: async (v) => { l.peakSingleIncrementLb = v; await Programs.save(p); refresh(); } }))) : null,
            !C.buildsOwnSessionShape(C.resolvedPrescriptionStyle(l.prescription || "automatic", exerciseByName.get(l.exerciseName)?.movementGroup ?? null, l.role, p.focus))
              ? ui.h("div", { class: "row" }, ui.h("span", { text: "Phase primer single" }),
                ui.toggle(l.phasePrimerEnabled !== false, async (v) => { l.phasePrimerEnabled = v; await Programs.save(p); refresh(); })) : null,
            ui.h("div", { class: "row" }, ui.h("span", { text: "One-tap drop (0 = auto)" }),
              ui.stepper(l.dropIncrementLb ?? 0, { min: 0, max: 50, step: C.programLoadStep(p.roundingLb, exerciseByName.get(l.exerciseName)?.type), format: ui.fmtWeight, onChange: async (v) => { l.dropIncrementLb = v; await Programs.save(p); } })),
            ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Est. 1RM" }),
              ui.stepper(l.estimatedMaxLb, { min: 0, max: 1200, step: 5, format: ui.fmtWeight, onChange: async (v) => { l.estimatedMaxLb = v; await Programs.save(p); refresh(); } })),
            // What all of the above produces. Every other value on this card is
            // an input; without this, nothing on it is an output.
            preview));
        }
        body.append(ui.h("button", { class: "btn ghost wide", text: "+ Add lift", onClick: () => pickExerciseSheet(async (e) => {
          const bootstrap = await bootstrapLiftFromHistory(e, { role: "complementary",
            focus: p.focus, roundingLb: p.roundingLb });
          day.lifts.push({ exerciseName: e.name, role: "complementary", order: day.lifts.length, prescription: "automatic", warmupPolicy: "automatic", baseWeightLb: bootstrap.baseWeightLb, estimatedMaxLb: bootstrap.estimatedMaxLb, stallCount: 0, lastIncrementLb: 0 });
          await Programs.save(p); draw();
        }) }));

        body.append(ui.h("div", { class: "section-title", text: "Accessories" }));
        for (const a of orderedSlots(day.accessories)) {
          const exerciseType = exerciseByName.get(a.exerciseName)?.type;
          const isTimed = exerciseType === "timed" || exerciseType === "conditioning";
          const isConditioning = exerciseType === "conditioning";
          body.append(ui.h("div", { class: "card" },
            ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
              detailTitle(a.exerciseName),
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
          const bootstrap = await bootstrapAccessoryFromHistory(e);
          day.accessories.push({ exerciseName: e.name, order: day.accessories.length,
            sets: e.type === "conditioning" ? 1 : 3, minReps: 8, maxReps: 12, currentReps: 8,
            targetSeconds: e.type === "conditioning" ? 1_200 : 30, durationStepSeconds: 5,
            weightLb: bootstrap.weightLb, incrementLb: bootstrap.incrementLb, stallCount: 0, capacityManaged: true, maximumSets: 6,
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

// Editor for one declared training break. The two entry affordances — a day
// count or an explicit date range — write the same inclusive "yyyy-MM-dd"
// start/end pair; `enteredAsDays` remembers which shape to reopen in.
// Mirrors native IntervalEditorView.
function intervalEditor(interval) {
  // Noon-anchored so date math never slips a day at a DST edge.
  const dayMs = (s) => new Date(`${s}T12:00:00`).getTime();
  const shiftDay = (s, days) => localDayKey(new Date(dayMs(s) + days * 86_400_000));
  const dayCount = () => Math.round((dayMs(interval.endDate) - dayMs(interval.startDate)) / 86_400_000) + 1;
  const kindFooter = {
    deload: "Reduced-load training inside the cycle. Sessions are still expected on deload days.",
    rest: "Planned days off. Not missed days.",
    away: "Travel, closure, illness, layoff. Not missed days — expect a re-entry suggestion when it ends.",
    activeRecovery: "Real work, deliberately off-program. Sessions banked inside it stay in history but never advance progression or PR baselines.",
  };
  ui.pushScreen({
    title: "Training break",
    onClose: () => ui.nav.refresh(),
    build: (body, api) => {
      const draw = () => {
        ui.clear(body);
        const save = async () => { await Intervals.save(interval); };
        body.append(ui.field("Kind", ui.seg(
          C.TRAINING_INTERVAL_KINDS.map((kind) => ({ value: kind, label: C.TRAINING_INTERVAL_KIND_LABELS[kind] })),
          interval.kind, async (kind) => { interval.kind = kind; await save(); draw(); })));
        // The kinds stay distinct on purpose (INV-INTERVAL-KINDS-STAY-DISTINCT)
        // — each reads differently to the engine, so each says what it means.
        body.append(ui.h("div", { class: "muted", text: kindFooter[interval.kind] || "" }));
        body.append(ui.field("Enter as", ui.seg(
          [{ value: "days", label: "Number of days" }, { value: "range", label: "Date range" }],
          interval.enteredAsDays === false ? "range" : "days",
          async (mode) => { interval.enteredAsDays = mode === "days"; await save(); draw(); })));
        const startInput = ui.h("input", { class: "input", type: "date", value: interval.startDate });
        startInput.addEventListener("change", async () => {
          if (!startInput.value) return;
          const count = dayCount();
          interval.startDate = startInput.value;
          // Moving the start keeps the declared LENGTH in days mode; the
          // range shape keeps the end (clamped, never inverted).
          if (interval.enteredAsDays !== false) interval.endDate = shiftDay(interval.startDate, count - 1);
          else if (interval.endDate < interval.startDate) interval.endDate = interval.startDate;
          await save(); draw();
        });
        body.append(ui.field("Starts", startInput));
        if (interval.enteredAsDays !== false) {
          body.append(ui.h("div", { class: "card" }, ui.h("div", { class: "row", style: { borderBottom: "0" } },
            ui.h("span", { text: "Length" }),
            ui.stepper(dayCount(), { min: 1, max: 365, step: 1,
              format: (v) => `${v} day${v === 1 ? "" : "s"}`,
              onChange: async (v) => { interval.endDate = shiftDay(interval.startDate, Math.max(1, v) - 1); await save(); } }))));
        } else {
          const endInput = ui.h("input", { class: "input", type: "date", value: interval.endDate });
          endInput.addEventListener("change", async () => {
            if (!endInput.value) return;
            interval.endDate = endInput.value < interval.startDate ? interval.startDate : endInput.value;
            await save(); draw();
          });
          body.append(ui.field("Ends", endInput));
        }
        const noteInput = ui.h("input", { class: "input", type: "text", placeholder: "Optional note", value: interval.note || "" });
        noteInput.addEventListener("change", async () => { interval.note = noteInput.value; await save(); });
        body.append(ui.field("Note", noteInput));
        body.append(ui.h("button", { class: "btn ghost danger wide", text: "Delete break", onClick: () => {
          ui.actionSheet("Delete this break? Sessions and history are unchanged.", [
            { label: "Delete break", role: "destructive", onClick: async () => { await Intervals.del(interval.id); api.close(); } },
            { label: "Cancel", role: "cancel", onClick: () => {} },
          ]);
        } }));
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
        // Raw query in: the shared matcher owns normalization and returns
        // true on empty, so no pre-trim/lowercase or empty-branch here.
        const visible = exercises.filter((exercise) => C.exerciseMatchesSearch(exercise, search.value));
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
  const [programs, completed, gym] = await Promise.all([Programs.all(), Sessions.completed(), Gyms.default()]);
  const barLb = C.barLb(gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb);
  const memberships = [];
  const cycleMemberships = [];
  for (const p of programs) {
    for (const d of p.days || []) {
      for (const l of d.lifts || []) if (l.exerciseName === e.name) {
        memberships.push(`${p.name} · ${d.name} (${l.role})`);
        cycleMemberships.push({ program: p, day: d, lift: l });
      }
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

  if (cycleMemberships.length) {
    wrap.append(ui.h("div", { class: "section-title", text: "Program cycle" }));
    for (const { program, day, lift } of cycleMemberships) {
      const cycle = ui.h("div", { class: "card" },
        ui.h("div", { class: "title", style: { marginBottom: "4px" }, text: `${program.name} · ${day.name}` }));
      // The shared preview pipeline (planningBase + volume-fallback sets +
      // gym snapping), exactly like the Home card and the session the app
      // will create — the raw stored base showed a different table than
      // every other surface. Base and fallback sets are phase-invariant, so
      // compute them once per membership, not per rotation row.
      const base = planningBase(lift, e, program, completed);
      const addedSets = volumeFallbackSets(lift, program);
      for (let rotation = 1; rotation <= C.DELOAD_WEEK; rotation++) {
        const { plan } = previewProgramPlan(lift, e, program, rotation, { base, addedSets, barLb, gym });
        const phaseLabel = C.slotPhaseLabel(rotation, lift.role, lift.prescription || "automatic",
          e.movementGroup, program.focus) || `R${rotation}`;
        cycle.append(ui.h("div", { class: "row" },
          ui.h("div", { class: "lead" },
            ui.h("span", { class: "sub", text: phaseLabel }),
            ui.h("span", { class: rotation === program.currentWeek ? "sub accent" : "sub",
              text: C.rotationContextLabel(rotation, program.currentWeek) })),
          ui.h("div", { style: { textAlign: "right" } },
            ui.h("div", { class: "title mono", text: plan.weightLb > 0 ? ui.fmtWeight(plan.weightLb) : "Bodyweight" }),
            ui.h("div", { class: "sub mono", text: `${plan.sets}×${plan.reps}` }))));
      }
      wrap.append(cycle);
    }
  }
}

// Exported: the logger's exercise titles open the same lift info screen the
// library and program editor use — muscles figure, history, settings. The
// caller may pass onClose to repaint itself: this screen live-edits the
// exercise (rest, load basis, type, shelving), and a logger underneath must
// not keep showing the pre-edit state.
export function exerciseDetail(e, { onClose } = {}) {
  ui.pushScreen({
    title: e.name,
    onClose,
    build: (body) => {
      const draw = () => {
        ui.clear(body);
        // Muscles first: primary movers red, supporting blue.
        const profile = muscleProfile(e.name, e.movementGroup);
        if (profile) {
          const svg = figureSVG(profile);
          svg.style.maxWidth = "280px"; svg.style.width = "100%";
          body.append(ui.h("div", { class: "card anatomy-card" },
            ui.h("div", { class: "section-title", text: "Muscles" }), svg, muscleLegend(profile)));
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
        if (e.type === "barbell") {
          // The station this lift lives at can stock a single plate
          // denomination — a kg-only deadlift platform beside lb squat racks.
          // The preference rides the exercise the same way its rest default
          // does; prescriptions, warmups, and the plate hint all solve
          // against the station's plates. Mirrors native LibraryView.
          const stationSel = ui.h("select", {},
            ...[["", "Gym inventory"], ["lb", "lb only"], ["kg", "kg only"]]
              .map(([value, text]) => ui.h("option", { value, text, selected: value === (e.stationDenomination || "") })));
          stationSel.addEventListener("change", async () => { e.stationDenomination = stationSel.value || null; await Exercises.save(e); });
          body.append(ui.field("Station plates", stationSel));
        }
        const siteSel = ui.h("select", {}, ui.h("option", { value: "", text: "None", selected: !e.watchSite }), ...BODY_SITES.map((s) => ui.h("option", { value: s, text: s, selected: s === e.watchSite })));
        siteSel.addEventListener("change", async () => { e.watchSite = siteSel.value || null; await Exercises.save(e); });
        body.append(ui.field("Watch site", siteSel));

        body.append(ui.h("div", { class: "section-title", text: "Availability & re-entry" }));
        const gateStatus = ui.h("select", {}, ...[["open", "Open"], ["watch", "Watch"], ["shelved", "Shelved"], ["re-entry", "Re-entry test"]]
          .map(([value, text]) => ui.h("option", { value, text, selected: value === C.exerciseGateStatus(e) })));
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
      try {
        const summary = await importBundle(JSON.parse(r.result));
        await syncLibrary();
        // Say so rather than repair silently — the backup carried a slot id on
        // two programs, and the later one has been re-issued.
        const repaired = summary?.repairedSlotIDs || 0;
        ui.toast(repaired
          ? `Imported. Repaired ${repaired} duplicate slot ${repaired === 1 ? "id" : "ids"} the backup reused across programs.`
          : "Imported.");
        ui.nav.refresh();
      }
      catch (error) {
        console.error("Cadence import failed", error);
        ui.toast(`Import failed: ${error?.message || error}`);
      }
    };
    r.onerror = () => ui.toast(`Import failed: ${r.error?.message || "couldn't read the file"}`);
    r.readAsText(f);
  });
  ui.sheet({ title: "Import JSON backup", build: (c, api) => {
    c.append(ui.h("div", { class: "muted", text: "This replaces everything the backup contains: sessions, bodyweight, check-ins, milestones, programs, lift progression, gyms (incl. barcode + plates), the exercise library, and settings. Data missing from the backup is left untouched." }));
    c.append(ui.field("Backup file", file));
    c.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "8px" }, text: "Close", onClick: () => api.close() }));
  } });
}

/// Import a single program. Deliberately separate from importData: this adds
/// one program, never replaces a domain, and needs no checkpoint because a
/// file that fails validation or names an unknown exercise changes nothing.
function importProgram() {
  const file = ui.h("input", { type: "file", accept: "application/json,.json" });
  file.addEventListener("change", () => {
    const f = file.files[0]; if (!f) return;
    const r = new FileReader();
    r.onload = async () => {
      try {
        const report = await importProgramText(r.result);
        ui.toast([
          `${report.action === "created" ? "Created" : "Updated"} ${report.name} — `
          + `${report.days} day${report.days === 1 ? "" : "s"}, ${report.lifts} lift${report.lifts === 1 ? "" : "s"}, `
          + `${report.accessories} accessor${report.accessories === 1 ? "y" : "ies"}.`,
          ...report.warnings,
        ].join(" "));
        ui.nav.refresh();
      } catch (error) {
        console.error("Cadence program import failed", error);
        ui.toast(`Import failed: ${error?.message || error}`);
      }
    };
    r.onerror = () => ui.toast(`Import failed: ${r.error?.message || "couldn't read the file"}`);
    r.readAsText(f);
  });
  ui.sheet({ title: "Import a program", build: (c, api) => {
    c.append(ui.h("div", { class: "muted", text: "Adds one program. Sessions, bodyweight, milestones, gyms, and settings are left alone, and an existing program is never overwritten. Every exercise the file names has to already be in your library." }));
    c.append(ui.field("Program file", file));
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
