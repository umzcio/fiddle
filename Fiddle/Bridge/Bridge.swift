//
//  Bridge.swift
//  Fiddle
//
//  The WKWebView side of the typed contract in Protocol.swift. It owns the web
//  view, registers the "fiddle" message handler, decodes inbound Commands, and
//  emits Events back to the page. Window-chrome actions go to the host; every
//  other command is forwarded to the FiddleController.
//

import Foundation
import WebKit
import os

// A weak-forwarding proxy to break the retain cycle between
// WKUserContentController (which strongly retains message handlers) and
// FiddleBridge (which owns the WKWebView). Without this, the cycle is
// bridge -> webView -> configuration -> userContentController -> bridge.
private final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    nonisolated func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// What the bridge needs from its host window.
@MainActor
protocol BridgeHost: AnyObject {
    func performWindowAction(_ action: WindowAction)
    func webViewDidLoad(_ webView: WKWebView)
}

@MainActor
final class FiddleBridge: NSObject {
    let webView: WKWebView
    weak var host: BridgeHost?

    /// The engine coordinator. Window actions are handled by the host; every
    /// other command is forwarded here.
    weak var controller: FiddleController?

    private let log = Logger(subsystem: "edu.umontana.fiddle", category: "bridge")

    init(host: BridgeHost?, surface: String? = nil) {
        self.host = host

        let configuration = WKWebViewConfiguration()
        let controller = WKUserContentController()
        let version = (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
        var boot = "window.__fiddleVersion = '\(version)';"
        if let surface {
            boot += " window.__fiddleSurface = '\(surface)';"
        }
        controller.addUserScript(WKUserScript(source: boot, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        configuration.userContentController = controller

        let webView = FiddleWebView(frame: .zero, configuration: configuration)
        self.webView = webView
        super.init()

        controller.add(WeakScriptMessageHandler(self), name: Bridge.handlerName)
        webView.navigationDelegate = self
        // Transparent background so the rounded shell shows through the
        // borderless window. drawsBackground has no public setter.
        webView.setValue(false, forKey: "drawsBackground")

        loadUI()
    }

    private func loadUI() {
        guard let index = Bundle.main.url(forResource: "index", withExtension: "html", subdirectory: "web") else {
            log.error("web/index.html not found in bundle")
            return
        }
        let webDir = index.deletingLastPathComponent()
        webView.loadFileURL(index, allowingReadAccessTo: webDir)
    }

    /// Send an Event to the page.
    func emit(_ event: Event) {
        guard let js = try? Bridge.script(for: event) else {
            log.error("failed to encode event")
            return
        }
        webView.evaluateJavaScript(js, completionHandler: nil)
    }

    // MARK: - Command routing

    private func route(_ command: Command) {
        // Window chrome is the window host's job; everything else is the engine's.
        if case .window(let action) = command {
            host?.performWindowAction(action)
            return
        }
        controller?.handle(command, from: self)
    }
}

// MARK: - EngineEventSink

extension FiddleBridge: EngineEventSink {}

// MARK: - WKScriptMessageHandler

extension FiddleBridge: WKScriptMessageHandler {
    nonisolated func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        let body = message.body
        Task { @MainActor in
            do {
                route(try Bridge.decodeCommand(from: body))
            } catch {
                log.error("bad command: \(String(describing: error), privacy: .public)")
                emit(.error(message: "Bad command from UI"))
            }
        }
    }
}

// MARK: - WKNavigationDelegate

extension FiddleBridge: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        host?.webViewDidLoad(webView)
    }
}
