// Plate calculator — target → per-side, or on-the-bar → total. Always reachable
// from the floating action button.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { barbellSVG } from "../barbell.js";
import { Gyms, Settings } from "../db.js";

export async function openPlateCalculator() {
  const [gyms, settings] = await Promise.all([Gyms.all(), Settings.get()]);
  let gym = gyms.find((g) => g.isDefault) || gyms[0] || null;
  let mode = "target";
  let bar = gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb;
  let unit = C.primaryUnit(settings.unitDisplay);
  let targetVal = unit === "kg" ? C.kgFromLb(135) : 135;
  const counts = {}; // plateId -> count, for reverse mode

  const availablePlates = () => {
    const list = gym && gym.plateToggles ? gym.plateToggles.filter((t) => t.enabled).map((t) => ({ value: t.value, unit: t.unit })) : C.ALL_STANDARD;
    return [...list].sort((a, b) => C.plateLb(b) - C.plateLb(a));
  };

  ui.pushScreen({
    title: "Plate calculator",
    build: (body) => {
      const panel = ui.h("div");
      const draw = () => {
        ui.clear(panel);
        panel.append(ui.seg([{ value: "target", label: "Target" }, { value: "reverse", label: "On the bar" }], mode, (m) => { mode = m; draw(); }));

        const barSel = ui.h("select", {}, ...C.ALL_BARS.map((b) => ui.h("option", { value: C.barId(b), text: C.barLabel(b), selected: C.barId(b) === C.barId(bar) })));
        barSel.addEventListener("change", () => { bar = C.barById(barSel.value); draw(); });
        panel.append(ui.field("Bar", barSel));
        if (gyms.length > 1) {
          const gymSel = ui.h("select", {}, ...gyms.map((g) => ui.h("option", { value: g.name, text: g.name, selected: gym && g.name === gym.name })));
          gymSel.addEventListener("change", () => { gym = gyms.find((g) => g.name === gymSel.value); bar = C.barById(gym.defaultBarId); draw(); });
          panel.append(ui.field("Gym", gymSel));
        }

        if (mode === "target") drawTarget(panel);
        else drawReverse(panel);
      };

      function drawTarget(p) {
        const input = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal", step: "0.5", value: String(targetVal) });
        input.addEventListener("input", () => { targetVal = parseFloat(input.value) || 0; result(); });
        p.append(ui.field("Target total", input));
        p.append(ui.seg([{ value: "lb", label: "lb" }, { value: "kg", label: "kg" }], unit, (u) => { unit = u; result(); }));
        const out = ui.h("div", { class: "card" });
        p.append(out);
        result();
        function result() {
          const targetLb = C.toLb(targetVal, unit);
          const sol = C.solve(targetLb, bar, availablePlates());
          ui.clear(out);
          // The answer, drawn: the loaded bar itself, big — the SAME solution
          // as the list below (which may pick the other unit system).
          if (targetLb > 0) {
            out.append(ui.h("div", { class: "barbell-hero" }, barbellSVG(targetLb, unit, bar, gym, sol).svg));
          }
          out.append(ui.h("div", { class: "section-title", text: "Per side" }));
          if (!sol.perSide.length) out.append(ui.h("div", { class: "big", text: "Bar only" }));
          for (const pc of sol.perSide) {
            out.append(ui.h("div", { class: "row" },
              ui.h("span", { class: "title" + (pc.plate.unit === "kg" ? " accent" : ""), text: C.plateLabel(pc.plate) }),
              ui.h("span", { class: "mono", text: `× ${pc.count}` })));
          }
          out.append(ui.h("div", { class: "section-title", text: "Total achieved" }));
          out.append(ui.h("div", { class: "big mono", text: C.both(sol.totalLb) }));
          out.append(ui.h("div", { class: "sub", text: `on ${C.barLabel(bar)}` }));
          if (sol.isOffTarget) {
            const deviation = unit === "kg" ? C.kgFromLb(Math.abs(sol.deviationLb)) : Math.abs(sol.deviationLb);
            out.append(ui.h("div", { class: "card", style: { background: "rgba(255,204,0,0.16)", marginTop: "10px" } },
              ui.h("span", { class: "warn", text: `⚠︎ Closest load is off target by ${C.trim(deviation)} ${unit}.` })));
          }
        }
      }

      function drawReverse(p) {
        const plates = availablePlates();
        const out = ui.h("div", { class: "card" });
        const hero = ui.h("div", { class: "barbell-hero" });
        const total = ui.h("div", { class: "big mono" });
        const sub = ui.h("div", { class: "sub" });
        const recompute = () => {
          const perSide = plates.map((pl) => ({ plate: pl, count: counts[C.plateId(pl)] || 0 })).filter((pc) => pc.count > 0);
          const totalLb = C.totalOnBar(bar, perSide);
          // Draw exactly what the user says is on the bar — never re-solve it.
          ui.clear(hero);
          hero.append(barbellSVG(totalLb, "lb", bar, gym, { perSide, totalLb }).svg);
          total.textContent = C.both(totalLb);
          sub.textContent = `total on ${C.barLabel(bar)}`;
        };
        for (const pl of plates) {
          const id = C.plateId(pl);
          out.append(ui.h("div", { class: "row" },
            ui.h("span", { class: "title" + (pl.unit === "kg" ? " accent" : ""), text: C.plateLabel(pl) }),
            ui.stepper(counts[id] || 0, { min: 0, max: 12, onChange: (v) => { counts[id] = v; recompute(); } })));
        }
        p.append(out);
        p.append(ui.h("button", { class: "btn ghost wide danger", text: "Clear", onClick: () => { for (const k of Object.keys(counts)) counts[k] = 0; draw(); } }));
        const totalCard = ui.h("div", { class: "card" }, ui.h("div", { class: "section-title", text: "On the bar" }), hero, total, sub);
        p.append(totalCard);
        recompute();
      }

      draw();
      body.append(panel);
    },
  });
}
