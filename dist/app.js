import {STORAGE_KEY,normalize,freshState,todaysRecords,remaining,start,pause,snooze,addRecord,undoRecord,configure,markDue,dayKey} from './model.js';
const $=id=>document.getElementById(id);
let state=freshState(),storageOK=true,transient=null,transientTimer,toastTimer,undoId=null,ticking=false,lastDay=dayKey();
const timeText=ts=>new Intl.DateTimeFormat('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(ts));
function readSaved(){try{const raw=localStorage.getItem(STORAGE_KEY);if(raw)state=normalize(JSON.parse(raw));}catch{storageOK=false;}}
function persist(){try{localStorage.setItem(STORAGE_KEY,JSON.stringify(state));storageOK=true;}catch{storageOK=false;}}
async function change(action){const execute=()=>{if(storageOK)readSaved();const result=action(state);persist();render();return result;};return navigator.locks?.request?navigator.locks.request('tutu-water-state',execute):execute();}
function toast(message,id=null){clearTimeout(toastTimer);undoId=id;$('toastMessage').textContent=message;$('undoToast').hidden=!id;$('toast').hidden=false;toastTimer=setTimeout(()=>$('toast').hidden=true,id?10000:4500);}
function react(pose,message,duration=4200){clearTimeout(transientTimer);transient={pose,message};renderCompanion();transientTimer=setTimeout(()=>{transient=null;renderCompanion();},duration);}
function renderCompanion(){
 const mode=state.timer.mode,poses={idle:'idle',running:'idle',paused:'sleep',due:'reminder'},messages={idle:'我在这里陪你，慢慢来就好。',running:'你忙你的，我在这里陪你。',paused:'我也歇一会儿，回来再叫我。',due:'忙了一会儿，记得喝口水呀。'};
 $('stage').dataset.pose=transient?.pose||poses[mode];
 const speech=transient?.message||messages[mode];if($('speech').textContent!==speech)$('speech').textContent=speech;
 $('bunnyArt').setAttribute('aria-label',{idle:'兔兔坐在小水杯旁，静静陪着你',reminder:'兔兔抱起杯子，提醒你喝水',happy:'兔兔开心地举杯，和你碰杯',sleep:'兔兔趴在软垫上打盹'}[$('stage').dataset.pose]);
 $('statusText').textContent={idle:'等待开始',running:'正在陪伴',paused:'休息一下',due:'喝水时间到'}[mode];$('statusText').className=`status ${mode==='running'?'active':mode==='due'?'due':''}`;
 $('timerLabel').textContent={idle:'准备好了，就开始陪伴吧',running:'距离下次提醒还有',paused:'已暂停 · 留住你的休息时间',due:'喝口水，休息一小会儿'}[mode];
 $('timerButtonText').textContent={idle:'开始陪伴',running:'暂停陪伴',paused:'继续陪伴',due:'暂停陪伴'}[mode];
 $('timerIcon').setAttribute('href',['running','due'].includes(mode)?'#i-pause':'#i-play');$('snooze').disabled=!['running','due'].includes(mode);renderTimer();
}
function renderTimer(){
 const secs=Math.ceil(remaining(state)/1000),mins=Math.floor(secs/60),seconds=secs%60,content=`${String(mins).padStart(2,'0')}<span>:</span>${String(seconds).padStart(2,'0')}`;
 if($('countdown').innerHTML!==content)$('countdown').innerHTML=content;
 $('timerDetail').textContent=state.timer.mode==='running'?`下次提醒 ${timeText(state.timer.dueAt)} · 每 ${state.settings.interval} 分钟`:state.timer.mode==='due'?'喝过水后，点一下就记好啦':`每 ${state.settings.interval} 分钟，温柔提醒一次`;
 document.title=state.timer.mode==='due'?'该喝水啦 · 兔兔喝水':'兔兔喝水 · 你的小小喝水搭子';
}
const drop='<svg class="icon" aria-hidden="true"><use href="#i-drop"/></svg>';
function render(){
 const today=todaysRecords(state);
 $('todayDate').textContent=new Intl.DateTimeFormat('zh-CN',{month:'long',day:'numeric',weekday:'long'}).format(new Date());$('rabbitName').textContent=state.settings.name;$('dailyCount').textContent=today.length;
 $('lastDrink').textContent=today.length?timeText(today[0].ts):'还没有记录';$('countCaption').textContent=today.length?'每一口，都是对自己的照顾。':'喝过水后点一下，兔兔帮你记下来。';$('recordSummary').textContent=today.length?`共 ${today.length} 次记录`:'从第一口开始';
 const list=$('recordList');list.replaceChildren();
 if(!today.length){const empty=document.createElement('div');empty.className='empty-records';empty.innerHTML=`${drop}<p>今天的第一口水，<br>兔兔准备好帮你记下啦。</p>`;list.append(empty);}
 for(const record of today){const row=document.createElement('div');row.className='record-item';row.innerHTML=`<span class="record-drop">${drop}</span><time></time><span class="record-label">喝过水啦</span><button class="undo-item">撤销</button>`;row.querySelector('time').textContent=timeText(record.ts);row.querySelector('time').dateTime=new Date(record.ts).toISOString();const undo=row.querySelector('button');undo.setAttribute('aria-label',`撤销 ${timeText(record.ts)} 的喝水记录`);undo.addEventListener('click',()=>removeRecord(record.id));list.append(row);}
 const days=new Set(state.records.map(r=>r.day)).size;$('dayCount').textContent=days?`已经一起记录 ${days} 天啦，慢慢来就好。`:'一起照顾自己的日子，从今天开始。';$('saveStatus').textContent=storageOK?'记录只保存在当前浏览器':'暂时无法保存 · 请保持页面打开';renderCompanion();
}
async function recordWater(){const id=await change(s=>addRecord(s));react('happy','收到，帮你记下来啦！干杯～');toast(storageOK?'这口水，已经帮你记好啦':'已记录，但浏览器暂时无法保存',id);return summary();}
async function removeRecord(id){try{await change(s=>undoRecord(s,id));toast('已经撤销这次记录');react('idle','没关系，帮你改好啦。');}catch(e){toast(e.message);}return summary();}
async function controlTimer(action){
 clearTimeout(transientTimer);transient=null;
 await change(s=>{if(action==='start'){if(!['running','due'].includes(s.timer.mode))start(s);}else if(action==='pause'){if(['running','due'].includes(s.timer.mode))pause(s);}else if(action==='snooze')snooze(s);else throw new Error('不支持这个操作。');});
 if(action==='start')react('idle','好呀，接下来我陪着你。');if(action==='snooze')react('idle','好呀，10 分钟后再提醒你。');return summary();
}
function summary(){return{name:state.settings.name,intervalMinutes:state.settings.interval,mode:state.timer.mode,remainingSeconds:Math.ceil(remaining(state)/1000),nextReminderAt:state.timer.mode==='running'?new Date(state.timer.dueAt).toISOString():null,todayRecords:todaysRecords(state).map(({id,ts})=>({id,time:new Date(ts).toISOString()})),companionDays:new Set(state.records.map(r=>r.day)).size};}
async function tick(){
 renderTimer();if(dayKey()!==lastDay){lastDay=dayKey();render();react('happy','新的一天，也一起照顾好自己。');}
 if(ticking||state.timer.mode!=='running'||state.timer.dueAt>Date.now())return;ticking=true;
 try{const due=await change(s=>markDue(s));if(due){clearTimeout(transientTimer);transient=null;renderCompanion();if(state.settings.notifications&&'Notification'in window&&Notification.permission==='granted'){try{const notification=new Notification(`${state.settings.name}提醒你喝水`,{body:'忙了一会儿，记得喝口水呀。喝完回来点一下，兔兔帮你记下来。',tag:'tutu-water-reminder',silent:true});notification.onclick=()=>{window.focus();notification.close();};}catch{toast('喝水时间到啦！这个浏览器暂时无法显示桌面通知。');}}}}finally{ticking=false;}
}
function showSettings(){$('nameInput').value=state.settings.name;$('intervalInput').value=state.settings.interval;$('permissionMessage').textContent='';syncInterval();syncNotification();$('settingsDialog').showModal();}
function syncInterval(){document.querySelectorAll('[data-interval]').forEach(b=>b.classList.toggle('selected',+b.dataset.interval===+$('intervalInput').value));}
function syncNotification(){const supported='Notification'in window&&window.isSecureContext,active=supported&&Notification.permission==='granted'&&state.settings.notifications;$('notificationToggle').setAttribute('aria-checked',String(active));$('notificationToggle').disabled=!supported;$('notificationStatus').textContent=!supported?'当前浏览器不支持，页面内仍会提醒':Notification.permission==='denied'?'通知已被浏览器关闭':active?'已开启，提醒会显示在桌面':'切换窗口时，也能收到提醒';}
$('recordWater').addEventListener('click',recordWater);$('toggleTimer').addEventListener('click',()=>controlTimer(['running','due'].includes(state.timer.mode)?'pause':'start'));$('snooze').addEventListener('click',()=>controlTimer('snooze'));
let greetingIndex=0;const greetings=['杯子放手边了吗？','慢慢来，我一直陪着你。','今天也有在好好照顾自己呀。','碰个小爪，继续加油吧！'];
$('rabbitTouch').addEventListener('click',()=>react(state.timer.mode==='paused'?'sleep':'happy',state.timer.mode==='paused'?'呼噜……再陪你歇一小会儿。':greetings[greetingIndex++%greetings.length]));
$('openSettings').addEventListener('click',showSettings);$('openHelp').addEventListener('click',()=>$('helpDialog').showModal());
 document.querySelectorAll('[data-close]').forEach(b=>b.addEventListener('click',()=>b.closest('dialog').close()));
 document.querySelectorAll('dialog').forEach(d=>d.addEventListener('click',e=>{if(e.target===d){const r=d.getBoundingClientRect();if(e.clientX<r.left||e.clientX>r.right||e.clientY<r.top||e.clientY>r.bottom)d.close();}}));
 document.querySelectorAll('[data-interval]').forEach(b=>b.addEventListener('click',()=>{$('intervalInput').value=b.dataset.interval;syncInterval();}));
$('intervalInput').addEventListener('input',()=>{$('intervalInput').setCustomValidity('');syncInterval();});
$('settingsForm').addEventListener('submit',async e=>{e.preventDefault();try{await change(s=>configure(s,{name:$('nameInput').value,interval:Number($('intervalInput').value)}));$('settingsDialog').close();toast('设置已保存，就照这个节奏来');}catch(error){$('intervalInput').setCustomValidity(error.message);$('intervalInput').reportValidity();}});
$('notificationToggle').addEventListener('click',async()=>{
 if(!('Notification'in window))return;
 if(state.settings.notifications&&Notification.permission==='granted'){await change(s=>s.settings.notifications=false);syncNotification();return;}
 if(Notification.permission==='denied'){$('permissionMessage').textContent='请在浏览器的网站设置中允许通知，然后再回来开启。';return;}
 try{const permission=await Notification.requestPermission();await change(s=>s.settings.notifications=permission==='granted');$('permissionMessage').textContent=permission==='granted'?'桌面通知已开启，请保持网页打开。':'暂未开启，页面内的喝水提醒仍然可用。';}catch{$('permissionMessage').textContent='这个浏览器无法开启通知，页面内仍会提醒。';}syncNotification();
});
$('undoToast').addEventListener('click',()=>{if(undoId)removeRecord(undoId);});$('closeToast').addEventListener('click',()=>$('toast').hidden=true);
window.addEventListener('storage',e=>{if(e.key===STORAGE_KEY){readSaved();render();tick();}});document.addEventListener('visibilitychange',()=>{if(!document.hidden){readSaved();render();tick();}});window.addEventListener('pageshow',()=>tick());
readSaved();render();tick();if(!storageOK)toast('浏览器暂时无法保存记录，本次页面内仍可使用');else if(state.records.length&&todaysRecords(state).length===0)react('happy','今天也一起照顾好自己。');setInterval(tick,1000);
const context=document.modelContext;
if(context?.registerTool){const lifecycle=new AbortController(),empty={type:'object',properties:{},additionalProperties:false};const tools=[
 {name:'get_hydration_status',title:'查看喝水状态',description:'Read today’s hydration records and reminder status in this browser.',inputSchema:empty,annotations:{readOnlyHint:true,untrustedContentHint:true},execute:()=>summary()},
 {name:'record_water',title:'记录一次喝水',description:'Record one drink now, update the visible journal, and restart an active timer. Use only when the user says they drank water.',inputSchema:empty,annotations:{readOnlyHint:false},execute:recordWater},
 {name:'control_water_reminder',title:'控制喝水提醒',description:'Start or resume, pause, or snooze the reminder for 10 minutes. Snoozing requires an active reminder.',inputSchema:{type:'object',properties:{action:{type:'string',enum:['start','pause','snooze']}},required:['action'],additionalProperties:false},annotations:{readOnlyHint:false},execute:input=>{if(!input||!['start','pause','snooze'].includes(input.action))throw new Error('action 必须为 start、pause 或 snooze');return controlTimer(input.action);}}
 ];for(const tool of tools){try{Promise.resolve(context.registerTool(tool,{signal:lifecycle.signal})).catch(()=>{});}catch{}}
}
