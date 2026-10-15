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
    /// A search query to highlight in the page, if any.
    let highlight: String?
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
            context.coordinator.lastFragment = fragment
            context.coordinator.lastHighlight = highlight
            context.coordinator.pendingFragment = fragment
            context.coordinator.pendingHighlight = highlight
            webView.loadHTMLString(html, baseURL: baseURL)
            return
        }

        if let fragment, fragment != context.coordinator.lastFragment {
            context.coordinator.scroll(to: fragment, in: webView)
        }
        context.coordinator.lastFragment = fragment

        if context.coordinator.lastHighlight != highlight {
            context.coordinator.lastHighlight = highlight
            context.coordinator.applyHighlight(highlight, in: webView)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onNavigate: onNavigate, onExternal: onExternal)
    }

    final class Coordinator: NSObject, WKNavigationDelegate {
        var onNavigate: (String) -> Void
        var onExternal: (URL) -> Void
        var lastHTML: String?
        var lastFragment: String?
        var lastHighlight: String?
        var pendingFragment: String?
        var pendingHighlight: String?

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
            if let highlight = pendingHighlight {
                pendingHighlight = nil
                applyHighlight(highlight, in: webView)
            }
        }

        func scroll(to fragment: String, in webView: WKWebView) {
            let escaped = escapeForScript(fragment)
            webView.evaluateJavaScript(

                "document.getElementById('\\(escaped)')?.scrollIntoView();",

                completionHandler: nil

            )
        }

        func applyHighlight(_ query: String?, in webView: WKWebView) {
            let literal = query.map(jsStringLiteral) ?? "null"
            let script = """
            (function() {
              document.querySelectorAll('mark.kh').forEach(function(m) {
                m.replaceWith(document.createTextNode(m.textContent));
              });
              var q = \(literal);
              if (!q) { return; }
              var lower = q.toLowerCase();
              var walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT);
              var nodes = [];
              var node;
              while ((node = walker.nextNode())) { nodes.push(node); }
              nodes.forEach(function(node) {
                var text = node.nodeValue;
                var index = text.toLowerCase().indexOf(lower);
                if (index < 0) { return; }
                var fragment = document.createDocumentFragment();
                var start = 0;
                while (index >= 0) {
                  if (index > start) { fragment.appendChild(document.createTextNode(text.slice(start, index))); }
                  var mark = document.createElement('mark');
                  mark.className = 'kh';
                  mark.textContent = text.slice(index, index + q.length);
                  fragment.appendChild(mark);
                  start = index + q.length;
                  index = text.toLowerCase().indexOf(lower, start);
                }
                if (start < text.length) { fragment.appendChild(document.createTextNode(text.slice(start))); }
                node.parentNode.replaceChild(fragment, node);
              });
            })();
            """
            webView.evaluateJavaScript(script, completionHandler: nil)
        }

        private func escapeForScript(_ value: String) -> String {
            value.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
        }

        private func jsStringLiteral(_ value: String) -> String {
            let escaped = value
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "\n", with: "\\n")
            return "\"\(escaped)\""
        }
    }
}
