// Body — bodyweight trend and daily protein logging.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { lineChart } from "../charts.js";
import { Bodyweight, Protein, Settings, iso } from "../db.js";

export async function render(host) {
  const [weights, todays, settings, total] = await Promise.all([
    Bodyweight.all(), Protein.today(), Settings.get(), Protein.todayTotal(),
  ]);
  weights.sort((a, b) => new Date(a.date) - new Date(b.date));
  const root = ui.h("div");

  // Bodyweight
  root.append(ui.h("div", { class: "section-title", text: "Bodyweight" }));
  const bw = ui.h("div", { class: "card" });
  if (weights.length > 1) {
    const display = (lb) => C.primaryUnit(settings.unitDisplay) === "kg" ? C.kgFromLb(lb) : lb;
    bw.append(lineChart(weights.map((w) => ({ t: new Date(w.date).getTime(), y: display(w.weightLb), ann: w.milestoneLabel || null })), { fmtY: (v) => C.trim(v) }));
  }
  const latest = weights[weights.length - 1];
  if (latest) {
    bw.append(ui.h("div", { class: "row", style: { borderBottom: "0" } },
      ui.h("div", { class: "lead" },
        ui.h("span", { class: "big mono", text: ui.fmtWeight(latest.weightLb) }),
        ui.h("span", { class: "sub", text: ui.fmtDate(latest.date) + (latest.bodyFatPercent ? ` · ${C.trim(latest.bodyFatPercent)}% bf` : "") }))));
  } else {
    bw.append(ui.h("div", { class: "muted", text: "No weigh-ins yet." }));
  }
  bw.append(ui.h("button", { class: "btn wide", style: { marginTop: "8px" }, text: "+ Log weight", onClick: () => logWeight() }));
  root.append(bw);

  // Protein
  root.append(ui.h("div", { class: "section-title", text: "Protein" }));
  const target = settings.proteinTargetGrams;
  const pct = Math.min(1, total / target);
  const pcard = ui.h("div", { class: "card" },
    ui.h("div", { class: "row", style: { borderBottom: "0" } },
      ui.h("span", { class: "big mono", text: `${Math.round(total)} g` }),
      ui.h("span", { class: "muted", text: `/ ${Math.round(target)} g today` })),
    ui.h("div", { class: "progress" }, ui.h("i", { style: { width: `${pct * 100}%`, background: total >= target ? "var(--good)" : "var(--accent)" } })),
    ui.h("div", { class: "btn-row", style: { marginTop: "10px" } },
      ui.h("button", { class: "btn sm", text: "Shake ~45g", onClick: () => add(45, "Shake") }),
      ui.h("button", { class: "btn sm", text: "Meat ~50g", onClick: () => add(50, "Meat") })));
  const custom = ui.h("input", { type: "number", inputmode: "numeric", placeholder: "grams" });
  pcard.append(ui.h("div", { class: "btn-row", style: { marginTop: "8px" } }, custom,
    ui.h("button", { class: "btn sm primary", text: "Add", onClick: () => { const g = parseFloat(custom.value); if (g > 0) add(g, "Custom"); } })));
  root.append(pcard);

  if (todays.length) {
    root.append(ui.h("div", { class: "section-title", text: "Today's entries" }));
    const list = ui.h("div", { class: "card" });
    for (const p of todays.sort((a, b) => new Date(b.date) - new Date(a.date))) {
      list.append(ui.h("div", { class: "row" },
        ui.h("div", { class: "lead" }, ui.h("span", { class: "title", text: p.label }), ui.h("span", { class: "sub mono", text: `${Math.round(p.grams)} g` })),
        ui.h("button", { class: "btn sm ghost danger", text: "Delete", onClick: async () => { await Protein.del(p.id); ui.nav.refresh(); } })));
    }
    root.append(list);
  }

  host.replaceChildren(root);

  async function add(grams, label) { await Protein.add({ date: iso(new Date()), grams, label }); ui.nav.refresh(); }
}

function logWeight() {
  ui.sheet({
    title: "Log weight",
    build: (c, api) => {
      const unit = C.primaryUnit(ui.prefs.unitDisplay);
      const w = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal", placeholder: unit });
      const bf = ui.h("input", { type: "number", inputmode: "decimal", placeholder: "optional" });
      const ms = ui.h("input", { type: "text", placeholder: "optional annotation" });
      c.append(ui.field(`Weight (${unit})`, w), ui.field("Body fat %", bf), ui.field("Milestone label", ms));
      c.append(ui.h("button", {
        class: "btn primary wide", style: { marginTop: "10px" }, text: "Save",
        onClick: async () => {
          const val = parseFloat(w.value);
          if (!(val > 0)) { ui.toast("Enter a weight."); return; }
          await Bodyweight.add({ date: iso(new Date()), weightLb: C.toLb(val, unit), bodyFatPercent: parseFloat(bf.value) || null, milestoneLabel: ms.value || null });
          api.close(); ui.nav.refresh();
        },
      }));
    },
  });
}
