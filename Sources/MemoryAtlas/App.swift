import SwiftUI
import AppKit

#if !DOCUMENTATION_RENDERER
@main
#endif
struct MemoryAtlasApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model=AtlasModel()
    var body: some Scene {
        Window("Memory Atlas",id:"dashboard") {
            Dashboard().environmentObject(model).frame(minWidth:1080,minHeight:700)
                .onAppear { AppDelegate.model=model }
        }.defaultSize(width:1380,height:900)
        .commands { CommandGroup(replacing:.newItem) {} }
        Settings { SettingsView().environmentObject(model).frame(width:760,height:700) }
    }
}
final class AppDelegate: NSObject,NSApplicationDelegate {
    static weak var model: AtlasModel?
    static var reopen: (() -> Void)?
    var status: NSStatusItem?
    func applicationDidFinishLaunching(_ notification: Notification) {
        status=NSStatusBar.system.statusItem(withLength:NSStatusItem.squareLength)
        if let button=status?.button {
            button.image=NSImage(systemSymbolName:"point.3.connected.trianglepath.dotted",accessibilityDescription:"Memory Atlas")
            button.target=self;button.action=#selector(openDashboard);button.toolTip="Open Memory Atlas"
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+1) {
            if !Bridge.demo && UserDefaults.standard.object(forKey:"configuredLogin") == nil {
                Self.model?.launchAtLogin(true);UserDefaults.standard.set(true,forKey:"configuredLogin")
            }
        }
    }
    @objc func openDashboard() {
        NSApp.activate(ignoringOtherApps:true)
        if let window=NSApp.windows.first(where:{$0.title=="Memory Atlas"}) {window.makeKeyAndOrderFront(nil)}
        else { Self.reopen?() }
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender:NSApplication)->Bool {false}
    func applicationShouldHandleReopen(_ sender:NSApplication,hasVisibleWindows:Bool)->Bool {openDashboard();return true}
}
