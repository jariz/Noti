//
//  PushManager.swift
//  Noti
//
//  Created by Jari on 23/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//
//  PushManager is in charge of maintaining the websocket, and dispatching user notifications when needed.
//

import Foundation
import Starscream
import SwiftyJSON
import Alamofire

class PushManager: NSObject, WebSocketDelegate {

    let token: String
    let socket: WebSocket
    let ephemeralService: EphemeralService
    let userService: UserService

    var user: User?
    var pushHistory = [JSON]()
    var crypt: Crypt?
    var killed = false
    
    init(token: String) {
        self.token = token
        self.socket = WebSocket(url: URL(string: "wss://stream.pushbullet.com/websocket/" + token)!)
        self.ephemeralService = EphemeralService(token: token)
        self.userService = UserService(token: token)

        super.init()

        self.setState(state: "Initializing...")
        
        NSUserNotificationCenter.default.delegate = self
        self.initCrypt()
        
        print("Getting user info...")

        self.refreshUser()
    }
    
    deinit {
        disconnect()
    }
    
    internal func disconnect() {
        //stops attempts to reconnect
        self.killed = true
        
        //disconnect now!
        self.socket.disconnect(forceTimeout: 0)
    }

    private func refreshUser() {
        userService.fetchUserInfo(success: { [weak self] user in
            self?.user = user
            self?.connect()
        }, failure: { [weak self] in
            self?.killed = true
            self?.disconnect()
            self?.setState(state: "Failed to log in.")
        })
    }
    
    func initCrypt() {
        if let keyData = UserDefaults.standard.object(forKey: "secureKey") as? Data {
            let key = keyData.toArray()
            self.crypt = Crypt(key: key)
            print("Encryption enabled!")
        } else {
            self.crypt = nil
            print("Encryption not enabled")
        }
        self.ephemeralService.crypt = self.crypt
    }
    
    func setState(state: String, image: NSImage? = nil, disabled: Bool? = nil) {
        var object:[String: AnyObject] = [
            "title": state as AnyObject
        ]
        if let image = image {
            object["image"] = image
        }
        if let disabled = disabled as AnyObject? {
            object["disabled"] = disabled
        }
        NotificationCenter.default.post(name: Notification.Name(rawValue: "StateChange"), object: object)
    }
    
    func connect() {
        socket.delegate = self
        socket.connect()
    }
    
    internal func websocketDidConnect(socket: WebSocket) {
        func applyState(name: String?, image: NSImage?) {
            if let name = name {
                self.setState(state: "Logged in as: \(name)", image: image, disabled: false)
            } else {
                self.setState(state: "Logged in", image: image, disabled: false)
            }
        }
        if let photo = self.user?.imageUrl {
            Alamofire.request(photo, method: .get)
                .responseData { [user = user] response in
                    applyState(name: user?.name, image: NSImage(data: response.result.value!))
            }
        } else {
            applyState(name: user?.name, image: nil)
        }
        
        
        print("PushManager", "Is connected")
    }
    
    internal func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        print("PushManager", "Is disconnected: \(error?.localizedDescription)")
        
        if(!self.killed) {
            print("Reconnecting in 5 sec")
            if let error = error {
                setState(state: "Disconnected: \(error.localizedFailureReason ?? error.localizedDescription), retrying...", disabled: true)
            }
            else {
                setState(state: "Disconnected, retrying...", disabled: true)
            }
            
            Timer.scheduledTimer(timeInterval: 5, target: BlockOperation(block: self.connect), selector: #selector(Operation.main), userInfo: nil, repeats: false)
        } else {
            print("Not going to reconnect: I'm killed")
            setState(state: "Disconnected. Please log in.", disabled: true)
        }
    }

    private func receivedTickle(message: JSON) {
        if let subtype = message["subtype"].string, subtype == "account" {
            self.refreshUser()
        }
    }

