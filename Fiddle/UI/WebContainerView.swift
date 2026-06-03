//
//  WebContainerView.swift
//  Fiddle
//
//  SwiftUI wrapper around the bridge's WKWebView. The borderless main window
//  hosts the web view directly via AppKit for precise sizing, but this
//  representable is the supported way to embed the same live UI inside any
//  SwiftUI scene (for example a future settings window).
//

import SwiftUI
import WebKit

struct WebContainerView: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ nsView: WKWebView, context: Context) {}
}
