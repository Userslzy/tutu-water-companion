import Foundation
func check(_ pass:@autoclosure()->Bool,_ message:String){if !pass(){fatalError(message)}}
let now=Date().timeIntervalSince1970*1000
var state=WaterState()
try state.apply("start",now:now)
try state.apply("pause",now:now+120_000)
check(state.timer.remainingMs==43*60_000,"Pause retains time")
try state.apply("start",now:now+600_000)
let deadline=state.timer.dueAt!
let id=try state.apply("record",now:now+660_000)!
check(state.timer.dueAt==now+660_000+45*60_000,"Record restarts timer")
try state.apply("undo",args:["recordId":id],now:now+670_000)
check(state.timer.dueAt==deadline && state.records.isEmpty,"Undo restores prior deadline")
check(state.advance(deadline+1),"Remind at deadline")
check(!state.advance(deadline+2),"Only one due event per cycle")
try state.apply("snooze",now:deadline+3)
check(state.timer.dueAt==deadline+600_003,"Snooze ten minutes")
try state.apply("pause",now:deadline+60_003)
let record=try state.apply("record",now:deadline+61_003)!
check(state.timer.mode=="paused","Drinking while paused does not resume")
try state.apply("configure",args:["name":"小白","interval":30],now:deadline+62_003)
try state.apply("undo",args:["recordId":record])
check(state.timer.remainingMs==30*60_000 && state.settings.name=="小白","Undo cannot overwrite newer settings")
do{try state.apply("configure",args:["interval":0]);fatalError("Invalid interval accepted")}catch{}
do{try state.apply("snooze");fatalError("Inactive snooze accepted")}catch{}
let temp=FileManager.default.temporaryDirectory.appendingPathComponent("tutu-model-test-\(UUID().uuidString)")
let store=StateStore(directory:temp);store.state=state;store.save()
let reloaded=StateStore(directory:temp)
check(reloaded.state.timer==state.timer && reloaded.state.settings.name=="小白","State persisted independently of webview")
let calendar=Calendar.current, date=Date(timeIntervalSince1970:now/1000), dayStart=calendar.startOfDay(for:date).timeIntervalSince1970*1000
var midnight=WaterState();try midnight.apply("record",now:dayStart-1000);try midnight.apply("record",now:dayStart+1000)
check(Set(midnight.records.map{$0.day}).count==2,"Midnight keeps both days")
print("PASS: pause/resume, record/undo, due-once, snooze, paused record, validation, persistence, midnight")

let still=ReminderMotion.sample(elapsed:0,reducedMotion:false)
let hop=ReminderMotion.sample(elapsed:0.4,reducedMotion:false)
check(hop.lift-still.lift>=12 && abs(hop.rotation)>=3,"Reminder must visibly hop and rock")
check(ReminderMotion.sample(elapsed:6.4,reducedMotion:false).lift>12,"Reminder repeats until handled")
let accessible=ReminderMotion.sample(elapsed:0.4,reducedMotion:true)
check(accessible.lift==0 && accessible.rotation==0 && accessible.scale==1 && accessible.haloOpacity>0,"Reduced motion retains static visual emphasis")
print("PASS: visible reminder movement, repeat cycle, reduced-motion fallback")
