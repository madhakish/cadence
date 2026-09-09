import * as ui from "../ui.js";
import * as C from "../core.js";
import {Programs,Exercises,Sessions} from "../db.js";
import {tfhDraft,tfhSynchronize} from "../tfh.js";
import {tfhPreview} from "./session.js";

export async function tfhEditor(program) {
  const [exercises,sessions] = await Promise.all([Exercises.all(),Sessions.all()]);
  let draft;
  try { draft = tfhDraft(program,exercises,sessions); }
  catch (e) { ui.toast(e.message); return; }
  ui.pushScreen({title:"TFH method",build(body,api) {
    body.append(ui.h("div",{class:"card"},
      ui.h("h2",{text:"Strength for everything else"}),
      ui.h("p",{text:"Three build rotations, then 2–3 light sessions. Leave about 1–3 days between recovery sessions. Review each starting load. Saving starts a new evidence cohort and preserves all history."}),
      ui.h("p",{text:"Loads are in pounds using the stated convention. Timed and conditioning slots keep their authored practice targets."})));
    const recovery = ui.h("div",{class:"card"},ui.h("h3",{text:"Recovery days · choose 2 or 3"}));
    for (const day of [...program.days].sort((a,b)=>a.order-b.order)) {
      const input = ui.h("input",{type:"checkbox",checked:draft.recoveryDayOrders.includes(day.order)});
      input.addEventListener("change",()=>{
        draft.recoveryDayOrders = draft.recoveryDayOrders.filter(d=>d!==day.order);
        if (input.checked) draft.recoveryDayOrders.push(day.order);
        draft.recoveryDayOrders.sort((a,b)=>a-b);
      });
      recovery.append(ui.field(day.name,input));
    }
    body.append(recovery);
    for (const slot of program.days.flatMap(d=>[...(d.lifts || []),...(d.accessories || [])])) {
      const a = draft.anchors[slot.id]; if (!a) continue;
      const card = ui.h("div",{class:"card"},ui.h("h3",{text:slot.exerciseName}),
        ui.h("p",{class:"sub",text:`${a.loadBasis} · ${a.implementCount} implement(s)${a.isPerSide ? " · reps per side" : ""}`}));
      const number = (label,value,change,step=1) => {
        const input = ui.h("input",{type:"number",value,step,min:0});
        input.addEventListener("change",()=>change(Number(input.value)));
        card.append(ui.field(label,input)); return input;
      };
      number("Starting load (lb)",a.weightLb,v=>{a.weightLb=v;},0.5).disabled = a.loadBasis === "bodyweight";
      number("Sets",a.reps.length,v=>{if(Number.isInteger(v)&&v>=1&&v<=10)a.reps=Array(v).fill(a.reps[0]);});
      number("Starting reps",a.reps[0],v=>{a.reps=a.reps.map(()=>v);});
      number("Minimum reps",a.minReps,v=>{a.minReps=v;});
      number("Maximum reps",a.maxReps,v=>{a.maxReps=v;});
      number("Smallest available step (lb)",a.incrementLb,v=>{a.incrementLb=v;},0.5);
      const intent = ui.h("select",{},...["develop","maintain","practice"].map(v=>ui.h("option",{value:v,text:v,selected:a.intent===v})));
      intent.addEventListener("change",()=>{a.intent=intent.value;}); card.append(ui.field("Purpose",intent));
      const bench = ui.h("input",{type:"checkbox",checked:a.benchmarkEnabled});
      bench.addEventListener("change",()=>{a.benchmarkEnabled=bench.checked;});
      card.append(ui.field("Optional R3 final-set benchmark",bench));
      card.append(ui.h("p",{class:"sub",text:"Stop at the technical limit of clean reps. Pain, interruptions, and chosen rep caps are not capacity tests. Skip the benchmark whenever it competes with other training."}));
      body.append(card);
    }
    body.append(ui.h("button",{class:"btn primary wide",text:`Use TFH from cycle ${draft.startCycle}`,onClick:async()=>{
      try {
        if (!C.tfhValidPolicy(draft)) throw new Error("Review the rep ranges, loads, and recovery days.");
        if ((await Sessions.openAll()).some(s=>s.programTag?.programId===(program.uuid || program.id)))
          throw new Error("Finish or discard this program's open session before changing its method.");
        const next = structuredClone(program); next.tfhPolicy = draft;
        for (const d of next.days) for(const s of [...(d.lifts || []),...(d.accessories || [])])
          s.exerciseId = exercises.find(e=>e.name===s.exerciseName)?.id;
        tfhSynchronize(next,await Sessions.all());
        await Programs.save(next); Object.assign(program,next); api.close(); ui.nav.refresh();
      } catch(e) {ui.toast(e.message);}
    }}));
  }});
}

export function tfhPlanRow(program,slot,exercise,sessions,gym,rotation=null) {
  let text;
  try {
    const r = tfhPreview(program,slot,exercise,sessions,gym,rotation);
    text = r ? `TFH · ${ui.fmtWeight(r.plan.weightLb)} · ${r.plan.reps.join("/")} reps${r.plan.benchmark ? " · last set optional AMRAP" : ""}\n${r.plan.reason}`
      : "TFH · authored timed practice";
  } catch(e) {text=e.message;}
  return ui.h("div",{class:"row"},ui.h("div",{class:"lead"},
    ui.h("span",{class:"title",text:slot.exerciseName}),ui.h("span",{class:"sub",style:{whiteSpace:"pre-line"},text})));
}

export function tfhEvidence(session,save) {
  const box = ui.h("details",{class:"card"},ui.h("summary",{text:"TFH evidence · optional"}));
  const context = ui.h("input",{type:"text",maxLength:500,value:session.tfhContext || "",placeholder:"Setup, support, bodyweight…"});
  context.addEventListener("change",async()=>{session.tfhContext=context.value || null;await save();});
  box.append(ui.field("Comparison conditions",context),ui.h("p",{class:"sub",text:"Use the same description only when conditions are comparable. Missing evidence leaves capacity unassessed."}));
  box.append(ui.h("button",{class:"btn ghost",text:"Completed, unflagged work felt clean",onClick:async()=>{
    for (const e of session.exercises) for (const s of e.sets) if(!s.isWarmup && s.status==="completed"
      && !C.setQuality(s.flags) && !(s.flags || []).includes("stopped early") && !s.bodyFlagSite) s.flags=[...(s.flags || []),"clean"];
    await save();ui.toast("Set quality recorded.");
  }}));
  for(const e of session.exercises) for(const s of e.sets) if(s.tfhBenchmark!=null) {
    const stop = ui.h("select",{},...["","technicalLimit","repCap","pain","interrupted","voluntary"].map(v=>ui.h("option",{value:v,text:v || "Not recorded",selected:(s.tfhBenchmark.stopReason || "")===v})));
    const rest = ui.h("input",{type:"number",min:1,max:3600,value:s.tfhBenchmark.restSeconds ?? "",placeholder:"Unknown"});
    box.append(ui.field(`${e.exerciseName} · why you stopped`,stop),ui.field("Actual rest before final set (seconds)",rest));
    box.append(ui.h("button",{class:"btn ghost",text:"Record benchmark context",onClick:async()=>{
      const b={stopReason:stop.value || null,restSeconds:rest.value==="" ? null : Number(rest.value)};
      if(!C.tfhValidBenchmark(b)){ui.toast("Rest must be 1–3600 seconds.");return;}
      s.tfhBenchmark=b;await save();ui.toast("Benchmark context recorded.");
    }}));
  }
  return box;
}
