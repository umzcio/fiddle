//
//  MenuBar.swift
//  Fiddle
//
//  The menu-bar item is a skinned popover (a compact "mini fiddle") hosting a
//  second WKWebView wired to the shared FiddleController. A slim MenuState drives
//  the bar icon's running state.
//

import SwiftUI
import WebKit

/// Drives the menu-bar icon (filled flame while running). A single shared
/// instance is observed by the App scene (so the MenuBarExtra label re-renders)
/// and updated by the FiddleController.
@MainActor
final class MenuState: ObservableObject {
    static let shared = MenuState()
    @Published var status: RunStatus = .idle
    @Published var skin: String = "red"
}

struct MenuLabel: View {
    @ObservedObject var state: MenuState
    var body: some View {
        Image(systemName: state.status == .running ? "flame.fill" : "flame")
            // Idle: the standard template look (adapts to the menu bar). Running:
            // a filled flame tinted with the current skin's accent color.
            .foregroundStyle(state.status == .running ? Self.accent(for: state.skin) : Color.primary)
    }

    /// The bright accent (`--ac-glow`) for each skin, mirroring index.html.
    static func accent(for skin: String) -> Color {
        switch skin {
        case "cobalt":   return Color(red: 0x4f/255, green: 0x93/255, blue: 0xff/255)
        case "graphite": return Color(red: 0x9a/255, green: 0xa2/255, blue: 0xad/255)
        case "emerald":  return Color(red: 0x3f/255, green: 0xe0/255, blue: 0x93/255)
        default:         return Color(red: 0xe2/255, green: 0x38/255, blue: 0x1f/255) // red
        }
    }
}

/// Hosts the popover's web view: a second bridge wired to the shared controller,
/// loading the compact `surface=menubar` UI. App-level window actions route to
/// the AppDelegate.
@MainActor
final class PopoverController: NSObject, BridgeHost {
    private(set) var bridge: FiddleBridge!
    private weak var app: AppDelegate?

    init(controller: FiddleController, app: AppDelegate) {
        self.app = app
        super.init()
        bridge = FiddleBridge(host: self, surface: "menubar")
        bridge.controller = controller
        controller.addSink(bridge)
    }

    var webView: WKWebView { bridge.webView }

    func performWindowAction(_ action: WindowAction) {
        switch action {
        case .showWindow: app?.showMainWindow()
        case .quit:       NSApplication.shared.terminate(nil)
        default:          break
        }
    }

    func webViewDidLoad(_ webView: WKWebView) {}
}

/// SwiftUI host for the popover web view, created once and reused.
struct PopoverContainer: NSViewRepresentable {
    let controller: FiddleController
    let app: AppDelegate

    @MainActor final class Coordinator { var popover: PopoverController? }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSView {
        if context.coordinator.popover == nil {
            context.coordinator.popover = PopoverController(controller: controller, app: app)
        }
        let web = context.coordinator.popover!.webView
        web.frame = NSRect(x: 0, y: 0, width: 300, height: 322)
        return web
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}
