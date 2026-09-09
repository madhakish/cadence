import assert from "node:assert/strict";
import "fake-indexeddb/auto";
const old=await new Promise((resolve,reject)=>{
  const r=indexedDB.open("cadence",8);
  r.onupgradeneeded=()=>{
    r.result.createObjectStore("programs",{keyPath:"id",autoIncrement:true});
    r.result.createObjectStore("sessions",{keyPath:"id",autoIncrement:true});
  };
  r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);
});
const manual={order:0,weightLb:55,reps:4,plannedWeightLb:60,plannedReps:5,status:"completed",flags:["grindy"],loadBasis:"perImplement",implementCount:2};
await new Promise((resolve,reject)=>{
  const tx=old.transaction(["programs","sessions"],"readwrite");
  tx.objectStore("programs").put({id:1,uuid:crypto.randomUUID(),name:"V8 fixture",cycleNumber:7,currentWeek:3,nextDayIndex:0,days:[]});
  tx.objectStore("sessions").put({id:1,date:"2026-07-01T00:00:00Z",isCompleted:true,exercises:[{order:0,exerciseName:"Fixture",exerciseId:crypto.randomUUID(),sets:[manual]}]});
  tx.oncomplete=resolve;tx.onerror=()=>reject(tx.error);
});old.close();
const db=await import("../app/js/db.js");
const p=(await db.Programs.all())[0],s=await db.Sessions.get(1);
assert.equal(p.tfhPolicy,null);assert.equal(p.cycleNumber,7);assert.equal(p.currentWeek,3);
assert.equal(s.tfhPolicyId,null);assert.equal(s.exercises[0].tfhAnchor,undefined);
const set=s.exercises[0].sets[0];
for(const [k,v]of Object.entries(manual))assert.deepEqual(set[k],v);
const raw=await db.runAll(["sessions"],"readonly",os=>new Promise((resolve,reject)=>{
  const r=os("sessions").get(1);r.onsuccess=()=>resolve(r.result);r.onerror=()=>reject(r.error);
}));
assert.equal(raw.tfhPolicyId,null,"the actual V8 store was upgraded, not only normalized on read");
console.log("V8 → V9 migration preserves manual work and never invents TFH evidence");
