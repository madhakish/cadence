// Plate calculator — target → exact per-side stack, or entered stack → total.
// The complete bar is the primary answer on phone and desktop.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { barbellSVG, barbellStage, loadoutSummary, mixedEquipmentNote, plateBadgeSVG } from "../barbell.js";
import { Gyms, Settings } from "../db.js";

const plateKey = (plate, style) => ui.h("span", { class: "plate-key" },
  plateBadgeSVG(plate, style),
  ui.h("span", { class: `title${plate.unit === "kg" ? " accent" : ""}`, text: C.plateLabel(plate) }));

function expandedBar(solution, plateStyle, requestedLb = null) {
  ui.pushScreen({ title: "Loaded bar", build: (body) => {
    const rendered = barbellSVG(solution, "full", plateStyle);
    body.append(barbellStage(rendered, { caption: "Mirrored stack · counts are per side", emphasis: "expanded" }),
      loadoutSummary(requestedLb, solution),
      ui.h("div", { class: "section-title", text: "Plates per side" }));
    const list = ui.h("div", { class: "card plate-list" });
    if (!solution.perSide.length) list.append(ui.h("div", { class: "big", text: solution.collarLb ? "Bar + collars" : "Bar only" }));
    for (const count of solution.perSide) {
      list.append(ui.h("div", { class: "row plate-row" }, plateKey(count.plate, plateStyle),
        ui.h("strong", { class: "mono", text: `× ${count.count}` })));
    }
    body.append(list);
  } });
}

// Reference-only plate families: colour, denomination, and the other-unit
// conversion, for recognising what's on the rack. Not inventory — nothing
// here reaches the solver; the 55 lb disc is listed for recognition only.
// Mirrors native PlateCalculatorView.referenceSection.
const PLATE_REFERENCE = {
  kg: [25, 20, 15, 10, 5, 2.5, 1.25].map((value) => ({ value, unit: "kg" })),
  lb: [55, 45, 35, 25, 10, 5, 2.5].map((value) => ({ value, unit: "lb" })),
};
const PLATE_REFERENCE_NOTE = "Kilogram colours follow the IWF and IPF code; pound bumpers follow the common "
  + "manufacturer code, and 5 lb and under are black iron. Colours never change with the theme. "
  + "This guide is reference only: the 55 lb disc is listed for recognition and is never added "
  + "to a gym's inventory or offered to the solver.";

