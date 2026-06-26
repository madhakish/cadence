// Settings — units, rest, protein target, gyms, progression, exercise library,
// and data export/import (the safety net against Safari storage eviction).
import * as ui from "../ui.js";
import * as C from "../core.js";
import { CATEGORIES, EX_TYPES, BODY_SITES } from "../constants.js";
import { Settings, Gyms, Tracks, Exercises, Programs, exportJSON, exportCSV, importBundle, wipeAll, ensureSeeded } from "../db.js";

export async function render(host) {
  const [settings, gyms, tracks, exercises, programs] = await Promise.all([Settings.get(), Gyms.all(), Tracks.all(), Exercises.all(), Programs.all()]);
  const root = ui.h("div");
  const saveS = async () => { await Settings.save(settings); ui.prefs.unitDisplay = settings.unitDisplay; };

  // Units
  root.append(ui.h("div", { class: "section-title", text: "Units" }));
  root.append(ui.h("div", { class: "card" },
    ui.seg([{ value: "lbPrimary", label: "lb" }, { value: "kgPrimary", label: "kg" }, { value: "both", label: "Both" }],
      settings.unitDisplay, async (v) => { settings.unitDisplay = v; await saveS(); ui.nav.refresh(); })));

  // Rest timers
  root.append(ui.h("div", { class: "section-title", text: "Rest timer defaults" }));
  const restCard = ui.h("div", { class: "card" });
  restCard.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Main lifts" }),
    ui.stepper(settings.mainLiftRestSeconds, { min: 60, max: 600, step: 30, format: ui.mmss, onChange: async (v) => { settings.mainLiftRestSeconds = v; await saveS(); } })));
  restCard.append(ui.h("div", { class: "row" }, ui.h("span", { text: "Accessory" }),
    ui.stepper(settings.accessoryRestSeconds, { min: 30, max: 300, step: 15, format: ui.mmss, onChange: async (v) => { settings.accessoryRestSeconds = v; await saveS(); } })));
  root.append(restCard);

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
    const g = { name: `Gym ${gyms.length + 1}`, isDefault: gyms.length === 0, defaultBarId: C.barId(C.BARS.bar45lb), plateToggles: C.ALL_STANDARD.map((p) => ({ value: p.value, unit: p.unit, enabled: true })), barcodeImage: null, barcodeLabel: "Membership tag" };
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
        ui.h("span", { class: "sub", text: `${p.focus} · ${p.days.length} days · Cycle ${p.cycleNumber}, Wk${p.currentWeek}${p.isActive ? " · active" : ""}` })),
      ui.h("span", { class: "chev" })));
  }
  root.append(progList);

  root.append(ui.h("div", { class: "section-title", text: "Progression (standalone lifts)" }));
  const trackList = ui.h("div", { class: "card list" });
  if (!tracks.length) trackList.append(ui.h("div", { class: "muted", text: "No tracked lifts." }));
  for (const t of tracks) {
    const sug = t.mode === "cycle" ? C.planFor(t) : C.linearPlan(t.baseWeightLb);
    trackList.append(ui.h("div", { class: "row", onClick: () => trackEditor(t) },
      ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: t.exerciseName }),
        ui.h("span", { class: "sub", text: `+${C.trim(t.incrementLb)} lb per ${t.mode === "cycle" ? "cycle" : "session"} · next: ${C.sessionPlanLabel(sug)}` })),
      ui.h("span", { class: "chev" })));
  }
  root.append(trackList);

  // Library
  root.append(ui.h("div", { class: "section-title", text: "Library" }));
  root.append(ui.h("div", { class: "card list" },
    ui.h("div", { class: "row", onClick: () => exerciseLibrary(exercises), style: { borderBottom: "0" } },
      ui.h("span", { class: "title", text: "Exercise library" }), ui.h("span", { class: "chev" }))));

  // Data
  root.append(ui.h("div", { class: "section-title", text: "Data" }));
  root.append(ui.h("div", { class: "card" },
    ui.h("div", { class: "btn-row" },
      ui.h("button", { class: "btn", text: "Export JSON", onClick: async () => ui.download("comeback-export.json", await exportJSON()) }),
      ui.h("button", { class: "btn", text: "Export CSV", onClick: async () => ui.download("comeback-sets.csv", await exportCSV(), "text/csv") }),
      ui.h("button", { class: "btn ghost", text: "Import JSON", onClick: () => importData() })),
    ui.h("div", { class: "sub", style: { marginTop: "8px" }, text: "Export regularly — iOS Safari can clear local data. Import restores from a JSON backup." })));
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

