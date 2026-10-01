import Cocoa
import FlutterMacOS
import UniformTypeIdentifiers

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    let messenger = flutterViewController.engine.binaryMessenger
    RichClipboard.register(messenger)
    SpellCheck.register(messenger)
    FileActions.register(messenger, view: flutterViewController.view)

    super.awakeFromNib()
  }
}

/// The clipboard in the forms Word, LibreOffice and UYAP's editor put there,
/// as linux/runner/rich_clipboard.cc reads and writes them.
enum RichClipboard {
  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "lifeos_evrak/rich_clipboard", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "getRichData": result(read())
      case "setRichData":
        guard let args = call.arguments as? [String: Any] else {
          result(FlutterError(code: "clipboard_write", message: nil, details: nil))
          return
        }
        write(args)
        result(nil)
      case "getHtml":
        result(NSPasteboard.general.string(forType: .html))
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Every rich form on the clipboard; the Dart side picks the richest.
  static func read() -> [String: Any]? {
    let board = NSPasteboard.general
    var candidates: [[String: Any]] = []
    for type in board.types ?? [] {
      let name = type.rawValue
      // UYAP's editor is Java: its own flavour reaches the Mac clipboard
      // under a name that still carries the Java class.
      let uyap =
        name.contains("application/x-java-serialized-object")
        && name.contains("EditorDataFlavor")
      let html = type == .html
      let rtf = type == .rtf
      guard uyap || html || rtf, let data = board.data(forType: type) else { continue }
      candidates.append([
        "format": uyap ? "uyap" : html ? "html" : "rtf",
        "data": FlutterStandardTypedData(bytes: data),
        "mime": name,
      ])
    }
    return candidates.isEmpty ? nil : ["candidates": candidates]
  }

  static func write(_ args: [String: Any]) {
    let board = NSPasteboard.general
    board.clearContents()
    if let text = args["text"] as? String { board.setString(text, forType: .string) }
    if let html = args["html"] as? FlutterStandardTypedData {
      board.setData(html.data, forType: .html)
    }
    if let rtf = args["rtf"] as? FlutterStandardTypedData {
      board.setData(rtf.data, forType: .rtf)
    }
  }
}

/// Turkish spelling with the dictionary macOS itself has, the one every
/// other program on the Mac reads.
enum SpellCheck {
  static let checker = NSSpellChecker.shared

  static func turkish() -> String? {
    checker.availableLanguages.first { $0 == "tr" || $0.hasPrefix("tr_") || $0.hasPrefix("tr-") }
  }

  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "folio/spellcheck", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any] ?? [:]
      guard let language = turkish() else {
        result(call.method == "available" ? false : [])
        return
      }
      switch call.method {
      case "available": result(true)
      case "check":
        let text = args["text"] as? String ?? ""
        let length = (text as NSString).length
        var found: [[String: Any]] = []
        var at = 0
        while at < length {
          let range = checker.checkSpelling(
            of: text, startingAt: at, language: language, wrap: false,
            inSpellDocumentWithTag: 0, wordCount: nil)
          if range.location == NSNotFound || range.length == 0 { break }
          // Offsets in UTF-16 units, as the Dart string counts them.
          found.append(["start": range.location, "length": range.length, "repeated": false])
          at = range.location + range.length
        }
        result(found)
      case "suggest":
        let word = args["word"] as? String ?? ""
        let range = NSRange(location: 0, length: (word as NSString).length)
        result(
          checker.guesses(
            forWordRange: range, in: word, language: language, inSpellDocumentWithTag: 0)
            ?? [])
      case "add":
        if let word = args["word"] as? String { checker.learnWord(word) }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}

/// What linux/runner/file_actions.cc does with a saved file, the Mac way.
enum FileActions {
  static func register(_ messenger: FlutterBinaryMessenger, view: NSView) {
    let channel = FlutterMethodChannel(
      name: "lifeos_evrak/file_actions", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard let path = (call.arguments as? [String: Any])?["path"] as? String else {
        result(FlutterError(code: "file_action", message: "Belge bulunamadı.", details: nil))
        return
      }
      let url = URL(fileURLWithPath: path)
      switch call.method {
      case "openDefault":
        NSWorkspace.shared.open(url)
        result(nil)
      case "showFolder":
        NSWorkspace.shared.activateFileViewerSelecting([url])
        result(nil)
      case "copyFile":
        let board = NSPasteboard.general
        board.clearContents()
        board.writeObjects([url as NSURL])
        result(nil)
      case "openWith":
        // The Mac has no "open with" chooser to call; an application picked
        // from the Applications folder does the same.
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.prompt = "Aç"
        if panel.runModal() == .OK, let app = panel.url {
          NSWorkspace.shared.open(
            [url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
        }
        result(nil)
      case "share":
        let picker = NSSharingServicePicker(items: [url])
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        result(nil)
      case "email":
        if let mail = NSSharingService(named: .composeEmail), mail.canPerform(withItems: [url]) {
          mail.perform(withItems: [url])
          result(nil)
        } else {
          result(
            FlutterError(code: "file_action", message: "E-posta uygulaması bulunamadı.", details: nil))
        }
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
