import AppKit
import SwiftUI
import WebKit

struct DashboardView: View {
    var body: some View {
        DashboardWebView()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .ignoresSafeArea()
    }
}

struct DashboardWebView: NSViewRepresentable {
    func makeCoordinator() -> DashboardWebCoordinator {
        DashboardWebCoordinator()
    }

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = true
        config.defaultWebpagePreferences = prefs

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")

        loadDashboard(into: webView)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    private func loadDashboard(into webView: WKWebView) {
        guard let url = Bundle.main.url(forResource: "dashboard", withExtension: "html") else {
            let errorHTML = """
            <body style="font-family:system-ui;padding:40px;color:#666;">
                <h2>dashboard.html not found</h2>
                <p>Add <strong>dashboard.html</strong> to your app target resources.</p>
            </body>
            """
            webView.loadHTMLString(errorHTML, baseURL: nil)
            return
        }

        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
}

final class DashboardWebCoordinator: NSObject, WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "https" || scheme == "http" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }

        decisionHandler(.allow)
    }
}

#Preview {
    DashboardView()
        .frame(width: 1200, height: 820)
}