function programEditor(p) {
  ui.pushScreen({
    title: p.name,
    build: (body) => {
      body.append(ui.field("Training focus", ui.seg(
        [{ value: "strength", label: "Strength" }, { value: "hypertrophy", label: "Hypertrophy" }, { value: "maintain", label: "Maintain" }],
        p.focus, async (v) => { p.focus = v; await Programs.save(p); })));
      body.append(ui.h("div", { class: "card" },
        ui.h("div", { class: "row" }, ui.h("span", { text: "Rounding" }),
          ui.stepper(p.roundingLb, { min: 2.5, max: 10, step: 2.5, format: (v) => `${C.trim(v)} lb`, onChange: async (v) => { p.roundingLb = v; await Programs.save(p); } })),
        ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Active" }),
          ui.toggle(p.isActive, async (v) => { p.isActive = v; await Programs.save(p); }))));
      body.append(ui.h("div", { class: "sub", style: { margin: "4px" }, text: `Cycle ${p.cycleNumber}, week ${p.currentWeek}. Lifts progress automatically — weights here are the current week-1 base.` }));
      body.append(ui.h("div", { class: "section-title", text: "Days" }));
      const list = ui.h("div", { class: "card list" });
      for (const day of [...p.days].sort((a, b) => a.order - b.order)) {
        list.append(ui.h("div", { class: "row", onClick: () => programDayEditor(p, day) },
          ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: day.name }),
            ui.h("span", { class: "sub", text: day.lifts.map((l) => l.exerciseName).join(" + ") })),
          ui.h("span", { class: "chev" })));
      }
      body.append(list);
    },
  });
}

function programDayEditor(p, day) {
  ui.pushScreen({
    title: day.name,
    build: (body) => {
      body.append(ui.h("div", { class: "section-title", text: "Lifts" }));
      for (const l of [...day.lifts].sort((a, b) => (a.role === "main" ? 0 : 1) - (b.role === "main" ? 0 : 1))) {
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } },
            ui.h("span", { class: "title", text: l.exerciseName }), ui.h("span", { class: "pill", text: l.role })),
          ui.h("div", { class: "row" }, ui.h("span", { text: "Week-1 base" }),
            ui.stepper(l.baseWeightLb, { min: 0, max: 1000, step: p.roundingLb, format: (v) => `${C.trim(v)} lb`, onChange: async (v) => { l.baseWeightLb = v; await Programs.save(p); } })),
          ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Est. 1RM" }),
            ui.stepper(l.estimatedMaxLb, { min: 0, max: 1200, step: 5, format: (v) => `${C.trim(v)} lb`, onChange: async (v) => { l.estimatedMaxLb = v; await Programs.save(p); } }))));
      }
      body.append(ui.h("div", { class: "section-title", text: "Accessories" }));
      for (const a of day.accessories) {
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row", style: { borderBottom: "0", paddingBottom: "2px" } }, ui.h("span", { class: "title", text: a.exerciseName })),
          ui.h("div", { class: "row" }, ui.h("span", { text: "Weight" }),
            ui.stepper(a.weightLb, { min: 0, max: 500, step: 2.5, format: (v) => `${C.trim(v)} lb`, onChange: async (v) => { a.weightLb = v; await Programs.save(p); } })),
          ui.h("div", { class: "row" }, ui.h("span", { text: "Sets" }),
            ui.stepper(a.sets, { min: 1, max: 8, format: (v) => `${v}`, onChange: async (v) => { a.sets = v; await Programs.save(p); } })),
          ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Rep range" }),
            ui.h("div", { class: "btn-row" },
              ui.stepper(a.minReps, { min: 1, max: 20, format: (v) => `${v}`, onChange: async (v) => { a.minReps = v; if (a.currentReps < v) a.currentReps = v; await Programs.save(p); } }),
              ui.stepper(a.maxReps, { min: 1, max: 30, format: (v) => `${v}`, onChange: async (v) => { a.maxReps = v; await Programs.save(p); } })))));
      }
    },
  });
}

