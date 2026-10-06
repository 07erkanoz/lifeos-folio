import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FolioFileActions") {
      FileActions.register(registrar.messenger())
    }
  }
}

/// What android/.../FileActions.kt does with a saved file, the iPhone way:
/// the share sheet, and "open in" another app. A copy is shared, never the
/// file in Folio's own folders.
enum FileActions {
  static var keep: FlutterMethodChannel?
  static var controller: UIDocumentInteractionController?

  static func register(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "lifeos_evrak/file_actions", binaryMessenger: messenger)
    keep = channel
    channel.setMethodCallHandler { call, result in
      let args = call.arguments as? [String: Any]
      switch call.method {
      case "share", "shareMany":
        let paths = call.method == "share"
          ? [args?["path"] as? String].compactMap { $0 }
          : (args?["paths"] as? [String] ?? [])
        let urls = paths.map { URL(fileURLWithPath: $0) }
          .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !urls.isEmpty, let top = topController() else {
          result(FlutterError(code: "FILE_ACTION", message: "Belge bulunamadı.", details: nil))
          return
        }
        let sheet = UIActivityViewController(activityItems: urls, applicationActivities: nil)
        if let pop = sheet.popoverPresentationController {
          pop.sourceView = top.view
          pop.sourceRect = CGRect(x: top.view.bounds.midX, y: top.view.bounds.maxY - 40, width: 1, height: 1)
          pop.permittedArrowDirections = []
        }
        top.present(sheet, animated: true)
        result(nil)
      case "openDefault", "openWith":
        guard let path = args?["path"] as? String, let top = topController() else {
          result(FlutterError(code: "FILE_ACTION", message: "Belge bulunamadı.", details: nil))
          return
        }
        let doc = UIDocumentInteractionController(url: URL(fileURLWithPath: path))
        controller = doc
        if !doc.presentOpenInMenu(from: top.view.bounds, in: top.view, animated: true) {
          result(FlutterError(code: "FILE_ACTION", message: "Bu belgeyi açacak uygulama bulunamadı.", details: nil))
          return
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  static func topController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var top = scenes.flatMap { $0.windows }.first { $0.isKeyWindow }?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }
}
