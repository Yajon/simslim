import AppKit
import SwiftUI
import WebKit

/// A sheet that shows the bundled About.html in the system WebKit view, with a
/// native footer so the copyright link always stays visible while the page
/// scrolls. Links inside the page are handed to the default browser by the
/// navigation delegate below.
struct AboutView: View {
  @Environment(\.dismiss) private var dismiss
  @State private var copyrightIsHovered = false

  private static let homePageURL = URL(string: "https://yajon.github.io/")

  var body: some View {
    VStack(spacing: 0) {
      header
      Divider()
      page
      Divider()
      footer
    }
    .frame(
      minWidth: 680, idealWidth: 780, maxWidth: 920,
      minHeight: 520, idealHeight: 660, maxHeight: 820)
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var header: some View {
    HStack(spacing: 10) {
      Image(nsImage: NSApplication.shared.applicationIconImage)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
        .frame(width: 24, height: 24)
      Text(tr("About SimSlim"))
        .font(.headline)
      Spacer()
      Button(tr("Close")) { dismiss() }
        .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 11)
    .background(.bar)
  }

  private var page: some View {
    Group {
      if Bundle.main.url(forResource: "About", withExtension: "html") != nil {
        AboutWebView()
      } else {
        VStack(spacing: 8) {
          Image(systemName: "exclamationmark.triangle")
            .font(.title2)
          Text(tr("About page is unavailable"))
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      }
    }
  }

  private var footer: some View {
    HStack {
      Spacer()
      Button {
        if let url = Self.homePageURL {
          NSWorkspace.shared.open(url)
        }
      } label: {
        Text(tr("Copyright © %d GuoYanjun", currentYear))
          .font(.caption)
          .foregroundStyle(copyrightIsHovered ? Color.accentColor : Color.secondary)
      }
      .buttonStyle(.plain)
      .modifier(PointingHandCursor())
      .onHover { copyrightIsHovered = $0 }
      .help(tr("Open in your browser"))
      Spacer()
    }
    .padding(.vertical, 10)
    .background(.bar)
  }

  private var currentYear: Int {
    Calendar.current.component(.year, from: Date())
  }
}

/// Pushes the pointing-hand cursor only once per hover so a stray exit cannot
/// unbalance AppKit's cursor stack.
struct PointingHandCursor: ViewModifier {
  @State private var isPushed = false

  func body(content: Content) -> some View {
    content.onHover { inside in
      if inside, !isPushed {
        NSCursor.pointingHand.push()
        isPushed = true
      } else if !inside, isPushed {
        NSCursor.pop()
        isPushed = false
      }
    }
  }
}

private struct AboutWebView: NSViewRepresentable {
  func makeNSView(context: Context) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    // About.html defaults to Chinese; the injected language switches its copy
    // to match the language this UI was built with (see Localization.swift).
    let languageScript = WKUserScript(
      source: "window.SIMSLIM_LANG = '\(Localization.shared.language.rawValue)';",
      injectionTime: .atDocumentStart,
      forMainFrameOnly: true)
    configuration.userContentController.addUserScript(languageScript)

    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = context.coordinator
    if let url = Bundle.main.url(forResource: "About", withExtension: "html") {
      webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }
    return webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}

  func makeCoordinator() -> Coordinator { Coordinator() }

  final class Coordinator: NSObject, WKNavigationDelegate {
    func webView(
      _ webView: WKWebView,
      decidePolicyFor navigationAction: WKNavigationAction,
      decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
      guard
        navigationAction.navigationType == .linkActivated,
        let url = navigationAction.request.url,
        let scheme = url.scheme?.lowercased(),
        scheme == "http" || scheme == "https"
      else {
        decisionHandler(.allow)
        return
      }
      NSWorkspace.shared.open(url)
      decisionHandler(.cancel)
    }
  }
}
