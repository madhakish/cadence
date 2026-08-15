// Body — bodyweight trend and advisory protein guidance.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { lineChart } from "../charts.js";
import { Bodyweight, Settings, Checkins, iso } from "../db.js";
import * as signals from "./signals.js";

export async function render(host) {
  const [weights, settings, checkins] = await Promise.all([Bodyweight.all(), Settings.get(), Checkins.all()]);
  weights.sort((a, b) => new Date(a.date) - new Date(b.date));
  const root = ui.h("div");

  const latestBySite = new Map();
  for (const checkin of checkins) {
    const prior = latestBySite.get(checkin.site);
    if (!prior || new Date(checkin.date) > new Date(prior.date)) latestBySite.set(checkin.site, checkin);
  }
  const hardStops = [...latestBySite.values()].filter((item) => C.isHardStopResponse(item.response)).length;
  root.append(ui.h("button", { class: "card row wide", ariaLabel: `Signals${hardStops ? `, ${hardStops} active hard stops` : ""}`,
    onClick: () => ui.pushScreen({ title: "Signals", build: (body) => { signals.render(body); } }) },
  ui.h("span", { class: "title", text: "⚡ Signals" }),
  hardStops ? ui.h("span", { class: "pill hard", text: String(hardStops) }) : ui.h("span", { class: "chev" })));

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

  // Protein — advice, not a tracker.
  //
  // Serving-level logging was retired in backup schema 6: counting grams only
  // works with a real meal-entry surface, and a half-measure the lifter
  // abandons after a week is worse than an honest target. Age changes the
  // per-meal threshold, so it is shown when there is a birth year to use.
  const age = C.ageFromBirthYear(settings.birthYear, new Date().getFullYear());
  const guidance = C.proteinSummary(latest?.weightLb, age);
  if (guidance) {
    root.append(ui.h("div", { class: "section-title", text: "Protein" }));
    const pcard = ui.h("div", { class: "card" }, ui.h("div", { text: guidance }));
    // Naming the assumption rather than hiding it: the per-meal figure is the
    // older-adult one until the lifter says otherwise.
    pcard.append(ui.h("div", { class: "sub", style: { marginTop: "6px" },
      text: C.proteinPerMealRationale(age)
        || "Add your year of birth in Settings for an age-adjusted per-meal figure." }));
    pcard.append(ui.h("div", { class: "muted", style: { marginTop: "6px" },
      text: "Guidance only — Cadence does not track what you eat." }));
    root.append(pcard);
  }

  host.replaceChildren(root);
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