export async function openPlateCalculator() {
  const [gyms, settings] = await Promise.all([Gyms.all(), Settings.get()]);
  let gym = gyms.find((option) => option.isDefault) || gyms[0] || null;
  let mode = "target";
  let bar = gym ? C.barById(gym.defaultBarId) : C.BARS.bar45lb;
  let unit = C.primaryUnit(settings.unitDisplay);
  let plateStyle = "steel";
  let referenceUnit = unit;
  let referenceOpen = false;
  let targetVal = unit === "kg" ? C.kgFromLb(135) : 135;
  const counts = {};
  const enteredOrder = [];

  const availablePlates = () => {
    const list = gym && Array.isArray(gym.plateToggles) && gym.plateToggles.length
      ? gym.plateToggles.filter((toggle) => toggle.enabled)
        .map(({ value, unit: plateUnit }) => ({ value, unit: plateUnit }))
      : C.ALL_STANDARD;
    return [...list].sort((a, b) => C.plateLb(b) - C.plateLb(a));
  };

  ui.pushScreen({ title: "Plate calculator", build: (body) => {
    const panel = ui.h("div", { class: "plate-calculator" });
    body.append(panel);

    const draw = () => {
      ui.clear(panel);
      panel.append(ui.seg([{ value: "target", label: "Target" }, { value: "reverse", label: "On the bar" }],
        mode, (next) => { mode = next; draw(); }));
      if (mode === "target") drawTarget(); else drawReverse();
      drawEquipment();
      drawReference();
    };

    const drawReference = () => {
      const details = ui.h("details", { class: "card plate-reference" },
        ui.h("summary", {},
          ui.h("span", { class: "title", text: "Plate reference" }),
          ui.h("span", { class: "sub", text: referenceUnit === "kg" ? "KG · IWF / IPF colour code" : "LB · manufacturer convention" })));
      details.open = referenceOpen;
      details.addEventListener("toggle", () => { if (details.isConnected) referenceOpen = details.open; });
      const table = ui.h("div", { class: "plate-reference-table", role: "table", "aria-label": "Plate reference" });
      table.append(ui.h("div", { class: "plate-reference-head", role: "row" },
        ui.h("span", { role: "columnheader", text: "Colour" }),
        ui.h("span", { role: "columnheader", text: "Plate" }),
        ui.h("span", { role: "columnheader", text: "Other unit" })));
      for (const plate of PLATE_REFERENCE[referenceUnit]) {
        const token = C.plateColorToken(plate, "bumper");
        const other = plate.unit === "kg"
          ? `${C.trim(C.lbFromKg(plate.value), 2)} lb`
          : `${C.trim(C.kgFromLb(plate.value), 2)} kg`;
        table.append(ui.h("div", { class: "plate-reference-row", role: "row" },
          ui.h("span", { class: "plate-reference-colour", role: "cell" },
            plateBadgeSVG(plate, "bumper"), ui.h("span", { text: token.charAt(0).toUpperCase() + token.slice(1) })),
          ui.h("span", { class: "mono", role: "cell", text: C.plateLabel(plate) }),
          ui.h("span", { class: "mono muted", role: "cell", text: other })));
      }
      details.append(
        ui.seg([{ value: "kg", label: "Kilograms" }, { value: "lb", label: "Pounds" }], referenceUnit,
          (next) => { referenceUnit = next; referenceOpen = true; draw(); }),
        table,
        ui.h("p", { class: "sub", text: PLATE_REFERENCE_NOTE }));
      panel.append(details);
    };

    const drawEquipment = () => {
      const details = ui.h("details", { class: "card equipment-disclosure" },
        ui.h("summary", { text: "Equipment & loading" }));
      const barSelect = ui.h("select", {}, ...C.ALL_BARS.map((option) => ui.h("option", {
        value: C.barId(option), text: C.barLabel(option), selected: C.barId(option) === C.barId(bar),
      })));
      barSelect.addEventListener("change", () => { bar = C.barById(barSelect.value); draw(); });
      details.append(ui.field("Bar", barSelect));
      if (gyms.length > 1) {
        const gymSelect = ui.h("select", {}, ...gyms.map((option) => ui.h("option", {
          value: option.name, text: option.name, selected: gym?.name === option.name,
        })));
        gymSelect.addEventListener("change", () => {
          gym = gyms.find((option) => option.name === gymSelect.value);
          bar = C.barById(gym.defaultBarId); draw();
        });
        details.append(ui.field("Gym", gymSelect));
      }
      details.append(ui.h("div", { class: "field" }, ui.h("span", { text: "Plate type" }),
        ui.seg([{ value: "steel", label: "Steel" }, { value: "bumper", label: "Bumper" }],
          plateStyle, (style) => { plateStyle = style; draw(); })),
      ui.h("p", { class: "sub", text: "Bar units and plate denominations stay independent. The picture always uses the selected rack; mixed-unit conversion appears only in the total." }));
      panel.append(details);
    };

    const drawTarget = () => {
      const input = ui.h("input", { class: "big-num", type: "number", inputmode: "decimal",
        step: "0.5", value: String(targetVal), "aria-label": `Requested target in ${unit}` });
      const unitControl = ui.seg([{ value: "lb", label: "lb" }, { value: "kg", label: "kg" }], unit,
        (nextUnit) => { unit = nextUnit; update(); });
      const target = ui.h("div", { class: "card target-entry" }, ui.field("Requested target", input), unitControl);
      const output = ui.h("div");
      input.addEventListener("input", () => { targetVal = Number.parseFloat(input.value) || 0; update(); });
      panel.append(target, output);

      function update() {
        const targetLb = C.toLb(targetVal, unit);
        const solution = C.solve(targetLb, bar, availablePlates(), 10,
          gym?.collarWeightLb || 0, gym?.loadingPolicy || "closest");
        ui.clear(output);
        const rendered = barbellSVG(solution, "full", plateStyle);
        output.append(ui.h("div", { class: "section-heading" },
          ui.h("div", { class: "section-title", text: "Load on the bar" })),
        barbellStage(rendered, {
          caption: "Mirrored stack · counts are per side", emphasis: "hero",
          onExpand: () => expandedBar(solution, plateStyle, targetLb),
        }),
        loadoutSummary(targetLb, solution));
        const mixed = mixedEquipmentNote(solution); if (mixed) output.append(mixed);
        if (!solution.satisfiesPolicy) output.append(ui.h("div", { class: "warning-panel", text: `No available plate stack satisfies ${C.loadingPolicyLabel(solution.policy).toLowerCase()}; showing the closest load.` }));
        if (solution.isOffTarget) output.append(ui.h("div", { class: "warning-panel", text: `Closest load differs from the request by ${C.trim(Math.abs(solution.deviationLb), 2)} lb / ${C.trim(Math.abs(C.kgFromLb(solution.deviationLb)), 2)} kg.` }));
        output.append(ui.h("div", { class: "section-title", text: "Plates per side" }));
        const list = ui.h("div", { class: "card plate-list" });
        if (!solution.perSide.length) list.append(ui.h("div", { class: "big", text: solution.collarLb ? "Bar + collars" : "Bar only" }));
        for (const count of solution.perSide) list.append(ui.h("div", { class: "row plate-row" },
          plateKey(count.plate, plateStyle), ui.h("strong", { class: "mono", text: `× ${count.count}` })));
        output.append(list);
      }
      update();
    };

    const drawReverse = () => {
      const plates = availablePlates();
      const output = ui.h("div");
      const editor = ui.h("div", { class: "card plate-list" });
      const orderEditor = ui.h("div");
      const recompute = () => {
        const byId = new Map(plates.map((plate) => [C.plateId(plate), plate]));
        const perSide = enteredOrder.map((id) => ({ plate: byId.get(id), count: counts[id] || 0 }))
          .filter((count) => count.plate && count.count > 0);
        const solution = C.enteredPlateSolution(bar, perSide, gym?.collarWeightLb || 0);
        ui.clear(output);
        const rendered = barbellSVG(solution, "full", plateStyle);
        output.append(ui.h("div", { class: "section-heading" },
          ui.h("div", { class: "section-title", text: "On the bar" })),
        barbellStage(rendered, {
          caption: "Entered stack · mirrored exactly", emphasis: "hero",
          onExpand: () => expandedBar(solution, plateStyle),
        }),
        loadoutSummary(null, solution));
        const mixed = mixedEquipmentNote(solution); if (mixed) output.append(mixed);

        ui.clear(orderEditor);
        if (perSide.length) {
          orderEditor.append(ui.h("div", { class: "section-title", text: "Sleeve order · inside to outside" }));
          const orderList = ui.h("div", { class: "card plate-list" });
          perSide.forEach((plateCount, index) => {
            const id = C.plateId(plateCount.plate);
            const move = (offset) => {
              const moved = C.movedVisiblePlateIDs(
                id, offset, enteredOrder, perSide.map((count) => C.plateId(count.plate)),
              );
              enteredOrder.splice(0, enteredOrder.length, ...moved);
              recompute();
            };
            orderList.append(ui.h("div", { class: "row plate-row" },
              ui.h("strong", { class: "mono", text: `${C.plateLabel(plateCount.plate)} × ${plateCount.count}` }),
              ui.h("div", { class: "row-actions" },
                ui.h("button", { class: "btn ghost icon", text: "↑", disabled: index === 0,
                  "aria-label": `Move ${C.plateLabel(plateCount.plate)} inward`, onClick: () => move(-1) }),
                ui.h("button", { class: "btn ghost icon", text: "↓", disabled: index === perSide.length - 1,
                  "aria-label": `Move ${C.plateLabel(plateCount.plate)} outward`, onClick: () => move(1) }))));
          });
          orderEditor.append(orderList);
        }
      };
      panel.append(output, ui.h("div", { class: "section-title", text: "Plates on one side" }), editor, orderEditor);
      for (const plate of plates) {
        const id = C.plateId(plate);
        editor.append(ui.h("div", { class: "row plate-row" }, plateKey(plate, plateStyle),
          ui.stepper(counts[id] || 0, { min: 0, max: 12,
            onChange: (value) => {
              const previous = counts[id] || 0;
              counts[id] = value;
              if (previous === 0 && value > 0 && !enteredOrder.includes(id)) enteredOrder.push(id);
              if (value === 0) {
                const orderIndex = enteredOrder.indexOf(id);
                if (orderIndex >= 0) enteredOrder.splice(orderIndex, 1);
              }
              recompute();
            } })));
      }
      panel.append(ui.h("button", { class: "btn ghost danger wide", text: "Clear entered plates",
        onClick: () => {
          Object.keys(counts).forEach((key) => { counts[key] = 0; });
          enteredOrder.splice(0); draw();
        } }));
      recompute();
    };

    draw();
  } });
}
