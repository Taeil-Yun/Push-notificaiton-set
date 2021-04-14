import UIKit
import Flutter
import UserNotifications

// Send iOS token to flutter
var myToken:String?

@available(iOS 10.0, *)
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // notification 권한 설정
    func registerForPushNotifications() {
      UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
          print("Permission granted: \(granted)")
        }
    }
    registerForPushNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    
    // APNs Get Token
    UIApplication.shared.registerForRemoteNotifications()
    
    // Send iOS Token to Flutter
    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let tokenChannel = FlutterMethodChannel(name: "dholic.flutter.apns/token", binaryMessenger: controller as! FlutterViewController as! FlutterBinaryMessenger)
    
    // Send iOS Token to Flutter
    tokenChannel.setMethodCallHandler({
        (call: FlutterMethodCall, result: FlutterResult) -> Void in
        // token 처리
        guard call.method == "getAPNsToken" else {
            result(FlutterMethodNotImplemented)
            return
        }
        self.receiveAPNsToken(result: result)
    })

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
    
  // 앱이 foreground상태 일 때, 알림이 온 경우 처리
  override func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {

            // 푸시가 오면 alert, badge, sound표시를 하라는 의미
            completionHandler([.alert, .badge, .sound])
    }

  // push가 온 경우 처리
  override func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {

            // deep link처리 시 아래 url값 가지고 처리
        let userInfo = response.notification.request.content.userInfo
                print("url = \(userInfo)")
        
        if let aps = userInfo["aps"] as? NSDictionary {
            if (aps["url"] as? NSDictionary) != nil {}
            else if (aps["url"] as? NSString) != nil {
                UIApplication.shared.open(URL(string : aps["url"] as! String)!, options: [:], completionHandler: { (status) in
                    })
            }
        }

            // if url.containts("receipt")...
    }
    
  // APNs Get Token
  override func application(_ application: UIApplication,
                didRegisterForRemoteNotificationsWithDeviceToken
                    deviceToken: Data) {
    let tokenString = deviceToken.reduce("", {$0 + String(format: "%02X", $1)})
        print("token \(tokenString.lowercased())")
    // Send iOS Token to Flutter
    if tokenString != nil {
        myToken = tokenString
    }
    
  // APNs Get Token
  override func application(_ application: UIApplication,
                didFailToRegisterForRemoteNotificationsWithError
                    error: Error) {
       // Try again later.
    }
    
    // Send iOS token to Flutter
    private func receiveAPNsToken(result: FlutterResult) {
        if myToken == nil {
            result(FlutterError(code: "UNAVAILBLE", message: "null", details: nil))
        } else {
            result(String("\(myToken)"))
        }
    }
}
