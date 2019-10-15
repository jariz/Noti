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
    var nopTimer : Timer
    
    init(token: String) {
        self.token = token
        self.socket = WebSocket(url: URL(string: "wss://stream.pushbullet.com/websocket/" + token)!)
        self.ephemerals = Ephemerals(token: token);
        self.userState = "Initializing..."
        self.nopTimer = Timer()
        super.init()
        
        center.delegate = self
        self.initCrypt()
        
        log.debug("Init Noti")
        getUserInfo {
            self.connect()
        }
    }
    
    deinit {
        disconnect(attemptReconnect:false)
    }
    
    @objc internal func disconnectForTimeout() {
        log.warning("Disconnected for timeout (nop not received)")
        disconnect(attemptReconnect: true)
    }
    
    @objc internal func disconnect(attemptReconnect: Bool = true) {
        log.warning("Triggered disconnect attemptReconnect:\(attemptReconnect), isConnected:\(self.socket!.isConnected)")
        //stops attempts to reconnect
        if !attemptReconnect {
            self.killed = true
        }
        
        //disconnect now!
        if self.socket!.isConnected {
            self.socket!.disconnect(forceTimeout: 0)
        }
    }
    
    func initCrypt() {
        let keyData = userDefaults.object(forKey: "secureKey") as? Data
        if keyData != nil {
            let key = keyData?.toArray()
            self.crypt = Crypt(key: key!)
            log.debug("Encryption enabled!")
        } else {
            self.crypt = nil
            log.debug("Encryption not enabled")
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
        log.debug("Getting user info...")
        //todo: this is kinda dirty ...
        self._callback = callback
        
        let headers = [
            "Access-Token": token
        ];
        
        Alamofire.request("https://api.pushbullet.com/v2/users/me", headers: headers)
            .responseString { response in
                if let info = response.result.value {
                    debugPrint(info)
                    self.userInfo = JSON(parseJSON:info)
                    
                    if self.userInfo!["error"].exists() {
                        log.error("user info error during request of user info: \(self.userInfo!["error"]["message"].string!)")
                        self.disconnect(attemptReconnect:false)
                        self.setState("Disconnected: " + self.userInfo!["error"]["message"].string!, disabled: true)
                    } else {
                        if callback != nil {
                            callback!()
                        }
                    }
                    
                } else if response.result.error != nil {
                    log.error("response error requesting user info")
                    if callback == nil {
                        self.disconnect(attemptReconnect:false)
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
                
                handleNotification(notification)
                
                for item in pushHistory {
                    if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                        if let actions = item["actions"].array {
                            ephemerals.dismissPush(item, trigger_key: actions[alternateAction]["trigger_key"].string!)
                            break;
                        }
                    }
                }
                break;
            case .contentsClicked:
                //check if this is the encryption warning notification (Swift4 new strings)
                if(notification.identifier?.hasPrefix("noti_encrypt"))!{
                    return
                }
                handleNotification(notification)
                
                Alamofire.request("https://update.pushbullet.com/android_mapping.json")
                    .responseString { response in
                        if let result = response.result.value {
                            let mapping = JSON(parseJSON:result)
                            
                            var indexToBeRemoved = -1, i = -1;
                            for item in self.pushHistory {
                                i += 1;
                                if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                                    if let url = mapping[item["package_name"].string!].string {
                                        NSWorkspace.shared.open(URL(string: url)!)
                                        
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
                if (notification.identifier?.count)! > 4 {
                    let index = notification.identifier?.index((notification.identifier?.startIndex)!, offsetBy: 4)
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
            log.error("did not understand activation type \(notification.activationType.rawValue)")
            break;
        }
    }
    
    func connect() {
        log.debug("Connecting to Pushbullet")
        socket!.delegate = self
        socket!.connect()
    }
    
    func websocketDidConnect(socket: WebSocketClient) {
        if let photo = self.userInfo!["image_url"].string {
            Alamofire.request(photo)
                .responseData { response in
                    self.setState("Logged in as: " + self.userInfo!["name"].string!, image: NSImage(data: response.result.value!), disabled: false)
            }
        } else {
            self.setState("Logged in as: " + self.userInfo!["name"].string!, disabled: false)
        }
        
        
        log.debug("PushManager is connected")
    }
    
    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        log.warning("PushManager is disconnected: \(error?.localizedDescription ?? "")")
        
        if(!self.killed) {
            log.info("Reconnecting in 5 sec");
            if error != nil {
                setState("Disconnected: \(error!.localizedDescription), retrying...", disabled: true)
            }
            else {
                setState("Disconnected, retrying...", disabled: true)
            }
            
            Timer.scheduledTimer(timeInterval: 5, target: BlockOperation(block: self.connect), selector: #selector(Operation.main), userInfo: nil, repeats: false)
        } else {
            log.error("Not going to reconnect: I'm killed")
            setState("Disconnected. Please log in.", disabled: true)
        }
    }
    
    func setPassword(password: String) {
        let iden = userInfo!["iden"].string!
        let key = Crypt.generateKey(password, salt: iden)
        userDefaults.set(key, forKey: "secureKey")
    }
    
    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        print("PushManager", "receive", text)
        
        var message = JSON(parseJSON:text);
        
        if let type = message["type"].string {
            switch type {
            case "nop":
                self.nopTimer.invalidate()  // Resetting nopTimer
                self.nopTimer = Timer.scheduledTimer(timeInterval: 35.0, target: self, selector: #selector(PushManager.disconnectForTimeout), userInfo: nil, repeats: false)
            case "tickle":
                if let subtype = message["subtype"].string {
                    if(subtype == "account") {
                        log.debug("TICKLE -> account")
                        getUserInfo(nil)
                    }
                    else if(subtype == "push"){
                        // When you receive a tickle message, it means that a resource of the type push has changed.
                        // Request only the latest push: In this case can be a file, a link or just a simple note
                        log.debug("TICKLE -> push")
                        Alamofire.request("https://api.pushbullet.com/v2/pushes?limit=1", headers: ["Access-Token": token])
                            .responseString { response in
                                if let result = response.result.value {
                                    let push = JSON(parseJSON:result)["pushes"][0]    // get ["pushes"][latest] array
                                    self.pushHistory.append(push)
                                    self.center.deliver(self.createNotification(push))
                                }
                        };
                    }
                }
                break;
            case "push":
                let push = checkEncryption(message["push"]);    // Check for encryption and decrypt
                pushHistory.append(push)
                
                if let pushType = push["type"].string {
                    switch(pushType) {
                    case "mirror":
                        log.debug("PUSH -> mirror")
                        center.deliver(createNotification(push))
                        break;
                    case "dismissal":
                        //loop through current user notifications, if identifier matches, remove it
                        log.debug("PUSH -> dismiss")
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
                        log.debug("PUSH -> sms_changed")
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
                        log.warning("Unknown type of push", pushType)
                        break;
                    }
                }
                break;
            default:
                log.warning("Unknown type of message ", message["type"].string!)
                break;
            }
        }
        
    }
    
    // Given a push JSON object from Pushbullet create a notification
    // Used in mirror and subtype:push
    internal func createNotification(_ msg : JSON) -> NSUserNotification{
        var push = checkEncryption(msg)                                     // If it's encrypted, decrypt it
        let notification = NSUserNotification()
        if(push == JSON.null || push["dismissed"].boolValue){               // If somenthing went wrong or it's already dismissed
            return notification
        }
        notification.actionButtonTitle = "Show"
        if let type = push["type"].string {
            print(push)
            switch type {
            case "link" :                                                     // Special type of Noti: url type
                notification.title = "Url"                                  // We have no title here
                notification.informativeText = push["url"].string
                notification.identifier = "noti_url" + push["iden"].string!     // We need to recognize it after user pressed
            case "file" :                                                   // Special type of Noti: file type
                notification.title = push["file_name"].string               // Using the file name as title
                notification.informativeText = push["image_url"].string     // and file type as description
                notification.identifier = "noti_file" + push["iden"].string!
            case "note" :                                                   // Special type of Noti: note (seems like a self message)
                notification.title = push["sender_name"].string
                notification.informativeText = push["body"].string
                notification.identifier = "noti_note" + push["iden"].string!
                notification.actionButtonTitle = "Dismiss"
            default :                                                       // Default: all other Noty
                notification.title = push["title"].string
                notification.informativeText = push["body"].string
                notification.otherButtonTitle = "Dismiss    "
                notification.identifier = push["notification_id"].string
            }
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
    
    internal func handleNotification(_ notification : NSUserNotification){
        //check if it's opening an url type of notification
        if((notification.identifier?.hasPrefix("noti_url"))! || (notification.identifier?.hasPrefix("noti_file"))!){
            NSWorkspace.shared.open(URL(string: notification.informativeText!)!)    // Just open the message URL
            return
        }
    }
    
    // Given a push JSON object return:
    // 1- The input object if no encryption is present
    // 2- A new object with "push" parameter decrypted
    // 3- JSON.null and display a notification of error
    internal func checkEncryption(_ message : JSON) -> JSON{
        if message["encrypted"].exists() && message["encrypted"].bool! {
            func warnUser() {
                let noti = NSUserNotification()
                noti.title = "I received data I couldn't understand!"
                noti.informativeText = "It appears you're using encryption, click to open settings & set password."
                noti.actionButtonTitle = "Settings"
                noti.identifier = "noti_encrypt" + String(arc4random())
                center.deliver(noti)
            }
            
            if crypt != nil {
                let decrypted = crypt?.decryptMessage(message["ciphertext"].string!)
                if decrypted == nil {
                    warnUser()
                    return JSON.null
                } else {
                    return JSON(parseJSON:decrypted!)
                }
            } else {
                warnUser()
                return JSON.null
            }
        }
        return message
    }
    
    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        
    }
}
