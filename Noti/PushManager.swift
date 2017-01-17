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

class PushManager: NSObject, WebSocketDelegate, NSUserNotificationCenterDelegate {
    var socket:WebSocket?
    let center = NSUserNotificationCenter.default
    var pushHistory = [JSON]()
    var userInfo:JSON?
    var token:String
    var ephemerals:Ephemerals
    var crypt:Crypt?
    var killed = false
    let userDefaults = UserDefaults.standard
    var userState: String
    
    init(token: String) {
        self.token = token
        self.socket = WebSocket(url: URL(string: "wss://stream.pushbullet.com/websocket/" + token)!)
        self.ephemerals = Ephemerals(token: token);
        self.userState = "Initializing..."
        super.init()
        
        center.delegate = self
        self.initCrypt()
        
        print("Getting user info...")
        getUserInfo {
            self.connect()
        }
    }
    
    deinit {
        disconnect()
    }
    
    internal func disconnect() {
        //stops attempts to reconnect
        self.killed = true
        
        //disconnect now!
        self.socket!.disconnect(forceTimeout: 0)
    }
    
    func initCrypt() {
        let keyData = userDefaults.object(forKey: "secureKey") as? Data
        if keyData != nil {
            let key = keyData?.toArray()
            self.crypt = Crypt(key: key!)
            print("Encryption enabled!")
        } else {
            self.crypt = nil
            print("Encryption not enabled")
        }
        self.ephemerals.crypt = self.crypt
    }
    
    func setState(_ state: String, image: NSImage? = nil, disabled: Bool? = nil) {
        userState = state
        var object:[String: AnyObject] = [
            "title": state as AnyObject
        ]
        if image != nil {
            object["image"] = image!
        }
        if disabled != nil {
            object["disabled"] = disabled as AnyObject?
        }
        NotificationCenter.default.post(name: Notification.Name(rawValue: "StateChange"), object: object)
    }
    
    var _callback:(() -> Void)? = nil
    func getUserInfo(_ callback: (() -> Void)?) {
        //todo: this is kinda dirty ...
        self._callback = callback
        
        let headers = [
            "Access-Token": token
        ];
        
        Alamofire.request("https://api.pushbullet.com/v2/users/me", headers: headers)
            .responseString { response in
                if let info = response.result.value {
                    debugPrint(info)
                    self.userInfo = JSON.parse(info)
                    
                    if self.userInfo!["error"].exists() {
                        self.killed = true
                        self.disconnect()
                        self.setState("Disconnected: " + self.userInfo!["error"]["message"].string!, disabled: true)
                    } else {
                        if callback != nil {
                            callback!()
                        }
                    }
                    
                } else if response.result.error != nil {
                    if callback == nil {
                        self.killed = true
                        self.disconnect()
                        self.setState("Failed to log in.")
                    } else {
                        self.setState("Failed to log in, retrying in 2 seconds...")
                        Timer.scheduledTimer(timeInterval: 2, target: BlockOperation(block: self.retryUserInfo), selector: #selector(Operation.main), userInfo: nil, repeats: false)
                    }
                    
                }
        }
    }
    
    func retryUserInfo() {
        getUserInfo(self._callback)
    }
    
    
    func userNotificationCenter(_ center: NSUserNotificationCenter, didActivate notification: NSUserNotification) {
        switch notification.activationType {
            case .actionButtonClicked:
                var alternateAction = notification.value(forKey: "_alternateActionIndex") as! Int
                
                if(alternateAction == Int.max) {
                    //user did not use an alternate action, set the index to 0
                    alternateAction = 0
                }
                
                print("action")
                print("alternate?", alternateAction)
                
                for item in pushHistory {
                    if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                        if let actions = item["actions"].array {
                            ephemerals.dismissPush(item, trigger_key: actions[alternateAction]["trigger_key"].string!)
                            break;
                        }
                    }
                    else if item["iden"].string == notification.identifier && item["type"].string == "link" {           // Url type act different
                        NSWorkspace.shared().open(URL(string: item["url"].string!)!)
                    }
                    else if item["iden"].string == notification.identifier && item["type"].string == "file" {           // This works only for image file retrieval it's different
                        NSWorkspace.shared().open(URL(string: item["image_url"].string!)!)
                    }
                }
                break;
            case .contentsClicked:
                //check if this is the encryption warning notification
                if (notification.identifier?.characters.count)! > 12 {
                    let index = notification.identifier!.characters.index(notification.identifier!.startIndex, offsetBy: 12)
                    if notification.identifier?.substring(to: index) == "noti_encrypt" {
                        return
                    }
                }
                
                
                
                // Call the default action (whatsapp web, messenger, ...)
                Alamofire.request("https://update.pushbullet.com/android_mapping.json")
                    .responseString { response in
                        if let result = response.result.value {
                            let mapping = JSON.parse(result)
                            
                            var indexToBeRemoved = -1, i = -1;
                            for item in self.pushHistory {
                                i += 1;
                                if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                                    if let url = mapping[item["package_name"].string!].string {
                                        NSWorkspace.shared().open(URL(string: url)!)
                                        
                                        for noti in center.deliveredNotifications {
                                            if noti.identifier == item["notification_id"].string {
                                                center.removeDeliveredNotification(noti)
                                                print("Removed a noti (", noti.identifier!, ")")
                                            }
                                        }
                                        
                                        indexToBeRemoved = i;
                                        break;
                                    }
                                }
                            }
                            if indexToBeRemoved != -1 {
                                self.pushHistory.remove(at: indexToBeRemoved);
                            }
                        }
                }
                
                for item in pushHistory {
                    if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                        ephemerals.dismissPush(item, trigger_key: nil)
                        break;
                    }
                }
                
