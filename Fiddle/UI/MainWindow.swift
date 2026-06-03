//
//  MainWindow.swift
//  Fiddle
//
//  The custom borderless window that hosts the web UI. It has no system title
//  bar (the web chrome draws its own ? / - / x orbs), is draggable by its
//  background, sizes itself to the rendered shell, and is transparent so the
//  rounded chrome bezel reads correctly against the desktop.
//

import AppKit
import WebKit
import os

/// Borderless windows refuse key/main status by default; the web UI needs both
/// so its text fields and buttons are interactive.
final class FiddleWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The web view that hosts the UI. It must never start a window drag, otherwise
/// AppKit swallows mouse-downs on non-form elements (links, the permission
/// banner, task cards) before the page can handle them. It also accepts the
/// first click so controls work even when the window was not already focused.
final class FiddleWebView: WKWebView {
    override var mouseDownCanMoveWindow: Bool { false }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

/// A transparent strip over the top-left chrome that drags the borderless
/// window, since the web view itself no longer moves it. Sized to cover the
/// "fiddle" wordmark area only, leaving the device selector and ? / - / x orbs
/// clickable.
final class DragRegionView: NSView {
    override func mouseDown(with event: NSEvent) {
        window?.performDrag(with: event)
    }
}

@MainActor
final class MainWindowController: NSObject, BridgeHost {
    let window: FiddleWindow
    private(set) var bridge: FiddleBridge!
    let controller: FiddleController
    /// Wired by the app delegate (which owns the Sparkle updater) so the About
    /// overlay's "Check for Updates" button can trigger an update check.
    var onCheckForUpdates: (() -> Void)?
    private let log = Logger(subsystem: "edu.umontana.fiddle", category: "window")
    private weak var hostedWebView: WKWebView?

    // Initial size; replaced by the measured shell size once the UI loads.
    private static let initialSize = NSSize(width: 844, height: 660)

    init(controller: FiddleController) {
        self.controller = controller
        // A titled window with a hidden, transparent title bar and full-size
        // content. Pure .borderless windows mis-route mouse/keyboard events to
        // hosted views (hover works but clicks are dropped); this style looks
        // identical (the web chrome draws its own ? / - / x orbs) but delivers
        // events correctly.
        window = FiddleWindow(
            contentRect: NSRect(origin: .zero, size: Self.initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        super.init()

        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false            // the shell draws its own drop shadow
        // Dragging is provided by an explicit handle (below), not the whole
        // background, so the web view keeps every click.
        window.isMovableByWindowBackground = false
        window.collectionBehavior = [.fullScreenNone, .managed]

        bridge = FiddleBridge(host: self)
        bridge.controller = controller
        controller.addSink(bridge)

        let bounds = NSRect(origin: .zero, size: Self.initialSize)
        let container = NSView(frame: bounds)

        let webView = bridge.webView
        webView.frame = bounds
        webView.autoresizingMask = [.width, .height]
        container.addSubview(webView)

        // Top-left drag handle, anchored to the top of the window.
        let handleHeight: CGFloat = 90
        let handleWidth: CGFloat = 290
        let dragHandle = DragRegionView(frame: NSRect(
            x: 0, y: bounds.height - handleHeight, width: handleWidth, height: handleHeight
        ))
        dragHandle.autoresizingMask = [.maxXMargin, .minYMargin]   // stay pinned top-left
        container.addSubview(dragHandle)

        window.contentView = container
        window.center()
    }

    func show() {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - BridgeHost

    func performWindowAction(_ action: WindowAction) {
        switch action {
        case .minimize:
            window.miniaturize(nil)
        case .close:
            // Hide rather than destroy: the menu bar item keeps Fiddle running.
            // Quit lives in the MenuBarExtra menu.
            window.orderOut(nil)
        case .help:
            if let url = URL(string: "https://github.com/umzcio/fiddle") {
                NSWorkspace.shared.open(url)
            }
        case .fit:
            fitToContent()
        case .checkForUpdates:
            onCheckForUpdates?()
        default:
            break
        }
    }

    /// Re-measure the rendered web shell and resize + center the window to fit.
    /// Called on initial load and whenever the web layout changes size (e.g. the
    /// Simple/Advanced switch), via the `fit` window action.
    func fitToContent() {
        guard let webView = hostedWebView else { return }
        // Measure the rendered shell itself (not the document, whose width is
        // pinned to the viewport and so never shrinks when the shell does), plus
        // the body padding that gives the shell's drop shadow room to render.
        let js = """
        (function(){
          var s=document.querySelector('.shell');
          if(!s) return JSON.stringify({w:0,h:0});
          var r=s.getBoundingClientRect();
          var cs=getComputedStyle(document.body);
          var pl=parseFloat(cs.paddingLeft)||0, pr=parseFloat(cs.paddingRight)||0;
          var pt=parseFloat(cs.paddingTop)||0, pb=parseFloat(cs.paddingBottom)||0;
          return JSON.stringify({w:Math.ceil(r.width+pl+pr), h:Math.ceil(r.height+pt+pb)});
        })()
        """
        webView.evaluateJavaScript(js) { [weak self] result, _ in
            guard
                let self,
                let json = result as? String,
                let data = json.data(using: .utf8),
                let size = try? JSONDecoder().decode([String: Double].self, from: data),
                let width = size["w"], let height = size["h"],
                width > 100, height > 100
            else { return }
            let newSize = NSSize(width: width, height: height)
            var frame = self.window.frame
            frame.size = newSize
            self.window.setFrame(frame, display: true, animate: false)
            self.window.center()
        }
    }

    /// Resize the borderless window to fit the rendered web shell exactly, so
    /// there is no empty chrome around it, then center it on screen.
    func webViewDidLoad(_ webView: WKWebView) {
        hostedWebView = webView
        fitToContent()
    }
}
