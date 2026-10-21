import Carbon.HIToolbox
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
    OpenedDocuments.register(messenger)
    AppQuit.register(messenger)
    QuickSearch.register(messenger, window: self)
    // Finder's Hizmetler › "Folio'da aç", and the iPhone as a scanner.
    NSApp.servicesProvider = FolioServices.shared
    NSUpdateDynamicServices()
    ContinuityScan.addMenu()

    super.awakeFromNib()
  }

  /// The window takes a picture or a PDF from the iPhone (Continuity
  /// Camera); see the NSServicesMenuRequestor extension below.
  override func validRequestor(
    forSendType sendType: NSPasteboard.PasteboardType?,
    returnType: NSPasteboard.PasteboardType?
  ) -> Any? {
    if sendType == nil, let type = returnType,
      type == .pdf || NSImage.imageTypes.contains(type.rawValue)
    {
      return self
    }
    return super.validRequestor(forSendType: sendType, returnType: returnType)
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
  /// Folio made the app Finder opens [extensions] with (Ayarlar ›
  /// Varsayılan önizleyici); the extensions it could not be made for.
  static func setDefaultViewer(_ extensions: [String], result: @escaping FlutterResult) {
    let app = Bundle.main.bundleURL
    let group = DispatchGroup()
    let lock = NSLock()
    var failed: [String] = []
    for ext in extensions {
      guard let type = UTType(filenameExtension: ext) else {
        failed.append(ext)
        continue
      }
      group.enter()
      NSWorkspace.shared.setDefaultApplication(at: app, toOpen: type) { error in
        if error != nil {
          lock.lock()
          failed.append(ext)
          lock.unlock()
        }
        group.leave()
      }
    }
    group.notify(queue: .main) { result(failed) }
  }

  static func register(_ messenger: FlutterBinaryMessenger, view: NSView) {
    let channel = FlutterMethodChannel(
      name: "lifeos_evrak/file_actions", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      if call.method == "shareMany" {
        let paths = (call.arguments as? [String: Any])?["paths"] as? [String] ?? []
        let picker = NSSharingServicePicker(items: paths.map { URL(fileURLWithPath: $0) })
        picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        result(nil)
        return
      }
      if call.method == "setDefaultViewer" {
        let extensions = (call.arguments as? [String: Any])?["extensions"] as? [String] ?? []
        setDefaultViewer(extensions, result: result)
        return
      }
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


/// Finder's Hizmetler menu, "Folio'da aç" (Info.plist, NSServices): the
/// files chosen opened in Folio, as "Birlikte Aç" would.
final class FolioServices: NSObject {
  static let shared = FolioServices()

  @objc func openInFolio(
    _ pboard: NSPasteboard, userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    let urls =
      pboard.readObjects(
        forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
      as? [URL] ?? []
    OpenedDocuments.receive(urls.map { $0.path })
    NSApp.activate(ignoringOtherApps: true)
  }

  /// "Folio ile önizle" and "Folio ile düzenle", as Windows's and Linux's
  /// right-click menus have them: Folio started again with --preview (a
  /// window of its own) or --edit (Folio's own window, handed on to the one
  /// open, lib/services/desktop/desktop_instance.dart).
  @objc func previewInFolio(
    _ pboard: NSPasteboard, userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    for path in files(pboard) { launch(["--preview", path]) }
  }

  @objc func editInFolio(
    _ pboard: NSPasteboard, userData: String,
    error: AutoreleasingUnsafeMutablePointer<NSString>
  ) {
    if let path = files(pboard).first { launch(["--edit", "--", path]) }
  }

  private func files(_ pboard: NSPasteboard) -> [String] {
    (pboard.readObjects(
      forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
      as? [URL] ?? []).map { $0.path }
  }

  private func launch(_ arguments: [String]) {
    guard let executable = Bundle.main.executableURL else { return }
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    try? process.run()
  }
}

/// The iPhone or iPad as Folio's camera (Continuity Camera): Dosya ›
/// "iPhone veya iPad'den tara" takes a photo or scans pages on the phone,
/// and what comes is kept in Belgeler/Folio Taramalar and opened.
enum ContinuityScan {
  static func addMenu() {
    guard let main = NSApp.mainMenu else { return }
    let file = NSMenuItem(title: "Dosya", action: nil, keyEquivalent: "")
    let menu = NSMenu(title: "Dosya")
    let scan = NSMenuItem(
      title: "iPhone veya iPad'den tara", action: nil, keyEquivalent: "")
    scan.identifier = NSMenuItem.importFromDeviceIdentifier
    menu.addItem(scan)
    file.submenu = menu
    main.insertItem(file, at: min(1, main.numberOfItems))
  }

  /// [data] kept as a scan of its own name; its path.
  static func keep(_ data: Data, ext: String) -> String? {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
    guard let base = docs.first else { return nil }
    let folder = base.appendingPathComponent("Folio Taramalar", isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let stamp = DateFormatter()
    stamp.dateFormat = "yyyy-MM-dd HH.mm.ss"
    let url = folder.appendingPathComponent("Tarama \(stamp.string(from: Date())).\(ext)")
    do {
      try data.write(to: url)
      return url.path
    } catch {
      return nil
    }
  }
}

extension MainFlutterWindow: NSServicesMenuRequestor {
  func readSelection(from pboard: NSPasteboard) -> Bool {
    var path: String?
    if let pdf = pboard.data(forType: .pdf) {
      path = ContinuityScan.keep(pdf, ext: "pdf")
    } else if let image = NSImage(pasteboard: pboard),
      let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.85])
    {
      path = ContinuityScan.keep(jpeg, ext: "jpg")
    }
    guard let path else { return false }
    OpenedDocuments.receive([path])
    return true
  }

  func writeSelection(to pboard: NSPasteboard, types: [NSPasteboard.PasteboardType]) -> Bool {
    false
  }
}

/// The quick search's shortcut on a Mac, what linux/runner/quick_search.cc
/// and windows/runner/quick_search.cpp do there: a system-wide hot key
/// (Carbon's RegisterEventHotKey, which needs no accessibility permission),
/// told to Dart as "activated" (lib/services/desktop/global_shortcut.dart).
enum QuickSearch {
  static var channel: FlutterMethodChannel?
  private static var hotKey: EventHotKeyRef?
  private static var handler: EventHandlerRef?

  static func register(_ messenger: FlutterBinaryMessenger, window: NSWindow) {
    let channel = FlutterMethodChannel(
      name: "com.erkanoz.folio/quick_search", binaryMessenger: messenger)
    self.channel = channel
    channel.setMethodCallHandler { [weak window] call, result in
      switch call.method {
      case "register":
        let args = call.arguments as? [String: Any] ?? [:]
        guard let code = keyCode(args["key"] as? String ?? "") else {
          result(FlutterError(code: "KEY", message: "Kısayol tuşu desteklenmiyor.", details: nil))
          return
        }
        unregister()
        installHandler()
        let bits = args["modifiers"] as? Int ?? 0
        var modifiers: UInt32 = 0
        if bits & 1 != 0 { modifiers |= UInt32(controlKey) }
        if bits & 2 != 0 { modifiers |= UInt32(optionKey) }
        if bits & 4 != 0 { modifiers |= UInt32(shiftKey) }
        if bits & 8 != 0 { modifiers |= UInt32(cmdKey) }
        // "FOLI": the hot key's own signature.
        let id = EventHotKeyID(signature: OSType(0x464F_4C49), id: 1)
        let status = RegisterEventHotKey(
          code, modifiers, id, GetApplicationEventTarget(), 0, &hotKey)
        if status == noErr {
          result(nil)
        } else {
          result(FlutterError(
            code: "HOTKEY", message: "Bu tuş birleşimi başka bir uygulamada kullanılıyor.",
            details: nil))
        }
      case "unregister":
        unregister()
        result(nil)
      case "activate":
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
        result(nil)
      case "parentWindow":
        result("")
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func installHandler() {
    guard handler == nil else { return }
    var spec = EventTypeSpec(
      eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
    InstallEventHandler(
      GetApplicationEventTarget(),
      { _, _, _ in
        DispatchQueue.main.async {
          QuickSearch.channel?.invokeMethod("activated", arguments: nil)
        }
        return noErr
      }, 1, &spec, nil, &handler)
  }

  private static func unregister() {
    if let hotKey {
      UnregisterEventHotKey(hotKey)
      self.hotKey = nil
    }
  }

  /// The key Dart names ("space", a letter, a digit, "F1"…"F12").
  private static func keyCode(_ key: String) -> UInt32? {
    let codes: [String: Int] = [
      "space": kVK_Space,
      "a": kVK_ANSI_A, "b": kVK_ANSI_B, "c": kVK_ANSI_C, "d": kVK_ANSI_D, "e": kVK_ANSI_E,
      "f": kVK_ANSI_F, "g": kVK_ANSI_G, "h": kVK_ANSI_H, "i": kVK_ANSI_I, "j": kVK_ANSI_J,
      "k": kVK_ANSI_K, "l": kVK_ANSI_L, "m": kVK_ANSI_M, "n": kVK_ANSI_N, "o": kVK_ANSI_O,
      "p": kVK_ANSI_P, "q": kVK_ANSI_Q, "r": kVK_ANSI_R, "s": kVK_ANSI_S, "t": kVK_ANSI_T,
      "u": kVK_ANSI_U, "v": kVK_ANSI_V, "w": kVK_ANSI_W, "x": kVK_ANSI_X, "y": kVK_ANSI_Y,
      "z": kVK_ANSI_Z,
      "0": kVK_ANSI_0, "1": kVK_ANSI_1, "2": kVK_ANSI_2, "3": kVK_ANSI_3, "4": kVK_ANSI_4,
      "5": kVK_ANSI_5, "6": kVK_ANSI_6, "7": kVK_ANSI_7, "8": kVK_ANSI_8, "9": kVK_ANSI_9,
      "F1": kVK_F1, "F2": kVK_F2, "F3": kVK_F3, "F4": kVK_F4, "F5": kVK_F5, "F6": kVK_F6,
      "F7": kVK_F7, "F8": kVK_F8, "F9": kVK_F9, "F10": kVK_F10, "F11": kVK_F11,
      "F12": kVK_F12,
    ]
    return codes[key].map { UInt32($0) }
  }
}
