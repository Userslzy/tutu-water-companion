const $=id=>document.getElementById(id), pending=new Map();
let state=freshState(), sequence=0, transient=null, transientTimer, toastTimer, undoId=null, ready=false, busy=false;
const timeText=ts=>new Intl.DateTimeFormat('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false}).format(new Date(ts));
function request(action,args={}){return new Promise((resolve,reject)=>{const id=String(++sequence);const timeout=setTimeout(()=>{pending.delete(id);reject(new Error('暂时没有收到回应，请再试一次。'));},action==='notification'?120000:5000);pending.set(id,{resolve,reject,timeout});window.webkit.messageHandlers.tutu.postMessage({id,action,...args});});}
window.desktopReceive=payload=>{
 const prior=state.timer.mode;state=normalize(payload.state);ready=true;
 if(state.timer.mode==='due'&&prior!=='due'){clearTimeout(transientTimer);transient=null;}
 render();$('saveStatus').textContent=payload.storageError||'记录保存在这台 Mac';
 const waiter=pending.get(payload.id);if(waiter){clearTimeout(waiter.timeout);pending.delete(payload.id);if(payload.error)waiter.reject(new Error(payload.error));else waiter.resolve(payload.result);}
};
function toast(message,id=null){clearTimeout(toastTimer);undoId=id;$('toastMessage').textContent=message;$('undoToast').hidden=!id;$('toast').hidden=false;toastTimer=setTimeout(()=>$('toast').hidden=true,id?10000:4000);}
function react(pose,message){clearTimeout(transientTimer);transient={pose,message};renderCompanion();transientTimer=setTimeout(()=>{transient=null;renderCompanion();},4000);}
function renderCompanion(){
 const mode=state.timer.mode;$('stage').dataset.pose=transient?.pose||({paused:'sleep',due:'reminder'}[mode]||'idle');
 const message=transient?.message||{idle:'我在这里陪你，慢慢来就好。',running:'你忙你的，我在这里陪你。',paused:'我也歇一会儿，回来再叫我。',due:'忙了一会儿，记得喝口水呀。'}[mode];
 if($('speech').textContent!==message)$('speech').textContent=message;
 $('bunnyArt').setAttribute('aria-label',{idle:'兔兔坐在小水杯旁',sleep:'兔兔在软垫上打盹',reminder:'兔兔举杯提醒喝水',happy:'兔兔开心地和你碰杯'}[$('stage').dataset.pose]);
 $('statusText').textContent={idle:'等待开始',running:'正在陪伴',paused:'休息一下',due:'喝水时间到'}[mode];$('statusText').className=`status ${mode==='running'?'active':mode==='due'?'due':''}`;
 $('timerLabel').textContent={idle:'准备好了，就开始陪伴吧',running:'距离下次提醒还有',paused:'已暂停 · 留住你的休息时间',due:'喝口水，休息一小会儿'}[mode];
 $('timerButtonText').textContent={idle:'开始陪伴',running:'暂停陪伴',paused:'继续陪伴',due:'暂停陪伴'}[mode];$('timerIcon').setAttribute('href',['running','due'].includes(mode)?'#i-pause':'#i-play');
 $('snooze').disabled=!ready||!['running','due'].includes(mode);$('recordWater').disabled=!ready;$('toggleTimer').disabled=!ready;renderTimer();
}
function renderTimer(){const sec=Math.ceil(remaining(state)/1000);$('countdown').innerHTML=`${String(Math.floor(sec/60)).padStart(2,'0')}<span>:</span>${String(sec%60).padStart(2,'0')}`;$('timerDetail').textContent=state.timer.mode==='running'?`下次提醒 ${timeText(state.timer.dueAt)} · 关闭窗口仍会陪伴`:`每 ${state.settings.interval} 分钟，温柔提醒一次`;}
const drop='<svg class="icon" aria-hidden="true"><use href="#i-drop"/></svg>';
function render(){
 const today=todaysRecords(state);$('todayDate').textContent=new Intl.DateTimeFormat('zh-CN',{month:'long',day:'numeric',weekday:'long'}).format(new Date());$('rabbitName').textContent=state.settings.name;$('dailyCount').textContent=today.length;$('lastDrink').textContent=today.length?timeText(today[0].ts):'还没有记录';$('recordSummary').textContent=today.length?`共 ${today.length} 次记录`:'从第一口开始';
 const list=$('recordList');list.replaceChildren();
 if(!today.length){const empty=document.createElement('div');empty.className='empty-records';empty.innerHTML=`${drop}<p>今天的第一口水，<br>兔兔准备好帮你记下啦。</p>`;list.append(empty);}
 for(const item of today){const row=document.createElement('div');row.className='record-item';row.innerHTML=`<span class="record-drop">${drop}</span><time></time><span class="record-label">喝过水啦</span><button class="undo-item">撤销</button>`;row.querySelector('time').textContent=timeText(item.ts);row.querySelector('time').dateTime=new Date(item.ts).toISOString();row.querySelector('button').setAttribute('aria-label',`撤销 ${timeText(item.ts)} 的喝水记录`);row.querySelector('button').onclick=()=>undo(item.id);list.append(row);}
 const days=new Set(state.records.map(r=>r.day)).size;$('dayCount').textContent=days?`已经一起记录 ${days} 天啦，慢慢来就好。`:'一起照顾自己的日子，从今天开始。';renderCompanion();syncNotification();
}
async function act(action,args={}){try{return await request(action,args);}catch(error){toast(error.message);throw error;}}
async function undo(id){try{await act('undo',{recordId:id});react('idle','没关系，帮你改好啦。');toast('已经撤销这次记录');}catch{}}
$('recordWater').onclick=async()=>{if(busy)return;busy=true;try{const id=await act('record');react('happy','收到，帮你记下来啦！干杯～');toast('这口水，已经帮你记好啦',id);}catch{}finally{busy=false;}};
$('toggleTimer').onclick=async()=>{try{clearTimeout(transientTimer);transient=null;await act(['running','due'].includes(state.timer.mode)?'pause':'start');}catch{}};
$('snooze').onclick=async()=>{try{await act('snooze');react('idle','好呀，10 分钟后再提醒你。');}catch{}};
let hello=0;const lines=['杯子放手边了吗？','慢慢来，我一直陪着你。','碰个小爪，继续加油吧！'];
$('rabbitTouch').onclick=()=>react(state.timer.mode==='paused'?'sleep':'happy',state.timer.mode==='paused'?'呼噜……再陪你歇一小会儿。':lines[hello++%lines.length]);
function syncIntervals(){document.querySelectorAll('[data-interval]').forEach(b=>b.classList.toggle('selected',Number(b.dataset.interval)===Number($('intervalInput').value)));}
function syncNotification(){$('notificationToggle').setAttribute('aria-checked',String(state.settings.notifications));$('notificationStatus').textContent=state.settings.notifications?'已开启通知，也会显示兔兔提醒动画':'可选；未开启也会显示兔兔提醒动画';}
$('openSettings').onclick=()=>{$('nameInput').value=state.settings.name;$('intervalInput').value=state.settings.interval;$('permissionMessage').textContent='';syncIntervals();syncNotification();$('settingsDialog').showModal();};
$('openHelp').onclick=()=>$('helpDialog').showModal();
$('collapseDesktop').onclick=()=>window.webkit.messageHandlers.tutu.postMessage({action:'collapse'});
$('notificationToggle').onclick=async()=>{try{await request('notification',{enabled:!state.settings.notifications});$('permissionMessage').textContent=state.settings.notifications?'系统通知已开启。':'系统通知已关闭。';}catch(error){$('permissionMessage').textContent=error.message;}};
$('settingsForm').onsubmit=async event=>{event.preventDefault();try{await act('configure',{name:$('nameInput').value,interval:Number($('intervalInput').value)});$('settingsDialog').close();toast('设置已保存，就照这个节奏来');}catch{}};
$('intervalInput').oninput=syncIntervals;document.querySelectorAll('[data-interval]').forEach(b=>b.onclick=()=>{$('intervalInput').value=b.dataset.interval;syncIntervals();});
 document.querySelectorAll('[data-close]').forEach(b=>b.onclick=()=>b.closest('dialog').close());
$('undoToast').onclick=()=>{if(undoId)undo(undoId);};$('closeToast').onclick=()=>$('toast').hidden=true;
render();setInterval(renderTimer,1000);window.webkit.messageHandlers.tutu.postMessage({action:'ready'});
