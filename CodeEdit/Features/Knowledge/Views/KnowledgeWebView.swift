//
//  KnowledgeWebView.swift
//  CodeEdit
//
//  A `WKWebView` that renders a knowledge page and routes in-pack navigation.
//

import SwiftUI
import WebKit

struct KnowledgeWebView: NSViewRepresentable {
    let html: String
    let baseURL: URL?
    let fragment: String?
    /// Called with a pack-relative path (+ optional `#fragment`) for in-pack links.
    let onNavigate: (String) -> Void
    /// Called for external links.
    let onExternal: (URL) -> Void

    func makeNSView(context: Context) -> WKWebView {
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.onNavigate = onNavigate
        context.coordinator.onExternal = onExternal

        if context.coordinator.lastHTML != html {
            context.coordinator.lastHTML = html
            context.coordinator.pendingFragment = fragment
            webView.loadHTMLString(html, baseURL: baseURL)
        } else if let fragment, fragment != context.coordinator.lastFragment {
            context.coordinator.scroll(to: fragment, in: webView)
        }
        context.coordinator.lastFragment = fragment
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, onExternal: onExternal)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigate: (String) -> Void
        var onExternal: (URL) -> Void
        var lastHTML: String?
        var lastFragment: String?
        var pendingFragment: String?

        init(onNavigate: @escaping (String) -> Void, onExternal: @escaping (URL) -> Void) {
            self.onNavigate = onNavigate
            self.onExternal = onExternal
        }

        func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction,
            decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
        ) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }

            if url.scheme == "ce-knowledge" {
                var path = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
                path = path.removingPercentEncoding ?? path
                if let fragment = url.fragment, !fragment.isEmpty {
                    path += "#" + (fragment.removingPercentEncoding ?? fragment)
                }
                onNavigate(path)
                decisionHandler(.cancel)
                return
            }

            if url.scheme == "http" || url.scheme == "https" {
                if navigationAction.navigationType == .linkActivated {
                    onExternal(url)
                    decisionHandler(.cancel)
                } else {
                    decisionHandler(.allow)
                }
                return
            }

            decisionHandler(.allow)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if let fragment = pendingFragment {
                pendingFragment = nil
                scroll(to: fragment, in: webView)
            }
        }

        func scroll(to fragment: String, in webView: WKWebView) {
            let escaped = fragment.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
            let script = "document.getElementById('\(escaped)')?.scrollIntoView();"
            webView.evaluateJavaScript(script, completionHandler: nil)
        }
    }
}
