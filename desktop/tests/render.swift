import AppKit
let source=NSImage(contentsOfFile:CommandLine.arguments[1])!
let cg=source.cgImage(forProposedRect:nil,context:nil,hints:nil)!
let frame=cg.cropping(to:CGRect(x:0,y:0,width:cg.width/2,height:cg.height/2))!
let image=NSImage(cgImage:frame,size:NSSize(width:220,height:220))
let output=NSImage(size:NSSize(width:300,height:300));output.lockFocus()
NSColor(calibratedRed:0.14,green:0.17,blue:0.2,alpha:1).setFill();NSRect(x:0,y:0,width:300,height:300).fill()
image.draw(in:NSRect(x:40,y:40,width:220,height:220),from:.zero,operation:.sourceOver,fraction:1)
output.unlockFocus()
let bitmap=NSBitmapImageRep(data:output.tiffRepresentation!)!
try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:CommandLine.arguments[2]))
