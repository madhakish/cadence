// Signals — per-body-site timeline of set flags + morning check-ins.
import * as ui from "../ui.js";
import * as C from "../core.js";
import { Sessions, Checkins, iso } from "../db.js";
import { BODY_SITES, watchNote, COPY } from "../constants.js";

let site = "Knee";

export async function render(host) {
  const [sessions, checkins] = await Promise.all([Sessions.completed(), Checkins.all()]);
  const root = ui.h("div");
  root.append(ui.seg(BODY_SITES, site, (s) => { site = s; render(host); }));

  const siteCheckins = checkins.filter((c) => c.site === site).sort((a, b) => new Date(b.date) - new Date(a.date));
  if (site === "Knee" && siteCheckins[0] && /flag|pain|swell|off/i.test(siteCheckins[0].response)) {
    root.append(ui.h("div", { class: "card", style: { background: "rgba(255,204,0,0.16)" } },
      ui.h("span", { class: "warn", text: `✋ ${COPY.swelling}` })));
  }

  root.append(ui.h("div", { class: "card" }, ui.h("span", { class: "sub", text: watchNote(site) })));

  // Build timeline: set flags for this site + check-ins
  const items = [];
  for (const s of sessions) {
    for (const e of s.exercises || []) {
      for (const x of e.sets || []) {
        if (x.bodyFlagSite === site) {
          items.push({ date: s.date, title: e.exerciseName, detail: `${ui.fmtWeight(x.weightLb)}×${x.reps}${x.bodyFlagNote ? ` — ${x.bodyFlagNote}` : ""}`, hard: false });
        }
      }
    }
  }
  for (const c of siteCheckins) {
    items.push({ date: c.date, title: `Check-in: ${c.response}`, detail: c.note || "", hard: /flag|pain|swell|off/i.test(c.response) });
  }
  items.sort((a, b) => new Date(b.date) - new Date(a.date));

  root.append(ui.h("div", { class: "section-title", text: "Timeline" }));
  if (!items.length) root.append(ui.h("div", { class: "card muted", text: "No signals logged. Good." }));
  else {
    const card = ui.h("div", { class: "card" });
    for (const it of items) {
      card.append(ui.h("div", { class: "row" },
        ui.h("div", { class: "lead" },
          ui.h("span", { class: "title" + (it.hard ? " hard" : "") , text: (it.hard ? "✋ " : "") + it.title }),
          it.detail ? ui.h("span", { class: "sub", text: it.detail }) : null,
          ui.h("span", { class: "sub", text: ui.fmtLong(it.date) }))));
    }
    root.append(card);
  }

  host.replaceChildren(root);
  document.getElementById("topbar-actions").replaceChildren(
    ui.h("button", { class: "btn sm primary", text: "Check-in", onClick: () => checkIn() }));

  function checkIn() {
    ui.sheet({
      title: site,
      build: (c, api) => {
        const save = async (response) => { await Checkins.add({ date: iso(new Date()), site, response, note: note.value || "" }); api.close(); ui.nav.refresh(); };
        const note = ui.h("input", { type: "text", placeholder: "Note (optional)" });
        c.append(ui.h("button", { class: "btn wide", style: { marginTop: "6px", color: "var(--good)" }, text: `✓ ${COPY.noSwelling}`, onClick: () => save(COPY.noSwelling) }));
        c.append(ui.h("button", { class: "btn wide", style: { marginTop: "8px", color: "var(--hard)" }, text: "✋ Something's off", onClick: () => save("Flagged") }));
        c.append(ui.field("Note", note));
      },
    });
  }
}
