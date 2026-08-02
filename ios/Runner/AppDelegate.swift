import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Native side of the iCloud backup channel. Registers only when the root
    // Flutter view controller is available; if it isn't, Dart simply sees a
    // MissingPluginException and the app falls back to Google Drive.
    if let controller = window?.rootViewController as? FlutterViewController {
      ICloudBackup.register(with: controller.binaryMessenger)
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}

/// Reads and writes a single backup file in the app's iCloud ubiquity
/// container, behind the `com.nomail.nomail/icloud` MethodChannel.
///
/// Degrades safely: `FileManager.url(forUbiquityContainerIdentifier:)` returns
/// nil until the iCloud capability + container are enabled for the app in
/// Xcode (Signing & Capabilities) and the Apple Developer portal. Until then
/// `isAvailable` reports false, `read` returns nil, and `write` errors — the
/// Dart layer treats all three as "iCloud not set up" and uses Drive instead.
/// Enabling iCloud is therefore purely additive; nothing here needs to change.
enum ICloudBackup {
  static let channelName = "com.nomail.nomail/icloud"
  static let fileName = "nomail-backup.json"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: channelName, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "isAvailable":
        result(containerURL() != nil)
      case "read":
        result(read())
      case "write":
        guard let args = call.arguments as? [String: Any],
              let bytes = args["bytes"] as? FlutterStandardTypedData else {
          result(FlutterError(code: "bad_args", message: "Missing bytes", details: nil))
          return
        }
        write(bytes.data, result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private static func containerURL() -> URL? {
    // nil identifier → first container declared in the entitlement; nil result
    // means iCloud isn't enabled for this build.
    return FileManager.default.url(forUbiquityContainerIdentifier: nil)
  }

  private static func backupURL() -> URL? {
    guard let container = containerURL() else { return nil }
    let docs = container.appendingPathComponent("Documents", isDirectory: true)
    try? FileManager.default.createDirectory(
      at: docs, withIntermediateDirectories: true)
    return docs.appendingPathComponent(fileName)
  }

  private static func read() -> FlutterStandardTypedData? {
    guard let url = backupURL() else { return nil }
    var data: Data?
    var coordError: NSError?
    NSFileCoordinator().coordinate(
      readingItemAt: url, options: [], error: &coordError) { readURL in
      data = try? Data(contentsOf: readURL)
    }
    guard let bytes = data else { return nil }
    return FlutterStandardTypedData(bytes: bytes)
  }

  private static func write(_ data: Data, result: @escaping FlutterResult) {
    guard let url = backupURL() else {
      result(FlutterError(
        code: "unavailable",
        message: "iCloud isn't enabled for NoMail", details: nil))
      return
    }
    var writeError: Error?
    var coordError: NSError?
    NSFileCoordinator().coordinate(
      writingItemAt: url, options: .forReplacing, error: &coordError) { writeURL in
      do {
        try data.write(to: writeURL, options: .atomic)
      } catch {
        writeError = error
      }
    }
    if let error = coordError ?? (writeError as NSError?) {
      result(FlutterError(
        code: "write_failed", message: error.localizedDescription, details: nil))
    } else {
      result(nil)
    }
  }
}