    private func receivedPush(socket: WebSocket, message: JSON) {
        let push = message["push"]
        var message = message
        pushHistory.append(push)

        if push["encrypted"].exists() && push["encrypted"].bool! {
            func warnUser() {
                let noti = NSUserNotification()
                noti.title = "I received data I couldn't understand!"
                noti.informativeText = "It appears you're using encryption, click open settings & set password."
                noti.actionButtonTitle = "Settings"
                noti.identifier = "noti_encrypt" + String(arc4random())
                NSUserNotificationCenter.default.deliver(noti)
            }

            if let crypt = self.crypt {
                let decrypted = crypt.decryptMessage(push["ciphertext"].string!)
                if let decrypted = decrypted {
                    message["push"] = JSON.parse(decrypted)
                    //handle decrypted message
                    websocketDidReceiveMessage(socket: socket, text: message.rawString()!)
                } else {
                    warnUser()
                }
            } else {
                warnUser()
            }

            return
        }

        if let pushType = push["type"].string {
            switch(pushType) {
            case "mirror":
                let userDefaults = UserDefaults.standard
                let notification = NSUserNotification()
                notification.otherButtonTitle = "Dismiss    "
                notification.actionButtonTitle = "Show"
                notification.title = push["title"].string
                notification.informativeText = push["body"].string
                notification.identifier = push["notification_id"].string
                let omitAppNameDefaultExists = userDefaults.object(forKey: "omitAppName") != nil
                let omitAppName = omitAppNameDefaultExists ? userDefaults.bool(forKey: "omitAppName") : false
                if !omitAppName {
                    notification.subtitle = push["application_name"].string
                }

                if let icon = push["icon"].string {

                    let data = Data(base64Encoded: icon, options: NSData.Base64DecodingOptions(rawValue: 0))!
                    let roundedImagesDefaultExists = userDefaults.object(forKey: "roundedImages") != nil
                    let roundedImages = roundedImagesDefaultExists ? userDefaults.bool(forKey: "roundedImages") : true
                    var img = NSImage(data: data)!
                    if roundedImages {
                        img = RoundedImage.create(Int(img.size.width) / 2, source: img)
                    }
                    notification.setValue(img, forKeyPath: "_identityImage")
                    notification.setValue(false, forKeyPath: "_identityImageHasBorder")
                }

                notification.setValue(true, forKeyPath: "_showsButtons")

                if push["conversation_iden"].exists() {
                    notification.hasReplyButton = true
                }

                if let actions = push["actions"].array {

                    if actions.count == 1 || self.user?.pro == false {
                        notification.actionButtonTitle = actions[0]["label"].string!
                    } else {
                        var titles = [String]()
                        for action in actions {
                            titles.append(action["label"].string!)
                        }
                        notification.actionButtonTitle = "Actions"
                        notification.setValue(true, forKeyPath: "_alwaysShowAlternateActionMenu")
                        notification.setValue(titles, forKeyPath: "_alternateActionButtonTitles")
                    }
                }

                let soundDefaultExists = userDefaults.object(forKey: "roundedImages") != nil
                let sound = soundDefaultExists ? userDefaults.string(forKey: "sound") : "Glass"

                notification.soundName = sound

                NSUserNotificationCenter.default.deliver(notification)
                break
            case "dismissal":
                //loop through current user notifications, if identifier matches, remove it
                for noti in NSUserNotificationCenter.default.deliveredNotifications {
                    if noti.identifier == push["notification_id"].string {
                        NSUserNotificationCenter.default.removeDeliveredNotification(noti)
                        print("Removed a noti (", noti.identifier!, ")")
                    }
                }
                var i = -1, indexToBeRemoved = -1
                for item in pushHistory {
                    i += 1
                    if push["notification_id"].string == item["notification_id"].string {
                        indexToBeRemoved = i
                        break
                    }
                }
                if indexToBeRemoved != -1 {
                    pushHistory.remove(at: indexToBeRemoved)
                }

                break
            case "sms_changed":
                if push["notifications"].exists() {
                    for sms in push["notifications"].array! {
                        let notification = NSUserNotification()

                        let threadId = sms["thread_id"].stringValue
                        let deviceId = push["source_device_iden"].stringValue

                        notification.title = "SMS from " + sms["title"].string!
                        notification.informativeText = sms["body"].string
                        notification.hasReplyButton = true
                        notification.identifier = "sms_" + deviceId + "|" + threadId + "|" + String(sms["timestamp"].int!)

                        notification.setValue(true, forKeyPath: "_showsButtons")

                        notification.soundName = "Glass"

                        if let photo = sms["image_url"].string {
                            Alamofire.request(photo, method: .get)
                                .responseData { response in
                                    notification.setValue(NSImage(data: response.result.value!), forKey: "_identityImage")
                                    NSUserNotificationCenter.default.deliver(notification)
                            }
                        } else {
                            NSUserNotificationCenter.default.deliver(notification)
                        }

                        NotificationCenter.default.post(name: Notification.Name("NewSMS-\(deviceId)"), object: nil, userInfo: ["threadId": threadId])
                    }
                }
                break
            default:
                print("Unknown type of push", pushType)
                break
            }
        }
    }

    internal func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        print("PushManager", "receive", text)

        var message = JSON.parse(text)

