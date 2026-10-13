import UIKit
import Flutter
import flutter_local_notifications
import app_links
import Security

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // This is required to make any communication available in the action isolate.
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }

    GeneratedPluginRegistrant.register(with: self)

    // The upload credential is device-local and excluded from Cashew exports.
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "cashew/miru-keychain", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { call, result in
        let query: [String: Any] = [
          kSecClass as String: kSecClassGenericPassword,
          kSecAttrService as String: (Bundle.main.bundleIdentifier ?? "cashew") + ".miru",
          kSecAttrAccount as String: "sync-configuration"
        ]
        if call.method == "read" {
          var readQuery = query
          readQuery[kSecReturnData as String] = true
          readQuery[kSecMatchLimit as String] = kSecMatchLimitOne
          var item: CFTypeRef?
          let status = SecItemCopyMatching(readQuery as CFDictionary, &item)
          if status == errSecItemNotFound { result(nil); return }
          guard status == errSecSuccess, let data = item as? Data,
                let value = String(data: data, encoding: .utf8) else {
            result(FlutterError(code: "keychain_read_failed", message: "Unable to read sync credential", details: nil)); return
          }
          result(value)
        } else if call.method == "write" {
          guard let value = call.arguments as? String, let data = value.data(using: .utf8) else {
            result(FlutterError(code: "invalid_configuration", message: nil, details: nil)); return
          }
          let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
          ]
          var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
          if status == errSecItemNotFound {
            var newItem = query
            for (key, value) in attributes { newItem[key] = value }
            status = SecItemAdd(newItem as CFDictionary, nil)
          }
          if status == errSecSuccess { result(nil) }
          else { result(FlutterError(code: "keychain_write_failed", message: "Unable to save sync credential", details: nil)) }
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
    }

    // Retrieve the link from parameters
    if let url = AppLinks.shared.getLink(launchOptions: launchOptions) {
      // We have a link, propagate it to your Flutter app or not
      AppLinks.shared.handleLink(url: url)
      return true // Returning true will stop the propagation to other packages
    }
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
