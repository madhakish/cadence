// Whole-program overview. Editing deliberately delegates to the existing
// editor so one engine owns all mutations on both platforms.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { Programs, Exercises } from "../db.js";
import { openAddProgramSheet, programEditor } from "./settings.js";

const ordered = (items = []) => [...items].sort((a, b) => (a.order ?? 0) - (b.order ?? 0)
  || String(a.exerciseName || a.name || "").localeCompare(String(b.exerciseName || b.name || "")));

export async function render(host) {
  const [programs, exercises] = await Promise.all([Programs.all(), Exercises.all()]);
  const exByName = new Map(exercises.map((exercise) => [exercise.name, exercise]));
  const root = ui.h("div");
  const sorted = [...programs].sort((a, b) => Number(b.isActive) - Number(a.isActive));

  if (!sorted.length) root.append(ui.empty("📋", "Start blank, use a template, or import a Cadence program file."));
  for (const program of sorted) {
    root.append(ui.h("div", { class: "section-title" },
      ui.h("span", { text: program.name }),
      ui.h("span", { class: "sub", text: `${program.focus} · Cycle ${program.cycleNumber}${program.isActive ? " · active" : ""}` })));
    for (const day of ordered(program.days)) {
      const card = ui.h("button", { class: "card wide program-day-card", onClick: () => programEditor(program),
        // Web has no day-scoped editor entry, so the label promises what the
        // click actually does — the program editor — rather than a day editor
        // screen readers would then fail to find.
        ariaLabel: `${day.name}, opens the program editor` },
      ui.h("div", { class: "row" }, ui.h("span", { class: "title", text: day.name }),
        day.order === program.nextDayIndex ? ui.h("span", { class: "pill accent", text: "Next" }) : null));
      for (const lift of ordered(day.lifts)) {
        const exercise = exByName.get(lift.exerciseName);
        const plan = C.programPlanFor(
          { cycleNumber: program.cycleNumber, baseWeightLb: lift.baseWeightLb, nextPhase: program.currentWeek, incrementLb: 0 },
          program.roundingLb, exercise?.type, exercise?.movementGroup, lift.role, program.focus,
          lift.prescription || "automatic", lift,
          C.volumeIncrementSets(lift.stallCount ?? 0, program.maximumAddedSetsPerRotation ?? 6),
        );
        card.append(ui.h("div", { class: "row program-slot" },
          ui.h("div", { class: "lead" },
            ui.h("span", { class: "title", text: lift.exerciseName }),
            ui.h("span", { class: "sub", text: C.slotBadge(lift.role, lift.prescription, exercise?.movementGroup, program.focus) }),
            ui.h("span", { class: "sub mono", text: `Base ${ui.fmtWeight(lift.baseWeightLb)} · next ${ui.fmtWeight(plan.weightLb)} · ${plan.sets}×${plan.reps}` }))));
      }
      const accessories = ordered(day.accessories);
      const stalled = accessories.some((item) => (item.currentReps || 0) >= (item.maxReps || Infinity)
        && !(item.incrementLb > 0) && !(item.durationStepSeconds > 0));
      card.append(ui.h("div", { class: "row", style: { borderBottom: "0" } },
        ui.h("span", { class: "sub", text: `${accessories.length} accessories` }),
        stalled ? ui.h("span", { class: "pill warn", text: "Needs progression" }) : null));
      root.append(card);
    }
  }
  root.append(ui.h("button", { class: "btn primary wide", text: "+ Add program", onClick: () => openAddProgramSheet(programs) }));
  host.replaceChildren(root);
}