        if let type = message["type"].string {
            switch type {
            case "tickle":
                self.receivedTickle(message: message)
            case "push":
                self.receivedPush(socket: socket, message: message)
            default:
                print("Unknown type of message ", message["type"].string ?? "(null)")
            }
        }

    }

    func setPassword(password: String) {
        let iden = self.user!.iden
        let key = Crypt.generateKey(password, salt: iden)
        UserDefaults.standard.set(key, forKey: "secureKey")
    }

    func websocketDidReceiveData(socket: WebSocket, data: Data) {

    }
}

extension PushManager: NSUserNotificationCenterDelegate {

    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        switch notification.activationType {
        case .actionButtonClicked:
            self.actionButtonClicked(notification: notification)
        case .contentsClicked:
            self.contentsClicked(notification: notification)
        case .replied:
            self.replied(notification: notification)
        default:
            print("did not understand activation type", notification.activationType.rawValue)
        }
    }

    private func actionButtonClicked(notification: NSUserNotification) {
        var alternateAction = notification.value(forKey: "_alternateActionIndex") as! Int

        if (alternateAction == Int.max) {
            //user did not use an alternate action, set the index to 0
            alternateAction = 0
        }

        print("action")
        print("alternate?", alternateAction)

        for item in pushHistory {
            if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                if let actions = item["actions"].array {
                    ephemeralService.dismissPush(item, triggerKey: actions[alternateAction]["trigger_key"].string!)
                    break
                }
            }
        }
    }

    private func contentsClicked(notification: NSUserNotification) {
        //check if this is the encryption warning notification
        if notification.identifier?.characters.count ?? 0 > 12 {
            let index = notification.identifier!.characters.index(notification.identifier!.startIndex, offsetBy: 12)
            if notification.identifier?.substring(to: index) == "noti_encrypt" {
                return
            }
        }

        Alamofire.request("https://update.pushbullet.com/android_mapping.json", method: .get)
            .responseString { response in
                if let result = response.result.value {
                    let mapping = JSON.parse(result)

                    var indexToBeRemoved = -1, i = -1

                    for item in self.pushHistory {
                        i += 1
                        guard item["notification_id"].string == notification.identifier && item["type"].string == "mirror" else {
                            continue
                        }
                        if let url = mapping[item["package_name"].string!].string {
                            NSWorkspace.shared().open(URL(string: url)!)
                            for noti in NSUserNotificationCenter.default.deliveredNotifications {
                                if noti.identifier == item["notification_id"].string {
                                    NSUserNotificationCenter.default.removeDeliveredNotification(noti)
                                    print("Removed a noti (", noti.identifier!, ")")
                                }
                            }

                            indexToBeRemoved = i
                            break
                        }
                    }
                    if indexToBeRemoved != -1 {
                        self.pushHistory.remove(at: indexToBeRemoved)
                    }
                }
        }

        for item in pushHistory {
            if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                ephemeralService.dismissPush(item, triggerKey: nil)
                break
            }
        }
    }

    private func replied(notification: NSUserNotification) {
        let body = notification.response?.string

        func doQuickReply() {
            var indexToBeRemoved = -1, i = -1
            for item in pushHistory {
                i += 1
                guard item["notification_id"].string == notification.identifier && item["type"].string == "mirror" else {
                    continue
                }
                ephemeralService.quickReply(item, reply: body!)
                indexToBeRemoved = i
                break
            }
            if (indexToBeRemoved != -1) {
                pushHistory.remove(at: indexToBeRemoved)
            }
        }

        guard notification.identifier?.characters.count ?? 0 > 4 else {
            doQuickReply()
            return
        }

        //determine if we replied to a sms or a normal notification
        let index = notification.identifier?.characters.index((notification.identifier?.startIndex)!, offsetBy: 4)
        guard notification.identifier?.substring(to: index!) == "sms_" else {
            doQuickReply()
            return
        }

        var indexToBeRemoved = -1, i = -1
        for item in pushHistory {
            i += 1

            guard item["type"].string == "sms_changed" else {
                continue
            }
            let metadata = notification.identifier?.substring(from: index!).components(separatedBy: "|")
            let thread_id = metadata![1], source_device_iden = metadata![0], timestamp = metadata![2]

            for (_, sms):(String, JSON) in item["notifications"] {
                guard (sms["thread_id"].string! == thread_id && String(sms["timestamp"].int!) == timestamp) else {
                    continue
                }
                ephemeralService.respondToSMS(body, thread_id: thread_id, source_device_iden: source_device_iden, source_user_iden: self.user!.iden)
                indexToBeRemoved = i
                break
            }

            if (indexToBeRemoved != -1) {
                break
            }
        }
        if (indexToBeRemoved != -1) {
            pushHistory.remove(at: indexToBeRemoved)
        }
    }
}
