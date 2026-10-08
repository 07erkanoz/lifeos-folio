import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  /// A document double-clicked in Finder, dropped on the Dock icon or sent
  /// with "Birlikte Aç": handed to Folio once it listens (OpenedDocuments).
  override func application(_ application: NSApplication, open urls: [URL]) {
    OpenedDocuments.receive(urls.filter { $0.isFileURL }.map { $0.path })
  }
}

/// The documents macOS asks Folio to open, on lib/services/platform/
/// document_intents.dart's channel: kept until Dart says it is ready, for a
/// document that opened Folio comes before Folio's window.
enum OpenedDocuments {
  static var channel: FlutterMethodChannel?
  static var ready = false
  static var waiting: [String] = []

  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(
      name: "lifeos_evrak/documents", binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "ready":
        ready = true
        flush()
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
  }

  static func receive(_ paths: [String]) {
    waiting.append(contentsOf: paths)
    flush()
  }

  static func flush() {
    guard ready, let channel, !waiting.isEmpty else { return }
    let paths = waiting
    waiting = []
    channel.invokeMethod("openFiles", arguments: paths)
  }
}
