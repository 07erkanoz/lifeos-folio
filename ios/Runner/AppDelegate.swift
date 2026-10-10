import Flutter
import PDFKit
import UIKit
import UniformTypeIdentifiers
import UserNotifications
import VisionKit
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // UYAP's notifications shown while Folio is open, too
    // (flutter_local_notifications).
    UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    // The background check for new UYAP notifications (BackgroundNotices):
    // its plugins, and its task, as Info.plist names it.
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "com.erkanoz.evrak_convert.uyapNotices",
      earliestBeginInSeconds: NSNumber(value: 15 * 60))
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FolioFileActions") {
      FileActions.register(registrar.messenger())
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "FolioDocuments") {
      FolioDocuments.register(with: registrar)
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

/// What android/.../MainActivity.kt does for documents, the iPhone way:
/// a document another app opens in Folio ("Folio ile aç") is copied into
/// Folio's own Documents/Gelen and handed to Dart; a page scanned with the
/// camera (VisionKit's document camera, its edges found and straightened)
/// is made a PDF in Documents/Taramalar, which the Files app shows.
class FolioDocuments: NSObject, FlutterPlugin, FlutterSceneLifeCycleDelegate,
  VNDocumentCameraViewControllerDelegate, UIDocumentPickerDelegate
{
  static var shared: FolioDocuments?
  var channel: FlutterMethodChannel?
  var ready = false
  var waiting: [String] = []
  var scanning: FlutterResult?
  var picking: FlutterResult?

  /// The folders the lawyer chose, open for reading while Folio runs.
  var opened: [URL] = []

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FolioDocuments()
    shared = instance
    // Before Dart reads any of them: the folders chosen before, opened again.
    instance.restoreFolders()
    let channel = FlutterMethodChannel(
      name: "lifeos_evrak/documents", binaryMessenger: registrar.messenger())
    instance.channel = channel
    registrar.addMethodCallDelegate(instance, channel: channel)
    registrar.addSceneDelegate(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "ready":
      ready = true
      flush()
      result(nil)
    case "scan":
      scan(result)
    case "pickFolder", "pickPictureFolder":
      pickFolder(result)
    case "forgetFolder":
      forgetFolder(call.arguments as? String)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // A document opened in Folio from another app.

  @objc(scene:willConnectToSession:options:)
  func scene(
    _ scene: UIScene, willConnectTo session: UISceneSession,
    options connectionOptions: UIScene.ConnectionOptions?
  ) -> Bool {
    if let contexts = connectionOptions?.urlContexts, !contexts.isEmpty {
      receive(contexts.map { $0.url })
    }
    return false
  }

  @objc(scene:openURLContexts:)
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) -> Bool {
    receive(URLContexts.map { $0.url })
    return true
  }

  func receive(_ urls: [URL]) {
    let inbox = Self.folder("Gelen")
    for url in urls where url.isFileURL {
      let scoped = url.startAccessingSecurityScopedResource()
      defer { if scoped { url.stopAccessingSecurityScopedResource() } }
      let target = Self.unique(inbox, url.lastPathComponent)
      do {
        try FileManager.default.copyItem(at: url, to: target)
        waiting.append(target.path)
      } catch {
        channel?.invokeMethod("openError", arguments: "Belge açılamadı: \(error.localizedDescription)")
      }
    }
    flush()
  }

  func flush() {
    guard ready, !waiting.isEmpty else { return }
    let paths = waiting
    waiting = []
    channel?.invokeMethod("openFiles", arguments: paths)
  }

  // A folder to index or to show in the gallery, read where it is.
  //
  // A path alone opens nothing on an iPhone: a folder outside Folio's own
  // is read only while the access the picker granted is held, and only a
  // bookmark of it, kept, gets that access back when Folio runs again.

  static let bookmarksKey = "folio.folderBookmarks"

  func pickFolder(_ result: @escaping FlutterResult) {
    guard let top = FileActions.topController() else {
      result(FlutterError(code: "FOLDER", message: "Klasör seçici açılamadı.", details: nil))
      return
    }
    picking?(nil)
    picking = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder])
    picker.delegate = self
    picker.allowsMultipleSelection = false
    top.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else {
      picking?(nil)
      picking = nil
      return
    }
    guard url.startAccessingSecurityScopedResource() else {
      picking?(FlutterError(code: "FOLDER", message: "Bu klasörü okuma izni alınamadı.", details: nil))
      picking = nil
      return
    }
    opened.append(url)
    var marks = Self.bookmarks()
    if let data = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
      marks[url.path] = data
      UserDefaults.standard.set(marks, forKey: Self.bookmarksKey)
    }
    picking?(url.path)
    picking = nil
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    picking?(nil)
    picking = nil
  }

  func restoreFolders() {
    var kept: [String: Data] = [:]
    for (path, data) in Self.bookmarks() {
      var stale = false
      guard
        let url = try? URL(
          resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
      else { continue }
      if url.startAccessingSecurityScopedResource() { opened.append(url) }
      let fresh = stale
        ? (try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        : nil
      // Kept under the path Dart knows it by.
      kept[path] = fresh ?? data
    }
    UserDefaults.standard.set(kept, forKey: Self.bookmarksKey)
  }

  func forgetFolder(_ path: String?) {
    guard let path = path else { return }
    var marks = Self.bookmarks()
    marks.removeValue(forKey: path)
    UserDefaults.standard.set(marks, forKey: Self.bookmarksKey)
    opened.removeAll { url in
      if url.path == path {
        url.stopAccessingSecurityScopedResource()
        return true
      }
      return false
    }
  }

  static func bookmarks() -> [String: Data] {
    UserDefaults.standard.dictionary(forKey: bookmarksKey) as? [String: Data] ?? [:]
  }

  // The document camera.

  func scan(_ result: @escaping FlutterResult) {
    guard VNDocumentCameraViewController.isSupported, let top = FileActions.topController() else {
      result(FlutterError(code: "SCAN", message: "Bu cihazda belge tarayıcı yok.", details: nil))
      return
    }
    scanning = result
    let camera = VNDocumentCameraViewController()
    camera.delegate = self
    top.present(camera, animated: true)
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan
  ) {
    controller.dismiss(animated: true)
    let pdf = PDFDocument()
    for index in 0..<scan.pageCount {
      if let page = PDFPage(image: scan.imageOfPage(at: index)) {
        pdf.insert(page, at: pdf.pageCount)
      }
    }
    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH.mm"
    let target = Self.unique(Self.folder("Taramalar"), "Tarama \(formatter.string(from: Date())).pdf")
    if pdf.pageCount > 0, pdf.write(to: target) {
      scanning?(target.path)
    } else {
      scanning?(FlutterError(code: "SCAN", message: "Tarama kaydedilemedi.", details: nil))
    }
    scanning = nil
  }

  func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
    controller.dismiss(animated: true)
    scanning?(nil)
    scanning = nil
  }

  func documentCameraViewController(
    _ controller: VNDocumentCameraViewController, didFailWithError error: Error
  ) {
    controller.dismiss(animated: true)
    scanning?(FlutterError(code: "SCAN", message: error.localizedDescription, details: nil))
    scanning = nil
  }

  static func folder(_ name: String) -> URL {
    let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    let folder = documents.appendingPathComponent(name, isDirectory: true)
    try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    return folder
  }

  static func unique(_ folder: URL, _ name: String) -> URL {
    var target = folder.appendingPathComponent(name)
    let stem = (name as NSString).deletingPathExtension
    let ext = (name as NSString).pathExtension
    var n = 2
    while FileManager.default.fileExists(atPath: target.path) {
      target = folder.appendingPathComponent(ext.isEmpty ? "\(stem) (\(n))" : "\(stem) (\(n)).\(ext)")
      n += 1
    }
    return target
  }
}
