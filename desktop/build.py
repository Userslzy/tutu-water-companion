from pathlib import Path
import argparse, shutil, subprocess, plistlib, platform, tempfile
parser=argparse.ArgumentParser(description='Build the offline macOS desktop companion.')
parser.add_argument('--universal',action='store_true',help='Include both Apple silicon and Intel architectures.')
options=parser.parse_args()
root=Path(__file__).resolve().parent
app=root/'output'/'兔兔喝水.app'
contents=app/'Contents'
for p in [contents/'MacOS', contents/'Resources'/'web'/'assets']: p.mkdir(parents=True,exist_ok=True)
web=contents/'Resources'/'web'
source=root.parent/'dist'
html=(source/'index.html').read_text()
css=(source/'style.css').read_text()
css="\n".join(line for line in css.splitlines() if not line.startswith("@import"))
css=css.replace("url('/assets/", "url('assets/")
css+='\n.desktop-actions{display:flex;gap:8px}.stage{height:285px}.rabbit-touch{width:235px;height:235px}.topbar{height:88px}.page-heading{padding:23px 0}.companion-card{padding-top:20px}.shell{padding-top:0}@media(max-width:760px){.brand small{display:none}.brand{font-size:17px;gap:8px}.settings-button{padding:9px}.desktop-actions{gap:5px}.desktop-actions .settings-button{font-size:12px}.page-heading h1{font-size:24px}}\n'
html=html.replace('<link rel="stylesheet" href="/style.css">','<style>'+css+'</style>')
model=(source/'model.js').read_text().replace('export ','')
js=model+'\n'+(root/'desktop.js').read_text()
html=html.replace('<script src="/app.js" type="module"></script>','<script defer src="desktop-bundle.js"></script>')
html=html.replace('href="/" aria-label="兔兔喝水首页"','href="#" aria-label="兔兔喝水首页"')
start=html.index('    <button class="settings-button" id="openSettings"')
end=html.index('\n',start)
original=html[start:end]
html=html[:start]+'<div class="desktop-actions">'+original+'<button class="settings-button" id="collapseDesktop">收回桌面</button></div>'+html[end:]
html=html.replace('你的小小喝水搭子','你的桌面喝水搭子').replace('记录只保存在当前浏览器','记录保存在这台 Mac')
help_start=html.index('<div class="help-content">')
help_end=html.index('</dialog>',help_start)
html=html[:help_start]+'''<div class="help-content"><p>单击桌面兔兔展开页面。点击「收回桌面」或窗口左上角的关闭按钮，兔兔就会回到桌面，提醒继续计时。</p><p>按住兔兔可以拖动位置，右键打开快捷菜单。菜单栏的小兔图标也可以展开、暂停或退出。</p><p>桌面版的记录独立保存在这台 Mac，不与网页版同步。关闭窗口不会丢失记录；退出应用后也会保存。</p><p>退出应用或电脑休眠时不会提醒。再次打开或唤醒电脑后会检查是否有到期提醒。到点后，桌面兔兔会举杯轻跳并持续显示提示，点击兔兔即可打开客户端记录。记录、延后或暂停后结束提醒；只打开或关闭页面不会自动完成记录。系统通知是可选项，未开启也会显示兔兔动画。</p><p class="gentle-note">跟着自己的需要喝水，兔兔不会给你设定喝水目标。</p></div>'''+html[help_end:]
(web/'index.html').write_text(html)
(web/'desktop-bundle.js').write_text(js)
shutil.copy2(source/'assets'/'bunny-poses.png',web/'assets'/'bunny-poses.png')
shutil.copy2(root/'Assets'/'bunny-transparent.png',contents/'Resources'/'bunny-transparent.png')
info={'CFBundleName':'兔兔喝水','CFBundleDisplayName':'兔兔喝水','CFBundleIdentifier':'com.lvcha.tutu-water.desktop','CFBundleVersion':'2','CFBundleShortVersionString':'1.1.0','CFBundleExecutable':'TutuWater','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'13.0','LSUIElement':True,'NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication','NSHumanReadableCopyright':'兔兔喝水 · 桌面陪伴'}
with (contents/'Info.plist').open('wb') as f:plistlib.dump(info,f)
architectures=['arm64','x86_64'] if options.universal else [('arm64' if platform.machine()=='arm64' else 'x86_64')]
with tempfile.TemporaryDirectory(prefix='tutu-build-') as directory:
    binaries=[]
    for architecture in architectures:
        binary=Path(directory)/('TutuWater-'+architecture)
        subprocess.run(['xcrun','swiftc',str(root/'Sources'/'State.swift'),str(root/'Sources'/'ReminderMotion.swift'),str(root/'Sources'/'App.swift'),'-o',str(binary),'-framework','AppKit','-framework','WebKit','-framework','UserNotifications','-target',architecture+'-apple-macos13.0','-O'],check=True)
        binaries.append(str(binary))
    if options.universal:
        subprocess.run(['xcrun','lipo','-create',*binaries,'-output',str(contents/'MacOS'/'TutuWater')],check=True)
    else:
        shutil.copy2(binaries[0],contents/'MacOS'/'TutuWater')
subprocess.run(['codesign','--force','--deep','--sign','-',str(app)],check=True)
subprocess.run(['codesign','--verify','--deep','--strict',str(app)],check=True)
print(app)
