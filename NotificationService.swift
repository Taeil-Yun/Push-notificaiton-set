//
//  NotificationService.swift
//  NotificaitonServiceExtension
//
//  Created by 윤태일 on 2021/03/22.
//

import UserNotifications

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?

    override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)
        
        if let bestAttemptContent = bestAttemptContent {
            // Modify the notification content here...
            bestAttemptContent.title = "\(bestAttemptContent.title)"
            
            if let imageURLString = bestAttemptContent.userInfo["ImageUrl"] as? String {
                        if let imagePath = DownloadManager.image(imageURLString) {
                            let imageURL = URL(fileURLWithPath: imagePath)
                            do {
                                let attach = try UNNotificationAttachment(identifier: "image-test", url: imageURL, options: nil)
                                bestAttemptContent.attachments = [attach]
                            } catch {
                                print(error)
                            }
                        }
                    }
            
            contentHandler(bestAttemptContent)
        }
    }
    
    override func serviceExtensionTimeWillExpire() {
        // Called just before the extension will be terminated by the system.
        // Use this as an opportunity to deliver your "best attempt" at modified content, otherwise the original push payload will be used.
        if let contentHandler = contentHandler, let bestAttemptContent =  bestAttemptContent {
            contentHandler(bestAttemptContent)
        }
    }

}

open class DownloadManager: NSObject {
    open class func image(_ URLString: String) -> String? {
        let componet = URLString.components(separatedBy: "/")
        if let fileName = componet.last {
            let paths = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)
            if let documentsPath = paths.first {
                let filePath = documentsPath.appending("/" + fileName)
                if let imageURL = URL(string: URLString) {
                    do {
                        let data = try NSData(contentsOf: imageURL, options: NSData.ReadingOptions(rawValue: 0))
                        if data.write(toFile: filePath, atomically: true) {
                            return filePath
                        }
                    } catch {
                        print(error)
                    }
                }
            }
        }

        return nil
    }
}
