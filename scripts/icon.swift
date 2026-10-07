import AppKit
let destination = CommandLine.arguments[1]
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let pixels=size*scale
        let image=NSImage(size:NSSize(width:pixels,height:pixels))
        image.lockFocus()
        let d=CGFloat(pixels)
        NSColor(calibratedRed:0.065,green:0.085,blue:0.09,alpha:1).setFill()
        NSBezierPath(roundedRect:NSRect(x:0,y:0,width:d,height:d),xRadius:d*0.22,yRadius:d*0.22).fill()
        let pts=[CGPoint(x:d*0.5,y:d*0.52),CGPoint(x:d*0.27,y:d*0.72),CGPoint(x:d*0.76,y:d*0.68),CGPoint(x:d*0.32,y:d*0.25),CGPoint(x:d*0.73,y:d*0.31)]
        NSColor(calibratedRed:0.4,green:0.76,blue:0.63,alpha:0.5).setStroke()
        for i in 1..<pts.count{let path=NSBezierPath();path.move(to:pts[0]);path.line(to:pts[i]);path.lineWidth=d*0.018;path.stroke()}
        for (i,p) in pts.enumerated(){(i==0 ? NSColor.white:NSColor(calibratedRed:0.4,green:0.76,blue:0.63,alpha:1)).setFill();let r=d*(i==0 ? 0.075:0.045);NSBezierPath(ovalIn:NSRect(x:p.x-r,y:p.y-r,width:r*2,height:r*2)).fill()}
        image.unlockFocus()
        let bitmap=NSBitmapImageRep(data:image.tiffRepresentation!)!
        try bitmap.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:destination+"/icon_\(size)x\(size)\(scale==2 ? "@2x":"").png"))
    }
}
