import AppKit
import WebKit
import UserNotifications

final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
final class PetView: NSView {
    weak var owner: AppDelegate?
    var sprites: [NSImage] = []
    var pose = 0
    var message = "点我展开 · 拖动可挪窝"
    var mouseStart = NSPoint.zero, frameStart = NSPoint.zero
    var dragged = false
    var breath: CGFloat = 0
    var reminderStartedAt = ProcessInfo.processInfo.systemUptime
    var reminderElapsedOverride: Double?
    var isReminder = false {
        didSet {
            if isReminder != oldValue {reminderStartedAt=ProcessInfo.processInfo.systemUptime}
            needsDisplay=true
        }
    }
    var reminderMotion: ReminderMotion {
        ReminderMotion.sample(elapsed:reminderElapsedOverride ?? (ProcessInfo.processInfo.systemUptime-reminderStartedAt),reducedMotion:NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }
    override init(frame: NSRect) {
        super.init(frame: frame)
        setAccessibilityElement(true); setAccessibilityRole(.button); setAccessibilityLabel("桌面兔兔，点击展开喝水页面，可拖动")
        if let url = Bundle.main.url(forResource: "bunny-transparent", withExtension: "png"), let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            let w = cg.width / 2, h = cg.height / 2
            for row in 0..<2 { for col in 0..<2 {
                if let frame = cg.cropping(to: CGRect(x: col*w, y: row*h, width: w, height: h)) { sprites.append(NSImage(cgImage: frame, size: NSSize(width: w,height:h))) }
            }}
        }
        toolTip = "单击展开 · 拖动挪位置 · 右键更多操作"
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill(); dirtyRect.fill(using: .copy)
        let motion=reminderMotion
        if isReminder {
            NSColor(calibratedRed:0.94,green:0.70,blue:0.28,alpha:motion.haloOpacity).setFill()
            NSBezierPath(ovalIn:NSRect(x:22,y:12,width:176,height:34)).fill()
        }
        if !sprites.isEmpty {
            let lift:CGFloat=isReminder ? motion.lift : (NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : sin(breath)*1.5)
            NSGraphicsContext.saveGraphicsState()
            let transform=NSAffineTransform()
            transform.translateX(by:110,yBy:100+lift)
            if isReminder {transform.rotate(byDegrees:motion.rotation);transform.scale(by:motion.scale)}
            transform.concat()
            sprites[min(pose,sprites.count-1)].draw(in:NSRect(x:-90,y:-90,width:180,height:180),from:.zero,operation:.sourceOver,fraction:1,respectFlipped:false,hints:[.interpolation:NSImageInterpolation.high])
            NSGraphicsContext.restoreGraphicsState()
        }
        if !message.isEmpty {
            let rect=NSRect(x:4,y:bounds.maxY-49,width:212,height:43)
            (isReminder ? NSColor(calibratedRed:1,green:0.93,blue:0.74,alpha:0.98) : NSColor(calibratedRed:0.98,green:0.98,blue:0.95,alpha:0.97)).setFill()
            let bubble=NSBezierPath(roundedRect:rect,xRadius:14,yRadius:14);bubble.fill()
            if isReminder {NSColor(calibratedRed:0.78,green:0.54,blue:0.16,alpha:0.8).setStroke();bubble.lineWidth=1.2;bubble.stroke()}
            let style=NSMutableParagraphStyle();style.alignment = .center;style.lineBreakMode = .byWordWrapping
            (message as NSString).draw(in:rect.insetBy(dx:8,dy:5),withAttributes:[.font:NSFont.systemFont(ofSize:isReminder ? 13 : 12,weight:isReminder ? .semibold : .regular),.foregroundColor:NSColor(calibratedRed:0.25,green:0.36,blue:0.29,alpha:1),.paragraphStyle:style])
        }
    }
    override func acceptsFirstMouse(for event:NSEvent?) -> Bool {true}
    override func mouseDown(with event:NSEvent) { mouseStart=NSEvent.mouseLocation;frameStart=window?.frame.origin ?? .zero;dragged=false }
    override func mouseDragged(with event:NSEvent) {
        let p=NSEvent.mouseLocation, dx=p.x-mouseStart.x,dy=p.y-mouseStart.y
        if hypot(dx,dy)>4 {dragged=true}
        if dragged {window?.setFrameOrigin(NSPoint(x:frameStart.x+dx,y:frameStart.y+dy))}
    }
    override func mouseUp(with event:NSEvent) { if dragged {owner?.savePosition()} else {owner?.showMain()} }
    override func rightMouseDown(with event:NSEvent) {if let menu=owner?.makeMenu(){NSMenu.popUpContextMenu(menu,with:event,for:self)}}
    override func accessibilityPerformPress() -> Bool {owner?.showMain();return true}
}
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandler, WKNavigationDelegate, UNUserNotificationCenterDelegate {
    var store:StateStore!
    var pet:FloatingPanel!, petView:PetView!, main:NSWindow!, web:WKWebView!, status:NSStatusItem!
    var timer:Timer?, animation:Timer?
    var reminderActivity:NSObjectProtocol?
    var ready=false, feedbackUntil:Date?, feedbackPose=0, lastNotifiedToken="", day=WaterState.day(Date().timeIntervalSince1970*1000)
    var selfTest=false, lastMenuMode=""
    func applicationDidFinishLaunching(_ notification:Notification) {
        selfTest=ProcessInfo.processInfo.arguments.contains("--self-test")
        if selfTest {DispatchQueue.main.asyncAfter(deadline:.now()+24){print("DESKTOP_SELF_TEST_TIMEOUT");exit(2)}}
        if !selfTest, let id=Bundle.main.bundleIdentifier {
            let others=NSRunningApplication.runningApplications(withBundleIdentifier:id).filter{$0.processIdentifier != ProcessInfo.processInfo.processIdentifier}
            if let other=others.first {other.activate(options:.activateIgnoringOtherApps);NSApp.terminate(nil);return}
        }
        let directory:URL
        if selfTest {directory=FileManager.default.temporaryDirectory.appendingPathComponent("tutu-self-test-\(UUID().uuidString)")}
        else {directory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("TutuWater")}
        store=StateStore(directory:directory)
        lastNotifiedToken=UserDefaults.standard.string(forKey:"notifiedToken") ?? ""
        setupMenu(); setupPet(); setupMain()
        UNUserNotificationCenter.current().delegate=self
        NSWorkspace.shared.notificationCenter.addObserver(self,selector:#selector(woke),name:NSWorkspace.didWakeNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(screensChanged),name:NSApplication.didChangeScreenParametersNotification,object:nil)
        NotificationCenter.default.addObserver(self,selector:#selector(appResignedActive),name:NSApplication.didResignActiveNotification,object:nil)
        timer=Timer(timeInterval:1,target:self,selector:#selector(tick),userInfo:nil,repeats:true);RunLoop.main.add(timer!,forMode:.common)
        animation=Timer(timeInterval:0.06,repeats:true){[weak self] _ in guard let self,self.pet.isVisible else{return};self.petView.breath += 0.085;self.petView.needsDisplay=true};RunLoop.main.add(animation!,forMode:.common)
        feedbackUntil=Date().addingTimeInterval(8);showPet();tick()
    }
    func setupMenu() {
        let appMenu=NSMenu(),item=NSMenuItem();appMenu.addItem(item);let submenu=NSMenu();item.submenu=submenu
        submenu.addItem(withTitle:"收回桌面",action:#selector(collapse),keyEquivalent:"w").target=self
        submenu.addItem(withTitle:"退出兔兔喝水",action:#selector(quit),keyEquivalent:"q").target=self
        let edit=NSMenuItem(title:"编辑",action:nil,keyEquivalent:"");let editMenu=NSMenu(title:"编辑")
        for (name,selector,key) in [("撤销",Selector(("undo:")),"z"),("剪切",#selector(NSText.cut(_:)),"x"),("拷贝",#selector(NSText.copy(_:)),"c"),("粘贴",#selector(NSText.paste(_:)),"v"),("全选",#selector(NSText.selectAll(_:)),"a")] {editMenu.addItem(withTitle:name,action:selector,keyEquivalent:key)}
        edit.submenu=editMenu;appMenu.addItem(edit);NSApp.mainMenu=appMenu
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        status.button?.image=NSImage(systemSymbolName:"hare.fill",accessibilityDescription:"兔兔喝水")
        status.button?.toolTip="兔兔喝水 · 桌面陪伴";status.menu=makeMenu()
    }
    func makeMenu()->NSMenu {
        let menu=NSMenu()
        func add(_ title:String,_ action:Selector){let i=menu.addItem(withTitle:title,action:action,keyEquivalent:"");i.target=self}
        add("展开喝水页面",#selector(showMain));add("收回桌面兔兔",#selector(collapse));menu.addItem(.separator())
        add("我喝过水了",#selector(quickRecord))
        add(["running","due"].contains(store?.state.timer.mode ?? "") ? "暂停陪伴" : "开始 / 继续陪伴",#selector(toggleReminder))
        if ["running","due"].contains(store?.state.timer.mode ?? ""){add("10 分钟后提醒",#selector(quickSnooze))}
        menu.addItem(.separator());add("退出兔兔喝水",#selector(quit));return menu
    }
    func setupPet() {
        pet=FloatingPanel(contentRect:NSRect(x:0,y:0,width:220,height:274),styleMask:[.borderless,.nonactivatingPanel],backing:.buffered,defer:false)
        pet.title="桌面兔兔";pet.level = .floating;pet.isFloatingPanel=true;pet.hidesOnDeactivate=false
        pet.isOpaque=false;pet.backgroundColor = .clear;pet.hasShadow=false;pet.isReleasedWhenClosed=false
        pet.collectionBehavior=[.canJoinAllSpaces,.fullScreenAuxiliary];pet.animationBehavior = .none
        petView=PetView(frame:NSRect(x:0,y:0,width:220,height:274));petView.owner=self;pet.contentView=petView
        let screen=NSScreen.main?.visibleFrame ?? NSRect(x:0,y:0,width:1200,height:800)
        var origin=NSPoint(x:screen.maxX-245,y:screen.minY+24)
        if !selfTest, UserDefaults.standard.object(forKey:"petX") != nil {origin=NSPoint(x:UserDefaults.standard.double(forKey:"petX"),y:UserDefaults.standard.double(forKey:"petY"))}
        pet.setFrameOrigin(origin);clampPosition()
        NSApp.applicationIconImage=petView.sprites.first
    }
    func setupMain() {
        let config=WKWebViewConfiguration();config.userContentController.add(self,name:"tutu");config.websiteDataStore = .nonPersistent()
        web=WKWebView(frame:.zero,configuration:config);web.navigationDelegate=self
        main=NSWindow(contentRect:NSRect(x:0,y:0,width:1060,height:850),styleMask:[.titled,.closable,.miniaturizable,.resizable],backing:.buffered,defer:false)
        main.title="兔兔喝水 · 桌面陪伴";main.contentMinSize=NSSize(width:380,height:600);main.isReleasedWhenClosed=false;main.delegate=self
        main.backgroundColor=NSColor(calibratedRed:0.98,green:0.976,blue:0.965,alpha:1);main.contentView=web
        if let frame=NSScreen.main?.visibleFrame {main.setContentSize(NSSize(width:min(1060,frame.width-60),height:min(850,frame.height-60)))}
        main.center()
        if let url=Bundle.main.url(forResource:"index",withExtension:"html",subdirectory:"web") {web.loadFileURL(url,allowingReadAccessTo:url.deletingLastPathComponent())}
    }
    @objc func showMain(){pet.orderOut(nil);NSApp.activate(ignoringOtherApps:true);if main.isMiniaturized{main.deminiaturize(nil)};main.makeKeyAndOrderFront(nil);sendState()}
    @objc func collapse(){main.orderOut(nil);showPet()}
    func showPet(){clampPosition();pet.orderFrontRegardless();updatePet()}
    func windowShouldClose(_ sender:NSWindow)->Bool {collapse();return false}
    func windowDidMiniaturize(_ notification:Notification){showPet()}
    func windowDidDeminiaturize(_ notification:Notification){pet.orderOut(nil)}
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows flag:Bool)->Bool{showMain();return true}
    @objc func quit(){store.save();NSApp.terminate(nil)}
    func applicationWillTerminate(_ notification:Notification){store?.save();if pet != nil{savePosition()};if let activity=reminderActivity{ProcessInfo.processInfo.endActivity(activity)}}
    func clampPosition(){
        let screens=NSScreen.screens.map{$0.visibleFrame};guard !screens.isEmpty else{return}
        let center=NSPoint(x:pet.frame.midX,y:pet.frame.midY), frame=screens.first(where:{$0.contains(center)}) ?? screens[0]
        var p=pet.frame.origin;p.x=max(frame.minX,min(p.x,frame.maxX-pet.frame.width));p.y=max(frame.minY,min(p.y,frame.maxY-pet.frame.height));pet.setFrameOrigin(p)
    }
    func savePosition(){clampPosition();if !selfTest{UserDefaults.standard.set(pet.frame.minX,forKey:"petX");UserDefaults.standard.set(pet.frame.minY,forKey:"petY")}}
    @objc func screensChanged(){clampPosition()}
    @objc func woke(){tick();sendState()}
    @objc func appResignedActive(){
        DispatchQueue.main.async{[weak self] in self?.presentVisualReminder()}
    }
    func updateReminderActivity(){
        let active=["running","due"].contains(store.state.timer.mode)
        if active && reminderActivity == nil {
            reminderActivity=ProcessInfo.processInfo.beginActivity(options:.userInitiatedAllowingIdleSystemSleep,reason:"Keep the user's hydration reminder responsive while the page is closed")
        } else if !active,let activity=reminderActivity {
            ProcessInfo.processInfo.endActivity(activity);reminderActivity=nil
        }
    }
    func presentVisualReminder(){
        guard store != nil,pet != nil,store.state.timer.mode=="due" else{return}
        let viewingPage=main.isVisible && !main.isMiniaturized && NSApp.isActive && main.isKeyWindow
        if !viewingPage && !pet.isVisible {clampPosition();pet.orderFrontRegardless()}
    }
    @objc func tick(){
        if store.state.advance(){store.save();feedbackUntil=nil;remind();sendState()}
        let current=WaterState.day(Date().timeIntervalSince1970*1000)
        if current != day {day=current;sendState()}
        updateReminderActivity();updatePet();presentVisualReminder()
    }
    func updatePet(){
        let due=store.state.timer.mode=="due"
        petView.isReminder=due
        if due {
            // A restored overdue reminder also takes priority over welcome/feedback messages.
            feedbackUntil=nil;petView.pose=1;petView.message="该喝水啦！\n点我打开客户端并记录"
        } else if let until=feedbackUntil,until>Date(){petView.pose=feedbackPose}
        else {feedbackUntil=nil;petView.pose=store.state.timer.mode=="paused" ? 3 : 0;petView.message=""}
        petView.setAccessibilityLabel(due ? "该喝水啦！点击兔兔打开客户端，完成喝水记录" : "桌面兔兔，点击展开喝水页面，可拖动")
        status.button?.toolTip=due ? "该喝水啦 · 点击打开客户端记录" : "兔兔喝水 · 桌面陪伴"
        petView.needsDisplay=true
        if lastMenuMode != store.state.timer.mode {lastMenuMode=store.state.timer.mode;status.menu=makeMenu()}
    }
    func remind(){
        guard lastNotifiedToken != store.state.timer.token else{return};lastNotifiedToken=store.state.timer.token
        if !selfTest{UserDefaults.standard.set(lastNotifiedToken,forKey:"notifiedToken")}
        guard store.state.settings.notifications,!selfTest else{return}
        let content=UNMutableNotificationContent();content.title="\(store.state.settings.name)提醒你喝水";content.body="忙了一会儿，记得喝口水呀。";content.sound=nil
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier:"tutu-water",content:content,trigger:nil)){_ in}
    }
    @objc func quickRecord(){perform("record")}
    @objc func quickSnooze(){perform("snooze")}
    @objc func toggleReminder(){perform(["running","due"].contains(store.state.timer.mode) ? "pause":"start")}
    func perform(_ action:String,args:[String:Any]=[:],request:String?=nil){
        do {let recordID=try store.state.apply(action,args:args);store.save()
            feedbackUntil=nil
            if action=="record"{feedbackPose=2;petView.message="收到，帮你记好啦！";feedbackUntil=Date().addingTimeInterval(4)}
            if action=="snooze"{feedbackPose=0;petView.message="好呀，10 分钟后见。";feedbackUntil=Date().addingTimeInterval(4)}
            sendState(request:request,result:recordID);updatePet();tick()
        }catch{sendState(request:request,error:error.localizedDescription)}
    }
    func userContentController(_ userContentController:WKUserContentController,didReceive message:WKScriptMessage){
        guard message.frameInfo.isMainFrame,let url=message.frameInfo.request.url,url.isFileURL,let root=Bundle.main.resourceURL?.appendingPathComponent("web").path,url.standardizedFileURL.path.hasPrefix(root+"/"),let body=message.body as? [String:Any],let action=body["action"] as? String else{return}
        let request=body["id"] as? String
        if action=="ready"{ready=true;sendState();if selfTest{runSelfTest()};return}
        if action=="collapse"{collapse();return}
        if action=="notification"{setNotifications(body["enabled"] as? Bool ?? false,request:request);return}
        perform(action,args:body,request:request)
    }
    func sendState(request:String?=nil,result:String?=nil,error:String?=nil){
        guard ready,let data=try? JSONEncoder().encode(store.state),let object=try? JSONSerialization.jsonObject(with:data) else{return}
        var payload:[String:Any] = ["state":object,"storageError":store.storageError ?? ""]
        if let request{payload["id"]=request};if let result{payload["result"]=result};if let error{payload["error"]=error}
        if let encoded=try? JSONSerialization.data(withJSONObject:payload),let json=String(data:encoded,encoding:.utf8){web.evaluateJavaScript("window.desktopReceive(\(json))",completionHandler:nil)}
    }
    func setNotifications(_ enabled:Bool,request:String?){
        if !enabled{store.state.settings.notifications=false;store.save();sendState(request:request);return}
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert]){[weak self] granted,error in DispatchQueue.main.async{guard let self else{return};self.store.state.settings.notifications=granted;self.store.save();self.sendState(request:request,error:granted ? nil:"通知未开启，可在系统设置的通知中允许兔兔喝水。")}}
    }
    func userNotificationCenter(_ center:UNUserNotificationCenter,willPresent notification:UNNotification,withCompletionHandler handler:@escaping (UNNotificationPresentationOptions)->Void){handler([.banner])}
    func userNotificationCenter(_ center:UNUserNotificationCenter,didReceive response:UNNotificationResponse,withCompletionHandler handler:@escaping ()->Void){DispatchQueue.main.async{self.showMain()};handler()}
    func webView(_ webView:WKWebView,decidePolicyFor navigationAction:WKNavigationAction,decisionHandler:@escaping (WKNavigationActionPolicy)->Void){
        guard let url=navigationAction.request.url else{decisionHandler(.cancel);return}
        if url.isFileURL,let root=Bundle.main.resourceURL?.appendingPathComponent("web").path,url.standardizedFileURL.path.hasPrefix(root+"/"){decisionHandler(.allow)}else{decisionHandler(.cancel)}
    }
    func captureReminderQA(){
        let qa=Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("qa")
        try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
        for (index,elapsed) in [0.0,0.4,0.8,1.2].enumerated(){
            petView.reminderElapsedOverride=elapsed
            if let bitmap=petView.bitmapImageRepForCachingDisplay(in:petView.bounds){
                petView.cacheDisplay(in:petView.bounds,to:bitmap)
                let image=NSImage(size:petView.bounds.size);image.lockFocus()
                NSColor(calibratedRed:0.14,green:0.17,blue:0.2,alpha:1).setFill();petView.bounds.fill()
                if let cg=bitmap.cgImage{NSImage(cgImage:cg,size:petView.bounds.size).draw(in:petView.bounds,from:.zero,operation:.sourceOver,fraction:1)};image.unlockFocus()
                if let data=image.tiffRepresentation,let rendered=NSBitmapImageRep(data:data){try? rendered.representation(using:.png,properties:[:])?.write(to:qa.appendingPathComponent("reminder-\(index).png"))}
            }
        }
        petView.reminderElapsedOverride=nil
    }
    func runSelfTest(){
        do {
            precondition(pet.level == .floating && !pet.hidesOnDeactivate && !pet.isOpaque)
            precondition(petView.sprites.count == 4)
            showMain();precondition(main.isVisible && !pet.isVisible)
            main.performClose(nil);precondition(!main.isVisible && pet.isVisible)
            try store.state.apply("start");store.state.timer.dueAt=Date().timeIntervalSince1970*1000-1
            pet.orderOut(nil);tick()
            precondition(store.state.timer.mode=="due" && !store.state.settings.notifications)
            precondition(pet.isVisible && petView.isReminder && petView.pose==1 && petView.message.contains("记录"))
            precondition(reminderActivity != nil)
            captureReminderQA()
            // Opening does not acknowledge the reminder or create a drinking record.
            _ = petView.accessibilityPerformPress()
            precondition(main.isVisible && store.state.timer.mode=="due" && store.state.records.isEmpty)
            main.performClose(nil)
            precondition(pet.isVisible && petView.isReminder && store.state.timer.mode=="due")
            perform("snooze")
            precondition(!petView.isReminder && store.state.timer.mode=="running")
            store.state.timer.dueAt=Date().timeIntervalSince1970*1000-1;tick()
            perform("pause")
            precondition(!petView.isReminder && reminderActivity==nil)
            // Overdue state loaded on startup must override the welcome message.
            store.state.timer.mode="due";feedbackUntil=Date().addingTimeInterval(8);updatePet()
            precondition(petView.isReminder && petView.pose==1 && feedbackUntil==nil)
            perform("record")
            precondition(!petView.isReminder && store.state.records.count==1 && store.state.timer.mode=="running")
            let recordID=store.state.records[0].id
            perform("undo",args:["recordId":recordID])
            precondition(petView.isReminder && store.state.timer.mode=="due" && store.state.records.isEmpty)
            // Use the actual client button and message bridge for the final record.
            showMain()
            web.evaluateJavaScript("document.getElementById('recordWater').click()",completionHandler:nil)
            DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
                self.web.evaluateJavaScript("JSON.stringify({count:document.getElementById('dailyCount').textContent,mode:document.getElementById('statusText').textContent,bridge:typeof window.desktopReceive,green:getComputedStyle(document.documentElement).getPropertyValue('--green').trim(),button:getComputedStyle(document.getElementById('recordWater')).backgroundColor})"){result,error in
                    print("DESKTOP_SELF_TEST",result ?? "no-result",error?.localizedDescription ?? "ok")
                    guard error == nil, let text = result as? String, let data = text.data(using:.utf8), let resultJSON = try? JSONSerialization.jsonObject(with:data) as? [String:String], resultJSON["count"] == "1", resultJSON["bridge"] == "function", resultJSON["green"] == "#517668", resultJSON["button"] == "rgb(81, 118, 104)", !self.petView.isReminder, self.store.state.timer.mode == "running" else {exit(2)};let saved=StateStore(directory:self.store.url.deletingLastPathComponent());precondition(saved.state.records.count==1)
                    let qa=Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("qa")
                    try? FileManager.default.createDirectory(at:qa,withIntermediateDirectories:true)
                    for pose in 0..<4 {
                        self.petView.pose=pose;self.petView.message="";self.petView.needsDisplay=true
                        if let bitmap=self.petView.bitmapImageRepForCachingDisplay(in:self.petView.bounds){self.petView.cacheDisplay(in:self.petView.bounds,to:bitmap);try? bitmap.representation(using:.png,properties:[:])?.write(to:qa.appendingPathComponent("pet-\(pose).png"))}
                    }
                    self.showMain()
                    self.web.takeSnapshot(with:nil){image,error in
                        if let image,let tiff=image.tiffRepresentation,let bitmap=NSBitmapImageRep(data:tiff){try? bitmap.representation(using:.png,properties:[:])?.write(to:qa.appendingPathComponent("desktop-page.png"))}
                        self.store.state=WaterState();self.store.save();print("DESKTOP_SELF_TEST_PASS");NSApp.terminate(nil)
                    }
                }
            }
        }catch{print("DESKTOP_SELF_TEST_FAIL",error);exit(2)}
    }
}
@main
struct Launcher {
    static func main() {
        let app=NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate=AppDelegate();app.delegate=delegate
        app.run()
    }
}
