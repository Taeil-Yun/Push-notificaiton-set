import UIKit
import Flutter

@available(iOS 10.0, *)
@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as? UNUserNotificationCenterDelegate
    }
    
    // APNs Get Token
    UIApplication.shared.registerForRemoteNotifications()

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
    
        // check the device token to server send
        let tokenRegistration = UserDefaults.standard.value(forKey: "TokenRegistState")
        if tokenRegistration == nil {
            guard let serverUrl = URL(string: "API") else {
                return      // 데이터를 보낼 서버 url
            }
            
            var request = URLRequest(url: serverUrl)
            request.httpMethod = "POST"     // POST 전송
            
            do {    // request body에 전송할 데이터
                request.httpBody = tokenString.lowercased().data(using: String.Encoding.utf8)
            } catch {
                print(error.localizedDescription)
            }
            
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.addValue("application/json", forHTTPHeaderField: "Accept-Type")
            
            let getSession = URLSession.shared
            getSession.dataTask(with: request, completionHandler: { (data, responds, error) in
                // 서버가 응답이 없거나 통신이 실패
                if let e = error {
                    NSLog("An error has occured: \(e.localizedDescription)")
                    return
                }
                print("전송완료")
            }).resume()
            
            UserDefaults.standard.set("tokenSendSuccess", forKey: "TokenRegistState")
        }
    }
  // APNs Get Token
  override func application(_ application: UIApplication,
                didFailToRegisterForRemoteNotificationsWithError
                    error: Error) {
       // Try again later.
    }
}
