export const STORAGE_KEY='tutu-water-v1', minute=60000;
export const dayKey=(time=Date.now())=>{const d=new Date(time);return `${d.getFullYear()}-${String(d.getMonth()+1).padStart(2,'0')}-${String(d.getDate()).padStart(2,'0')}`;};
export const freshState=()=>({version:1,settings:{name:'兔兔',interval:45,notifications:false},records:[],timer:{mode:'idle',dueAt:null,remainingMs:45*minute,token:''}});
export const uid=()=>globalThis.crypto?.randomUUID?.()||`${Date.now()}-${Math.random().toString(36).slice(2)}`;
export function normalize(raw){
 const next=freshState();if(!raw||raw.version!==1)return next;
 const s=raw.settings||{};
 if(typeof s.name==='string')next.settings.name=s.name.trim().slice(0,12)||'兔兔';
 if(Number.isInteger(s.interval)&&s.interval>=1&&s.interval<=240)next.settings.interval=s.interval;
 next.settings.notifications=s.notifications===true;
 next.records=Array.isArray(raw.records)?raw.records.filter(r=>r&&typeof r.id==='string'&&Number.isFinite(r.ts)&&r.ts>0&&typeof r.day==='string').map(r=>({...r})):[];
 const t=raw.timer||{};
 if(['idle','paused','running','due'].includes(t.mode))next.timer={mode:t.mode,dueAt:Number.isFinite(t.dueAt)?t.dueAt:null,remainingMs:Number.isFinite(t.remainingMs)?Math.max(0,Math.min(240*minute,t.remainingMs)):next.settings.interval*minute,token:typeof t.token==='string'?t.token:''};
 if(next.timer.mode==='running'&&next.timer.dueAt===null)next.timer.mode='idle';return next;
}
export const todaysRecords=(state,now=Date.now())=>state.records.filter(r=>r.day===dayKey(now)).sort((a,b)=>b.ts-a.ts);
export const remaining=(state,now=Date.now())=>state.timer.mode==='running'?Math.max(0,state.timer.dueAt-now):state.timer.mode==='due'?0:state.timer.remainingMs;
export function start(state,now=Date.now()){const ms=state.timer.mode==='paused'?state.timer.remainingMs:state.settings.interval*minute;state.timer={mode:'running',dueAt:now+ms,remainingMs:ms,token:uid()};}
export function pause(state,now=Date.now()){state.timer={mode:'paused',dueAt:null,remainingMs:remaining(state,now),token:uid()};}
export function snooze(state,now=Date.now()){if(!['running','due'].includes(state.timer.mode))throw new Error('开始陪伴后，才可以稍后提醒。');state.timer={mode:'running',dueAt:now+10*minute,remainingMs:10*minute,token:uid()};}
export function addRecord(state,now=Date.now()){
 const before={...state.timer},id=uid(),active=['running','due'].includes(state.timer.mode);
 state.timer={mode:active?'running':state.timer.mode,dueAt:active?now+state.settings.interval*minute:null,remainingMs:state.settings.interval*minute,token:id};
 state.records.push({id,ts:now,day:dayKey(now),timerBefore:before});return id;
}
export function undoRecord(state,id){const item=state.records.find(r=>r.id===id);if(!item)throw new Error('这条记录已经撤销了。');if(state.timer.token===id&&item.timerBefore)state.timer={...item.timerBefore};state.records=state.records.filter(r=>r.id!==id);}
export function configure(state,{name,interval},now=Date.now()){
 if(!Number.isInteger(interval)||interval<1||interval>240)throw new Error('请填写 1–240 之间的整数分钟。');
 state.settings={...state.settings,name:(name||'兔兔').trim().slice(0,12)||'兔兔',interval};
 const active=['running','due'].includes(state.timer.mode);state.timer={mode:active?'running':state.timer.mode,remainingMs:interval*minute,dueAt:active?now+interval*minute:null,token:uid()};
}
export function markDue(state,now=Date.now()){if(state.timer.mode!=='running'||state.timer.dueAt>now)return false;state.timer.mode='due';state.timer.remainingMs=0;return true;}