function trackEditor(t) {
  ui.pushScreen({
    title: t.exerciseName,
    build: (body) => {
      const draw = () => {
        ui.clear(body);
        body.append(ui.field("Mode", ui.seg([{ value: "cycle", label: "4-week cycle" }, { value: "linear", label: "Linear" }], t.mode, async (m) => { t.mode = m; await Tracks.save(t); draw(); })));
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row" }, ui.h("span", { text: "Increment" }), ui.stepper(t.incrementLb, { min: 2.5, max: 25, step: 2.5, format: (v) => `+${C.trim(v)} lb`, onChange: async (v) => { t.incrementLb = v; await Tracks.save(t); refreshSug(); } })),
          ui.h("div", { class: "row" }, ui.h("span", { text: t.mode === "cycle" ? "Week-1 weight" : "Current weight" }), ui.stepper(t.baseWeightLb, { min: 0, max: 1000, step: 5, format: (v) => `${C.trim(v)} lb`, onChange: async (v) => { t.baseWeightLb = v; await Tracks.save(t); refreshSug(); } }))));
        if (t.mode === "cycle") {
          const sel = ui.h("select", {}, ...[1, 2, 3, 4].map((p) => ui.h("option", { value: p, text: C.PHASES[p].name, selected: p === t.nextPhase })));
          sel.addEventListener("change", async () => { t.nextPhase = Number(sel.value); await Tracks.save(t); refreshSug(); });
          body.append(ui.field("Next phase", sel));
          body.append(ui.h("div", { class: "muted", text: `Cycle ${t.cycleNumber}` }));
        }
        body.append(ui.h("div", { class: "section-title", text: "Next suggestion" }));
        const sug = ui.h("div", { class: "big accent" });
        body.append(sug);
        function refreshSug() { sug.textContent = C.sessionPlanLabel(t.mode === "cycle" ? C.planFor(t) : C.linearPlan(t.baseWeightLb)); }
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
      for (const cat of CATEGORIES) {
        const inCat = exercises.filter((e) => e.category === cat).sort((a, b) => a.name.localeCompare(b.name));
        if (!inCat.length) continue;
        body.append(ui.h("div", { class: "section-title", text: cat }));
        const card = ui.h("div", { class: "card list" });
        for (const e of inCat) {
          card.append(ui.h("div", { class: "row", onClick: () => exerciseDetail(e) },
            ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: e.name }),
              ui.h("span", { class: "sub", text: [e.isShelved ? "shelved" : null, e.isUnilateral ? "per side" : null].filter(Boolean).join(" · ") || e.type })),
            ui.h("span", { class: "chev" })));
        }
        body.append(card);
      }
    },
  });
}

function exerciseDetail(e) {
  ui.pushScreen({
    title: e.name,
    build: (body) => {
      const draw = () => {
        ui.clear(body);
        const typeSel = ui.h("select", {}, ...EX_TYPES.map((t) => ui.h("option", { value: t, text: t, selected: t === e.type })));
        typeSel.addEventListener("change", async () => { e.type = typeSel.value; await Exercises.save(e); });
        body.append(ui.field("Type", typeSel));
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row" }, ui.h("span", { text: "Unilateral (per side)" }), ui.toggle(e.isUnilateral, async (v) => { e.isUnilateral = v; await Exercises.save(e); })),
          ui.h("div", { class: "row" }, ui.h("span", { text: "Rest" }), ui.stepper(e.defaultRestSeconds, { min: 0, max: 600, step: 15, format: ui.mmss, onChange: async (v) => { e.defaultRestSeconds = v; await Exercises.save(e); } }))));
        const siteSel = ui.h("select", {}, ui.h("option", { value: "", text: "None", selected: !e.watchSite }), ...BODY_SITES.map((s) => ui.h("option", { value: s, text: s, selected: s === e.watchSite })));
        siteSel.addEventListener("change", async () => { e.watchSite = siteSel.value || null; await Exercises.save(e); });
        body.append(ui.field("Watch site", siteSel));

        const shelvedNote = ui.h("textarea", { rows: 2, placeholder: "Re-entry test", value: e.shelvedNote || "" });
        shelvedNote.addEventListener("change", async () => { e.shelvedNote = shelvedNote.value; await Exercises.save(e); });
        const shelvedWrap = ui.h("div", {}, ui.field("Re-entry test", shelvedNote));
        shelvedWrap.style.display = e.isShelved ? "" : "none";
        body.append(ui.h("div", { class: "card" },
          ui.h("div", { class: "row", style: { borderBottom: "0" } }, ui.h("span", { text: "Shelved" }), ui.toggle(e.isShelved, async (v) => { e.isShelved = v; await Exercises.save(e); shelvedWrap.style.display = v ? "" : "none"; })),
          shelvedWrap));

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
      try { await importBundle(JSON.parse(r.result)); ui.toast("Imported."); ui.nav.refresh(); }
      catch { ui.toast("Couldn't read that file."); }
    };
    r.readAsText(f);
  });
  ui.sheet({ title: "Import JSON backup", build: (c, api) => {
    c.append(ui.h("div", { class: "muted", text: "This replaces sessions, bodyweight, protein, check-ins, and milestones with the contents of the backup." }));
    c.append(ui.field("Backup file", file));
    c.append(ui.h("button", { class: "btn ghost wide", style: { marginTop: "8px" }, text: "Close", onClick: () => api.close() }));
  } });
}

function resetData() {
  ui.actionSheet("Reset all data?", [
    { label: "Erase and re-seed", role: "danger", onClick: async () => { await wipeAll(); const s = await Settings.get(); s.seededAt = null; await Settings.save(s); await ensureSeeded(); ui.toast("Reset."); ui.nav.refresh(); } },
  ]);
}
