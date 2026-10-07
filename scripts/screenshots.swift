// Render the actual SwiftUI screens offscreen using synthetic demo data.
import SwiftUI
import AppKit

@main struct DocumentationScreenshots {
    @MainActor static func main() async throws {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)
        let output=URL(fileURLWithPath:CommandLine.arguments.last!)
        try FileManager.default.createDirectory(at:output,withIntermediateDirectories:true)
        let model=AtlasModel()
        await model.refresh();await model.loadSettings();await model.loadMemories()
        guard model.error==nil else {fatalError(model.error!)}
        for (route,name) in [("Overview","overview"),("Memories","memories"),("Knowledge Graph","knowledge-graph"),("Settings","settings")] {
            model.route=route
            if route=="Memories" {model.selected=model.records.first}
            if route=="Knowledge Graph" {model.project="memory-atlas";await model.loadGraph()}
            let view=NSHostingView(rootView:Dashboard().environmentObject(model).frame(width:1380,height:900))
            let window=NSWindow(contentRect:NSRect(x:0,y:0,width:1380,height:900),styleMask:.borderless,backing:.buffered,defer:false)
            window.appearance=NSAppearance(named:.darkAqua)
            view.appearance=NSAppearance(named:.darkAqua)
            window.contentView=view
            view.frame=NSRect(x:0,y:0,width:1380,height:900)
            view.layoutSubtreeIfNeeded()
            try await Task.sleep(nanoseconds:500_000_000)
            view.layoutSubtreeIfNeeded()
            guard let bitmap=view.bitmapImageRepForCachingDisplay(in:view.bounds) else {fatalError("Could not render "+route)}
            view.cacheDisplay(in:view.bounds,to:bitmap)
            guard let png=bitmap.representation(using:.png,properties:[:]) else {fatalError("Could not encode "+route)}
            try png.write(to:output.appendingPathComponent(name+".png"))
            window.contentView=nil
        }
        print("Rendered four native screens with synthetic data only.")
    }
}
