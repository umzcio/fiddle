import SwiftUI

@main
struct FiddleApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    // Observed at the scene level so the MenuBarExtra label re-renders when the
    // run status flips (a nested @ObservedObject in the label alone does not).
    @ObservedObject private var menuState = MenuState.shared

    var body: some Scene {
        MenuBarExtra {
            PopoverContainer(controller: appDelegate.controller, app: appDelegate)
                .frame(width: 300, height: 322)
        } label: {
            MenuLabel(state: menuState)
        }
        .menuBarExtraStyle(.window)
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = FiddleController()
    private var mainWindowController: MainWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        controller.menuState = MenuState.shared
        let wc = MainWindowController(controller: controller)
        mainWindowController = wc
        wc.show()
    }

    func showMainWindow() { mainWindowController?.show() }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        showMainWindow()
        return true
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        controller.recheckPermissions()
    }
    func applicationWillTerminate(_ notification: Notification) {
        controller.shutdown()
    }
}