                break;
            
            case .replied:
                let body = notification.response?.string
                
                func doQuickReply() {
                    var indexToBeRemoved = -1, i = -1;
                    for item in pushHistory {
                        i += 1;
                        if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                            ephemerals.quickReply(item, reply: body!);
                            indexToBeRemoved = i;
                            break;
                        }
                    }
                    if(indexToBeRemoved != -1) {
                        pushHistory.remove(at: indexToBeRemoved)
                    }
                }
                
                //determine if we replied to a sms or a normal notification
                if (notification.identifier?.characters.count)! > 4 {
                    let index = notification.identifier?.characters.index((notification.identifier?.startIndex)!, offsetBy: 4)
                    if notification.identifier?.substring(to: index!) == "sms_" {
                        var indexToBeRemoved = -1, i = -1;
                        for item in pushHistory {
                            i += 1;
                            if item["type"].string == "sms_changed" {
                                let metadata = notification.identifier?.substring(from: index!).components(separatedBy: "|")
                                let thread_id = metadata![1], source_device_iden = metadata![0], timestamp = metadata![2]
                                
                                for (_, sms):(String, JSON) in item["notifications"] {
                                    if(sms["thread_id"].string! == thread_id && String(sms["timestamp"].int!) == timestamp) {
                                        ephemerals.respondToSMS(body, thread_id: thread_id, source_device_iden: source_device_iden, source_user_iden: self.userInfo!["iden"].string!);
                                        indexToBeRemoved = i
                                        break;
                                    }
                                }
                                
                                if(indexToBeRemoved != -1) {
                                    break;
                                }
                            }
                        }
                        if(indexToBeRemoved != -1) {
                            pushHistory.remove(at: indexToBeRemoved)
                        }
                    } else {
                        doQuickReply()
                    }
                } else {
                    doQuickReply()
                }
                
            break;
        default:
            print("did not understand activation type", notification.activationType.rawValue)
            break;
        }
    }
    
    func connect() {
        socket!.delegate = self
        socket!.connect()
    }
    
    internal func websocketDidConnect(socket: WebSocket) {
        if let photo = self.userInfo!["image_url"].string {
            Alamofire.request(photo)
                .responseData { response in
                    self.setState("Logged in as: " + self.userInfo!["name"].string!, image: NSImage(data: response.result.value!), disabled: false)
            }
        } else {
            self.setState("Logged in as: " + self.userInfo!["name"].string!, disabled: false)
        }
        
        
        print("PushManager", "Is connected")
    }
    
    internal func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        print("PushManager", "Is disconnected: \(error?.localizedDescription)")
        
        if(!self.killed) {
            print("Reconnecting in 5 sec");
            if error != nil {
                setState("Disconnected: \(error!.localizedDescription), retrying...", disabled: true)
            }
            else {
                setState("Disconnected, retrying...", disabled: true)
            }
            
            Timer.scheduledTimer(timeInterval: 5, target: BlockOperation(block: self.connect), selector: #selector(Operation.main), userInfo: nil, repeats: false)
        } else {
            print("Not going to reconnect: I'm killed")
            setState("Disconnected. Please log in.", disabled: true)
        }
    }
    
    func setPassword(password: String) {
        let iden = userInfo!["iden"].string!
        let key = Crypt.generateKey(password, salt: iden)
        userDefaults.set(key, forKey: "secureKey")
    }
    
    internal func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        print("PushManager", "receive", text)
        
        var message = JSON.parse(text);
        
        if let type = message["type"].string {
            switch type {
                
            case "tickle":
                if let subtype = message["subtype"].string {
                    if(subtype == "account") {
                        getUserInfo(nil)
                    }
                    else if(subtype == "push"){
                        // When you receive a tickle message, it means that a resource of the type push has changed.
                        // Request only the latest push: In this case can be a file, a link or just a simple note
                        let headers = ["Access-Token": token];
                        Alamofire.request("https://api.pushbullet.com/v2/pushes?limit=1", headers: headers)
                            .responseString { response in
                                if let result = response.result.value {
                                    let push = JSON.parse(result)["pushes"][0]    // get ["pushes"] array
                                    self.pushHistory.append(push)
                                    self.center.deliver(self.createNotification(push: push))
                                }
                            };
                        
                    }
                }
                break;
            case "push":
                let push = message["push"];
                pushHistory.append(push)
                
                if push["encrypted"].exists() && push["encrypted"].bool! {
                    func warnUser() {
                        let noti = NSUserNotification()
                        noti.title = "I received data I couldn't understand!"
                        noti.informativeText = "It appears you're using encryption, click to open settings & set password."
                        noti.actionButtonTitle = "Settings"
                        noti.identifier = "noti_encrypt" + String(arc4random())
                        center.deliver(noti)
                    }
                    
                    if crypt != nil {
                        let decrypted = crypt?.decryptMessage(push["ciphertext"].string!)
                        if decrypted == nil {
                            warnUser()
                        } else {
                            message["push"] = JSON.parse(decrypted!)
                            //handle decrypted message
                            websocketDidReceiveMessage(socket: socket, text: message.rawString()!)
                        }
                    } else {
                        warnUser()
                    }
                    
                    return
                }
                
                if let pushType = push["type"].string {
                    switch(pushType) {
                    case "mirror":
                        center.deliver(createNotification(push: push))
                        break;
                    case "dismissal":
                        //loop through current user notifications, if identifier matches, remove it
                        for noti in center.deliveredNotifications {
                            if noti.identifier == push["notification_id"].string {
                                center.removeDeliveredNotification(noti)
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
                        
                        break;
                    case "sms_changed":
                        if push["notifications"].exists() {
                            for sms in push["notifications"].array! {
                                let notification = NSUserNotification()
                                
                                notification.title = "SMS from " + sms["title"].string!
                                notification.informativeText = sms["body"].string
                                notification.hasReplyButton = true
                                notification.identifier = "sms_" + push["source_device_iden"].string! + "|" + sms["thread_id"].string! + "|" + String(sms["timestamp"].int!)
                                
                                notification.setValue(true, forKeyPath: "_showsButtons")
                                
                                notification.soundName = "Glass"
                                
                                if let photo = sms["image_url"].string {
                                    Alamofire.request(photo)
                                        .responseData { response in
                                            notification.setValue(NSImage(data: response.result.value!), forKey: "_identityImage")
                                            self.center.deliver(notification)
                                    }
                                } else {
                                    self.center.deliver(notification)
                                }
                            }
                        }
                        break;
                    default:
                        print("Unknown type of push", pushType)
                        break;
                    }
                }
                break;
            default:
                print("Unknown type of message ", message["type"].string!)
                break;
            }
        }
        
    }
    
    // Given a push JSON object from Pushbullet create a notification
    // Used in mirror and subtipe:push
    internal func createNotification(push : JSON) -> NSUserNotification{
        let notification = NSUserNotification()
        notification.actionButtonTitle = "Show"
        if let url = push["url"].string {                       // Special type of Noti: url type
            notification.title = "Url"
            notification.informativeText = url
        }
        else if let file = push["file_name"].string {           // Special type of Noti: file type
            notification.title = file
            notification.informativeText = push["file_type"].string
        }
        else{                                                   // Normal notification with title and text
            notification.title = push["title"].string
            notification.informativeText = push["body"].string
            notification.otherButtonTitle = "Dismiss    "
        }
        if let id = push["iden"].string{                        // id can be "iden"
            notification.identifier = id
        }
        else{                                                   // or it can be "notification_id"
            notification.identifier = push["notification_id"].string
        }
        let omitAppNameDefaultExists = userDefaults.object(forKey: "omitAppName") != nil
        let omitAppName = omitAppNameDefaultExists ? userDefaults.bool(forKey: "omitAppName") : false;
        if !omitAppName {
            notification.subtitle = push["application_name"].string
        }
        
        if let icon = push["icon"].string {
            let data = Data(base64Encoded: icon, options: NSData.Base64DecodingOptions(rawValue: 0))!
            let roundedImagesDefaultExists = userDefaults.object(forKey: "roundedImages") != nil
            let roundedImages = roundedImagesDefaultExists ? userDefaults.bool(forKey: "roundedImages") : true;
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
            if(actions.count == 1 || !(userInfo!["pro"].exists())) {
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
        
        let soundDefaultExists = userDefaults.object(forKey: "sound") != nil                // issue 38 https://github.com/jariz/Noti/issues/38
        let sound = soundDefaultExists ? userDefaults.string(forKey: "sound") : "Glass";
        
        notification.soundName = sound
        
        return notification
    }
    
    func websocketDidReceiveData(socket: WebSocket, data: Data) {
        
    }
}
