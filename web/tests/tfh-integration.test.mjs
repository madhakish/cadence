import assert from "node:assert/strict";
import "fake-indexeddb/auto";
import {JSDOM} from "jsdom";
import * as C from "../app/js/core.js";
const dom = new JSDOM('<header id="topbar"><h1 id="screen-title"></h1><div id="topbar-actions"></div></header><main id="view"></main><button id="fab"></button><nav id="tabbar"></nav><div id="overlays"></div><div id="toast"></div>',{url:"http://localhost/cadence/app/"});
Object.assign(globalThis,{window:dom.window,document:dom.window.document,Node:dom.window.Node,localStorage:dom.window.localStorage});
const db = await import("../app/js/db.js");
const S = await import("../app/js/views/session.js");
const T = await import("../app/js/tfh.js");
const UI = await import("../app/js/views/tfh.js");
await db.ensureSeeded();
const exs = await db.Exercises.all();
const names = ["Incline DB Press","Back Squat"];
const program = {uuid:crypto.randomUUID(),name:"TFH integration fixture",templateId:"upper-lower-4",
  focus:"strength",equipmentPolicy:"any",cycleNumber:1,currentWeek:1,nextDayIndex:0,roundingLb:5,
  isActive:false,days:names.map((name,order)=>({name:`Day ${order}`,order,trainingIntent:"general",
    lifts:[{id:crypto.randomUUID(),exerciseName:name,exerciseId:exs.find(e=>e.name===name).id,role:"main",order:0,
      baseWeightLb:order ? 150 : 60,estimatedMaxLb:0,doubleProgressionSets:3,minimumReps:3,maximumReps:5,currentReps:3}],accessories:[]}))};
program.tfhPolicy=T.tfhDraft(program,exs,[]);
program.tfhPolicy.anchors[program.days[0].lifts[0].id].benchmarkEnabled=true;
program.id=await db.Programs.save(program);
let p=await db.Programs.byStableId(program.uuid);
assert.deepEqual(T.tfhCurrentPosition(p,[]),{cycle:1,rotation:1,dayOrder:0,completedCycles:[]});
const firstID=await S.createSessionFromProgramDay(p,p.days[0]);
assert.equal(await S.createSessionFromProgramDay(p,p.days[0]),firstID,"resume the one open TFH session");
const first=await db.Sessions.get(firstID), e=first.exercises[0];
assert.equal(e.exerciseId,program.days[0].lifts[0].exerciseId);
assert.equal(e.tfhAnchor.id,p.tfhPolicy.anchors[e.programSlotId].id);
assert.deepEqual(e.sets.filter(s=>!s.isWarmup).map(s=>s.reps),[3,3,3]);
assert.ok(e.sets.every(s=>s.loadBasis==="perImplement" && s.implementCount===2));
const bank = async s => {
  for(const e of s.exercises)for(const x of e.sets){x.status="completed";x.flags=["clean"];}
  s.tfhContext="same setup and preceding work";
  await S.completeSession(s);
};
await bank(first);
p=await db.Programs.byStableId(program.uuid);
assert.equal(p.nextDayIndex,1,"production banking advances the day");
let history=await db.Sessions.all();
let next=T.tfhPrescription(p,e.programSlotId,history,2);
assert.equal(next.plan.weightLb,60);
assert.deepEqual(next.plan.reps,[4,3,3],"one total rep, no volume collapse or forced DB increment");
// A correction must change the next prescription without a persisted stall grade.
const corrected=await db.Sessions.get(firstID);
const last=corrected.exercises[0].sets.filter(s=>!s.isWarmup).at(-1);
await db.Sessions.applyCorrections(corrected,[{set:last,correction:{reps:2}}]);
next=T.tfhPrescription(p,e.programSlotId,await db.Sessions.all(),2);
assert.deepEqual(next.plan.reps,[3,3,3]);
assert.equal(T.tfhCoachingReport(p,await db.Sessions.all()).recommendations[0].ruleID,"tfh.learning");
await db.Sessions.applyCorrections(corrected,[{set:last,correction:{reps:3}}]);
// Complete all build days using the actual builder and completion transaction.
while(true){
  p=await db.Programs.byStableId(program.uuid);
  if(p.currentWeek===4)break;
  const id=await S.createSessionFromProgramDay(p,p.days.find(d=>d.order===p.nextDayIndex));
  const s=await db.Sessions.get(id);
  if(s.programTag.week===3 && s.programTag.dayIndex===0){
    const benchmark=s.exercises[0].sets.at(-1);
    assert.deepEqual(benchmark.tfhBenchmark,{});
    benchmark.tfhBenchmark={stopReason:"technicalLimit",restSeconds:180};
  }
  await bank(s);
}
const before=p.cycleNumber;
await S.reconcileRecoveryBridge(p,null,new Date("2035-01-01"));
assert.equal(p.currentWeek,4,"time cannot complete TFH recovery");
for(let i=0;i<2;i++){
  const id=await S.createSessionFromProgramDay(p,p.days.find(d=>d.order===p.nextDayIndex));
  const s=await db.Sessions.get(id),work=s.exercises[0].sets.filter(x=>!x.isWarmup);
  assert.equal(work.length,2);assert.ok(work.every(x=>x.tfhBenchmark==null));
  await bank(s);p=await db.Programs.byStableId(program.uuid);
}
assert.equal(p.cycleNumber,before+1);assert.equal(p.currentWeek,1);
assert.deepEqual(T.tfhCurrentPosition(p,await db.Sessions.all()).completedCycles,[1]);
const bundle=await db.exportBundle();
assert.equal(bundle.schemaVersion,14);db.validateBackup(bundle);
await db.importBundle(bundle,{createCheckpoint:false});
const restored=await db.Programs.byStableId(program.uuid);
assert.deepEqual(restored.tfhPolicy,p.tfhPolicy);
const after=await db.exportBundle();
const tfhSessions=b=>b.sessions.filter(s=>s.tfhPolicyId===p.tfhPolicy.id);
assert.deepEqual(tfhSessions(after),tfhSessions(bundle),"prescriptions, identities and optional benchmark evidence round-trip");
const invalid=structuredClone(bundle);
invalid.programs.find(x=>x.id===program.uuid).tfhPolicy.anchors[e.programSlotId].weightLb=-1;
await assert.rejects(()=>db.importBundle(invalid,{createCheckpoint:false}));
assert.deepEqual((await db.Programs.byStableId(program.uuid)).tfhPolicy,p.tfhPolicy,"bad TFH backup changes nothing");
const row=UI.tfhPlanRow(restored,restored.days[0].lifts[0],exs.find(x=>x.name===names[0]),await db.Sessions.all(),await db.Gyms.default());
assert.match(row.textContent,/4\/3\/3 reps/);
assert.doesNotMatch(row.textContent,/3×4/);
// Deletion fills the missing schedule position, not another manufactured cycle.
const toDelete=(await db.Sessions.all()).find(s=>s.tfhPolicyId===p.tfhPolicy.id && s.programTag.week===4);
await db.Sessions.del(toDelete.id);
assert.equal(T.tfhCurrentPosition(restored,await db.Sessions.all()).rotation,4);
console.log("TFH live builder, correction, recovery, coaching and backup integration passed");
