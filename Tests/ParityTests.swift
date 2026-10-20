import SwiftUI
import AppKit
import CoreImage

@MainActor @main struct ParityTests {
    static var checks=0
    static func check(_ condition:@autoclosure()->Bool,_ message:String) { checks+=1;if !condition(){fatalError("FAIL: "+message)} }
    static func near(_ value:Double,_ expected:Double,_ message:String,_ tolerance:Double=0.00001) { check(abs(value-expected)<tolerance,message+" got \(value), expected \(expected)") }
    static func main() throws {
        near(WebEase.linear.value(0.4),0.4,"linear timing")
        near(WebEase.arrive.value(0),0,"arrival begins");near(WebEase.arrive.value(1),1,"arrival ends")
        check(WebEase.arrive.value(0.2)>0.7,"CSS exponential arrival")
        near(WebChartProgress.value(elapsed:0.13+0.29,index:0),0.875,"JS cubic ease-out exact midpoint")
        near(WebChartProgress.value(elapsed:0.22,index:3),0,"card stagger holds")
        near(WebChartProgress.value(elapsed:0.13+0.135+0.58,index:3),1,"last chart finishes")
        var time=100.0
        let timeline=MotionTimeline(clock:{time})
        timeline.animate("alpha",to:1,from:0,duration:0.19,delay:0.11)
        time+=0.05;timeline.sample(at:time);near(timeline.value("alpha"),0,"incoming page remains transparent before 110ms")
        time=100.205;timeline.sample(at:time);near(timeline.value("alpha"),WebEase.arrive.value(0.5),"CSS page timing")
        let presentation=timeline.value("alpha");timeline.freeze();timeline.animate("alpha",to:0,duration:0.16,ease:.depart)
        near(timeline.value("alpha"),presentation,"interruption captures current opacity")
        time+=0.16;timeline.sample(at:time);near(timeline.value("alpha"),0,"reversal finishes")
        var jobs:[(Double,()->Void)]=[];time=200
        let nav=NavigationMotion(clock:{time},scheduler:{delay,action in jobs.append((time+delay,action))})
        func advance(_ delta:Double) { time+=delta;nav.timeline.sample(at:time);let ready=jobs.filter{$0.0<=time};jobs.removeAll{$0.0<=time};ready.forEach{$0.1()} }
        nav.update(to:.statistics,running:false,empty:true,reduced:false)
        advance(0.1);near(nav.timeline.value("statistics.opacity"),0,"statistics arrival delay")
        check(nav.timeline.value("home.opacity",fallback:1)<1,"home fades independently")
        advance(0.02);check(nav.timeline.value("statistics.part.header.opacity")>0,"header arrives first")
        near(nav.timeline.value("statistics.part.card3.opacity"),0,"last card waits for 170ms")
        advance(0.31);check(nav.statisticsMounted && !nav.homeVisible,"page cleanup after group completion")
        nav.update(to:.focus,running:false,empty:true,reduced:false);advance(0.07)
        let prior=nav.timeline.value("statistics.opacity");nav.update(to:.statistics,running:false,empty:true,reduced:false)
        near(nav.timeline.value("statistics.opacity"),prior,"rapid page reversal does not restart from zero")
        advance(0.26);check(nav.statisticsMounted && !nav.homeVisible,"rapid reversal cleanup")
        nav.update(to:.focus,running:false,empty:true,reduced:true);check(!nav.statisticsMounted && nav.homeVisible,"reduced motion settles pages immediately")
        nav.update(to:.settings,running:false,empty:true,reduced:false)
        advance(0.08);check(nav.timeline.value("settings.part.0.opacity")>0,"settings header starts at75ms")
        near(nav.timeline.value("settings.part.1.opacity"),0,"settings sound waits97ms")
        advance(0.09);near(nav.timeline.value("home.opacity"),0,"home gone at160ms before circle finishes")
        check(nav.timeline.value("settings.reveal")<1,"circle continues independent of home opacity")
        advance(0.34);check(nav.settingsMounted && !nav.homeVisible,"settings final visibility")
        nav.update(to:.focus,running:false,empty:true,reduced:false);advance(0.05);near(nav.timeline.value("home.opacity"),0,"settings return holds home for60ms")
        advance(0.24);check(!nav.settingsMounted && nav.homeVisible,"settings closes after280ms")
        nav.update(to:.settings,running:false,empty:true,reduced:false);advance(0.51)
        nav.update(to:.focus,running:false,empty:true,reduced:false);advance(0.02)
        nav.update(to:.statistics,running:false,empty:true,reduced:false)
        advance(0.29)
        check(!nav.settingsMounted && nav.statisticsMounted,"Escape then Cmd2 removes closing settings before statistics")
        near(nav.timeline.value("settings.reveal"),0,"interrupted settings close reaches zero reveal")
        advance(0.43)
        check(!nav.settingsMounted && nav.statisticsMounted && !nav.homeVisible,"Escape Cmd2 finishes with statistics as sole mounted secondary page")
        nav.update(to:.focus,running:false,empty:true,reduced:true)
        nav.update(to:.settings,running:false,empty:true,reduced:false);advance(0.51)
        nav.update(to:.focus,running:false,empty:true,reduced:false);advance(0.02)
        nav.update(to:.statistics,running:false,empty:true,reduced:false);advance(0.02)
        nav.update(to:.focus,running:false,empty:true,reduced:false);advance(0.29)
        check(!nav.settingsMounted && !nav.statisticsMounted && nav.homeVisible,"Escape Cmd2 then Cmd1 cancels pending statistics and clears settings")
        let restoredSpring = LiquidSpring(initial: 1, automatic: false)
        near(restoredSpring.position, 1, "restored timer controls start fully separated")
        near(restoredSpring.target, 1, "restored control spring is already at its target")
        near(restoredSpring.velocity, 0, "restored controls have no entrance motion")
        var springTime=300.0
        let spring=LiquidSpring(automatic:false,clock:{springTime});spring.setTarget(1)
        var referencePosition=0.0,referenceVelocity=0.0
        for _ in 0..<20 {
            let dt=1.0/120,h=dt/2,omega=14.5
            for _ in 0..<2 { referenceVelocity += (omega*omega*(1-referencePosition)-2*omega*referenceVelocity)*h;referencePosition += referenceVelocity*h }
            springTime+=dt;spring.step(at:springTime)
        }
        near(spring.position,referencePosition,"same JS semi-implicit spring integrator",0.0000001)
        spring.setTarget(0);for _ in 0..<200 { springTime+=1.0/120;spring.step(at:springTime) };near(spring.position,0,"liquid retraction completes")
        spring.setTarget(1,instant:true);near(spring.position,1,"background/reduce settles reset immediately")
        let palette=Palette(dark:false)
        guard let light=LiquidRaster.image(width:336,progress:1,fill:palette.accent,stroke:nil,filtered:true),let dark=LiquidRaster.image(width:336,progress:1,fill:Color(hex:0x202020),stroke:Color(hex:0x3a3a3a),filtered:true) else { fatalError("liquid renderer unavailable") }
        func pixel(_ image:CGImage,_ x:Int,_ y:Int)->[Double] {
            var bytes=[UInt8](repeating:0,count:image.width*image.height*4)
            bytes.withUnsafeMutableBytes { pointer in
                let context=CGContext(data:pointer.baseAddress,width:image.width,height:image.height,bitsPerComponent:8,bytesPerRow:image.width*4,space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue)!
                context.draw(image,in:CGRect(x:0,y:0,width:image.width,height:image.height))
            }
            let offset=(y*image.width+x)*4,alpha=Double(bytes[offset+3])/255
            return [alpha>0 ? Double(bytes[offset])/255/alpha : 0,alpha>0 ? Double(bytes[offset+1])/255/alpha : 0,alpha>0 ? Double(bytes[offset+2])/255/alpha : 0,alpha]
        }
        let center=pixel(light,200,64);near(center[0],12.0/255,"SVG fill color retained",0.008);near(center[1],135.0/255,"SVG green not whitened",0.008)
        near(pixel(light,Int((20+336-49)*2),64)[3],0,"water drop detaches with transparent10px gap",0.01)
        let darkCenter=pixel(dark,200,64);near(darkCenter[0],32.0/255,"dark fill retained",0.008)
        let darkEdge=pixel(dark,200,20);check(darkEdge[0]>darkCenter[0],"dark1px stroke preserved by fullSVG chain")
        let matrixImage=try appearanceProbe();check(matrixImage,"CSS dark transform preserves sRGB and alpha")
        var colorTime=400.0
        let controlColors=ControlColorMotion(clock:{colorTime})
        controlColors.update(palette:palette,running:false,instant:true)
        controlColors.update(palette:palette,running:true)
        colorTime+=0.09;controlColors.timeline.sample(at:colorTime)
        let fillStart=12.0/255,fillEnd=226.0/255
        let fraction=WebEase.cubic(0.25,0.1,0.25,1).value(0.09/0.2)
        let fillRed=NSColor(controlColors.color("fill",fallback:.clear)).usingColorSpace(.sRGB)!.redComponent
        near(Double(fillRed),fillStart+(fillEnd-fillStart)*fraction,"control fill samples CSS200ms ease",0.0001)
        let inkFraction=WebEase.cubic(0.25,0.1,0.25,1).value(0.5)
        let inkRed=NSColor(controlColors.color("ink",fallback:.clear)).usingColorSpace(.sRGB)!.redComponent
        near(Double(inkRed),1+(52.0/255-1)*inkFraction,"control ink samples independent180ms",0.0001)
        controlColors.update(palette:palette,running:false)
        near(Double(NSColor(controlColors.color("fill",fallback:.clear)).usingColorSpace(.sRGB)!.redComponent),Double(fillRed),"control reversal keeps presentation color",0.0001)
        colorTime+=0.2;controlColors.timeline.sample(at:colorTime)
        near(Double(NSColor(controlColors.color("fill",fallback:.clear)).usingColorSpace(.sRGB)!.redComponent),fillStart,"control reversal completes",0.0001)
        controlColors.update(palette:Palette(dark:true),running:true,instant:true)
        near(Double(NSColor(controlColors.color("fill",fallback:.clear)).usingColorSpace(.sRGB)!.redComponent),32.0/255,"reduced motion settles colors",0.0001)
        near(CompletionEnvelope.gain(at:0.01),0.06,"WebAudio linear attack")
        near(CompletionEnvelope.gain(at:0.02),0.12,"WebAudio peak gain")
        near(CompletionEnvelope.gain(at:0.56),sqrt(0.12*0.001),"WebAudio exponential midpoint")
        near(CompletionEnvelope.gain(at:1.1),0.001,"WebAudio ramp target")
        near(CompletionEnvelope.gain(at:1.15),0.001,"WebAudio final hold")
        near(CompletionEnvelope.gain(at:1.2),0,"WebAudio stop")
        try verifyWindowDragReadiness()
        let report:[String:Any]=["checks":checks,"geometry":["outer":[390,420],"content":[388,418],"contentOrigin":[1,1],"controlsWidth":336,"runningControlsCenterY":375,"settingsAnchor":[348.5,38]],"nativeTimeline":"matches HTML delays/durations/Bezier and interruption samples","liquid":"Gaussian3.6 -> alpha19a-9 -> SourceGraphic atop liquid, dark1px stroke" ]
        let data=try JSONSerialization.data(withJSONObject:report,options:[.prettyPrinted,.sortedKeys]);try data.write(to:URL(fileURLWithPath:CommandLine.arguments[1]))
        print("PASS: \(checks) fidelity checks: CSS timing, staged navigation, interruptions, JS spring, SVG liquid colors/stroke, chart progress, and sRGB alpha.")
    }
    static func appearanceProbe() throws -> Bool {
        let cs=CGColorSpace(name:CGColorSpace.sRGB)!,rgb=[12.0,135.0,77.0]
        let alphas=[0,64,128,255];var bytes=[UInt8]()
        for a in alphas { bytes += rgb.map{UInt8(($0*Double(a)/255).rounded())}+[UInt8(a)] }
        let source=CIImage(bitmapData:Data(bytes),bytesPerRow:16,size:CGSize(width:4,height:1),format:.RGBA8,colorSpace:cs)
        var out=[UInt8](repeating:0,count:16)
        CSSVideoAppearance.context.render(CSSVideoAppearance.image(source),toBitmap:&out,rowBytes:16,bounds:CGRect(x:0,y:0,width:4,height:1),format:.RGBA8,colorSpace:cs)
        let gray=1.09-1.18*(0.2126*rgb[0]+0.7152*rgb[1]+0.0722*rgb[2])/255
        return alphas.enumerated().allSatisfy { i,a in abs(Int(out[i*4+3])-a)<=1 && abs(Int(out[i*4])-Int((gray*Double(a)).rounded()))<=2 }
    }
    /// Dispatch only to our own offscreen view; no desktop input is synthesized.
    static func verifyWindowDragReadiness() throws {
        _ = NSApplication.shared
        let area = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let window = NSWindow(contentRect: CGRect(x: 400, y: 200, width: 446, height: 476), styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.contentView = nil; window.close() }
        var proximity = WindowDockProximity(), ticks = 0, releases = 0, committed = false
        var time = 0.0
        let host = NSHostingView(rootView: WindowDragArea(onDragBegin: { proximity.reset() }, onDragUpdate: { _ in
            time += 1
            if proximity.update(frame: window.frame, area: area, margin: 28, now: time) { ticks += 1 }
        }, onDragEnd: { moved in releases += 1; committed = moved && proximity.edge != nil }))
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        func findDragView(_ view: NSView) -> NSView? {
            if String(describing: type(of: view)).contains("DragView") { return view }
            return view.subviews.lazy.compactMap { findDragView($0) }.first
        }
        guard let view = findDragView(host) else { fatalError("Drag surface did not mount") }
        func event(_ type: NSEvent.EventType, _ x: CGFloat) -> NSEvent {
            NSEvent.mouseEvent(with: type, location: NSPoint(x: x, y: 400), modifierFlags: [], timestamp: time, windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        }
        view.mouseDown(with: event(.leftMouseDown, 220))
        view.mouseDragged(with: event(.leftMouseDragged, -328))
        check(proximity.edge == .left && ticks == 1, "native overshoot arms edge feedback before mouse-up")
        check(releases == 0 && !committed && window.frame.size == WindowDockGeometry.fullSize, "held drag keeps full mode without committing")
        view.mouseDragged(with: event(.leftMouseDragged, 220))
        check(ticks == 1, "native held drag does not repeat feedback")
        view.mouseUp(with: event(.leftMouseUp, 220))
        check(releases == 1 && committed, "release commits previously armed edge")
        window.setFrameOrigin(NSPoint(x: 400, y: 200)); committed = false
        view.mouseDown(with: event(.leftMouseDown, 220))
        view.mouseDragged(with: event(.leftMouseDragged, -208))
        view.mouseDragged(with: event(.leftMouseDragged, 368))
        check(proximity.edge == nil, "native drag away cancels ready state while held")
        view.mouseUp(with: event(.leftMouseUp, 220))
        check(releases == 2 && !committed, "release after leaving edge does not dock")
        window.setFrameOrigin(NSPoint(x: -28, y: 200))
        view.mouseDown(with: event(.leftMouseDown, 220))
        view.mouseUp(with: event(.leftMouseUp, 220))
        check(releases == 3 && !committed, "clicking near edge never counts as a drag")
    }

}
