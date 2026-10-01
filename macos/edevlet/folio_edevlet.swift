// LifeOS Folio — e-Devlet ile UYAP girişi için tarayıcı penceresi (macOS).
//
// linux/edevlet/folio_edevlet.c'nin Mac karşılığı; Folio ikisini aynı
// biçimde çağırır. Sistemin WebKit'i ayrı bir süreçte, ayrı bir pencerede
// çalışır; geçici veri deposu sayesinde diske hiçbir çerez yazılmaz.
//
// Kullanıcı e-Devlet'te mobil imza ya da e-imza ile onaylayınca e-Devlet
// UYAP'ın dönüş adresine yönlendirir; bu yönlendirme YÜKLENMEDEN durdurulur
// ve içindeki kod Folio'ya verilir. Kodu UYAP'a, oturumun sahibi olan Folio
// götürür.
//
// Protokol (stdout):  kod=<oauth kodu>\n
// Çıkış kodları:  0 kod alındı | 2 kullanıcı vazgeçti | 64 hatalı parametre
//
// GÜVENLİK: dönüş adresi kodu taşır. Tam adres hiçbir günlüğe yazılmaz;
// kod yalnız stdout borusundan Folio'ya gider.
import AppKit
import WebKit

func argument(_ name: String) -> String? {
  let args = CommandLine.arguments
  guard let at = args.firstIndex(of: name), at + 1 < args.count else { return nil }
  return args[at + 1]
}

guard let address = argument("--url"), let page = URL(string: address),
  let redirect = argument("--redirect"), !redirect.isEmpty
else {
  FileHandle.standardError.write("folio-edevlet: --url ve --redirect gerekir.\n".data(using: .utf8)!)
  exit(64)
}
let hint = argument("--hint") ?? ""

final class Login: NSObject, NSApplicationDelegate, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
  var got = false
  var window: NSWindow!
  var view: WKWebView!

  func applicationDidFinishLaunching(_ notification: Notification) {
    let configuration = WKWebViewConfiguration()
    // Geçici depo: ortak bir bilgisayarda bir önceki kişinin e-Devlet
    // oturumu kalmaz.
    configuration.websiteDataStore = .nonPersistent()
    view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = self
    view.uiDelegate = self

    let stack = NSStackView()
    stack.orientation = .vertical
    stack.spacing = 0
    stack.alignment = .leading
    if !hint.isEmpty {
      let label = NSTextField(wrappingLabelWithString: hint)
      let pad = NSStackView(views: [label])
      pad.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 12)
      stack.addArrangedSubview(pad)
      pad.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
    }
    stack.addArrangedSubview(view)
    view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true

    window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 560, height: 720),
      styleMask: [.titled, .closable, .resizable, .miniaturizable],
      backing: .buffered, defer: false)
    window.title = "e-Devlet ile UYAP girişi"
    window.contentView = stack
    window.delegate = self
    window.level = .floating
    window.center()
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    view.load(URLRequest(url: page))
  }

  /// True when [url] is the return address and its code was handed over.
  func take(_ url: URL?) -> Bool {
    guard !got, let url, url.absoluteString.hasPrefix(redirect),
      let code = URLComponents(url: url, resolvingAgainstBaseURL: false)?
        .queryItems?.first(where: { $0.name == "code" })?.value,
      !code.isEmpty
    else { return false }
    got = true
    FileHandle.standardOutput.write("kod=\(code)\n".data(using: .utf8)!)
    DispatchQueue.main.async { NSApp.terminate(nil) }
    return true
  }

  // Every navigation, a server redirect included, is asked about first: the
  // return address is stopped here, before its request leaves.
  func webView(
    _ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
    decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
  ) {
    decisionHandler(take(action.request.url) ? .cancel : .allow)
  }

  // e-Devlet's e-imza page opens its help in a new window; it goes to the
  // system's browser rather than nowhere.
  func webView(
    _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
    for action: WKNavigationAction, windowFeatures: WKWindowFeatures
  ) -> WKWebView? {
    if let url = action.request.url, !take(url) { NSWorkspace.shared.open(url) }
    return nil
  }

  func windowWillClose(_ notification: Notification) { NSApp.terminate(nil) }

  func applicationWillTerminate(_ notification: Notification) {
    exit(got ? 0 : 2)
  }
}

let app = NSApplication.shared
let login = Login()
app.delegate = login
// A window of its own with a Dock icon while it is open, though it is not
// an app bundle.
app.setActivationPolicy(.regular)
app.run()
