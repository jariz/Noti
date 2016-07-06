//
//  PushManager.swift
//  Noti
//
//  Created by Jari on 23/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Foundation
import Starscream
import SwiftyJSON
import Alamofire

class PushManager: NSObject, WebSocketDelegate, NSUserNotificationCenterDelegate {
    var socket:WebSocket?
    var center = NSUserNotificationCenter.defaultUserNotificationCenter()
    var pushHistory = [JSON]()
    var userInfo:JSON?;
    var token:String;
    
    init(token: String) {
        self.token = token
        self.socket = WebSocket(url: NSURL(string: "wss://stream.pushbullet.com/websocket/" + token)!)
        super.init()
        
        center.delegate = self
        connect()
    }
    
    deinit {
        self.socket?.disconnect()
    }
    
    internal func disconnect() {
        self.socket!.disconnect()
    }
    
    
    func userNotificationCenter(center: NSUserNotificationCenter, didActivateNotification notification: NSUserNotification) {
        switch notification.activationType {
        case .ActionButtonClicked:
            var alternateAction = notification.valueForKey("_alternateActionIndex") as! Int
            
            if(alternateAction == Int.max) {
                //user did not use an alternate action, set the index to 0
                alternateAction = 0
            }
            
            print("action")
            print("alternate?", alternateAction)
            
            
            for item in pushHistory {
                if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                    if let actions = item["actions"].array {
                        dismissPush(item, trigger_key: actions[alternateAction]["trigger_key"].string!)
                        break;
                    }
                }
            }
            break;
        case .Replied:
            let body = notification.response?.string
            
            func doQuickReply() {
                for item in pushHistory {
                    if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                        quickReply(item, body: body!)
                    }
                }
            }
            
            //determine if we replied to a sms or a normal notification
            if notification.identifier?.characters.count > 4 {
                let index = notification.identifier?.startIndex.advancedBy(4)
                if notification.identifier?.substringToIndex(index!) == "sms_" {
                    for item in pushHistory {
                        if item["type"].string == "sms_changed" {
                            let metadata = notification.identifier?.substringFromIndex(index!).componentsSeparatedByString("|")
                            respondToSMS(body, thread_id: metadata![1], source_device_iden: metadata![0])
                        }
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
    
    /**
     * TODO refactor these functions below
     **/
    
    func respondToSMS(message: String!, thread_id: String!, source_device_iden: String!) {
        print("respondToSMS", "message", message, "thread_id", thread_id, "source_device_iden", source_device_iden)
        
        //get api key from cookies
        var APIkey:String = ""
        for cookie in NSHTTPCookieStorage.sharedHTTPCookieStorage().cookies! {
            if(cookie.domain == "www.pushbullet.com" && cookie.secure && cookie.name == "api_key" && cookie.path == "/") {
                APIkey = cookie.value
            }
        }
        print("Grabbed API key", APIkey)
        
        if(APIkey == "") {
            let alert = NSAlert()
            alert.messageText = "Unable to retrieve API key from cookies"
            alert.informativeText = "Making Noti reauthorize with PushBullet will probably solve this. (click it's icon in your menu and choose 'Reauthorize')"
            alert.runModal()
            return
        }
        
        let headers = [
            "Authorization": "Bearer " + APIkey
        ];
        
        //get thread recipients & send reply to them
        let body = [
            "key": source_device_iden + "_threads"
        ]
        
        Alamofire.request(.POST, "https://api.pushbullet.com/v3/get-permanent", headers: headers, encoding: .JSON, parameters: body)
            .responseString { response in
                debugPrint(response)
                if let threads = JSON.parse(response.result.value!)["data"]["threads"].array {
                    for thread in threads {
                        if thread["id"].string == thread_id {
                            for recipient in thread["recipients"].array! {
                                let body = [
                                    "push": [
                                        "conversation_iden": recipient["address"].string!,
                                        "message": message,
                                        "package_name": "com.pushbullet.android",
                                        "source_user_iden": "ujpah72o0",
                                        "target_device_iden": source_device_iden,
                                        "type": "messaging_extension_reply"
                                    ],
                                    "type": "push"
                                ]
                                Alamofire.request(.POST, "https://api.pushbullet.com/v2/ephemerals", headers: headers, encoding: .JSON, parameters: body)
                                    .responseString { response in
                                        debugPrint(response)
                                }
                            }
                        }
                    }
                }
        }
        
        
    }
    
    func quickReply(push: JSON, body: String) {
        
        let body = [
            "type": "push",
            "push": [
                "type": "messaging_extension_reply",
                "source_user_iden": push["source_user_iden"].string!,
                "target_device_iden": push["source_device_iden"].string!,
                "package_name": push["package_name"].string!,
                "conversation_iden": push["conversation_iden"].string!,
                "message": body
            ]
        ];
        
        let headers = [
            "Access-Token": token
        ];
        
        print("----BODY-----")
        debugPrint(body)
        print("-------------")
        
        Alamofire.request(.POST, "https://api.pushbullet.com/v2/ephemerals", headers: headers, encoding: .JSON, parameters: body)
            .responseJSON { response in
                debugPrint(response)
        }
    }
    
    func dismissPush(push: JSON, trigger_key: String?) {
        print("dismissPush", trigger_key);
        let headers = [
            "Access-Token": token
        ];
        var body = [
            "type": "push",
            "push": [
                "notification_id": push["notification_id"].string!,
                "package_name": push["package_name"].string!,
                "source_user_iden": push["source_user_iden"].string!,
                "type": "dismissal"
            ]
        ];
        
        if (trigger_key != nil) {
            var push = body["push"] as! [String: String]
            push["trigger_key"] = trigger_key!
            body["push"] = push
        }
        
        print("----BODY-----")
        debugPrint(body)
        print("-------------")
        
        Alamofire.request(.POST, "https://api.pushbullet.com/v2/ephemerals", headers: headers, encoding: .JSON, parameters: body)
            .responseJSON { response in
                debugPrint(response)
        }
    }
    
    func connect() {
        socket!.delegate = self
        socket!.connect()
    }
    
    func websocketDidConnect(socket: WebSocket) {
        print("PushManager", "Is connected")
    }
    
    func websocketDidDisconnect(socket: WebSocket, error: NSError?) {
        print("PushManager", "Is disconnected: \(error?.localizedDescription)", "Reconnecting in 5 sec")
        
        NSTimer.scheduledTimerWithTimeInterval(5, target: NSBlockOperation(block: self.connect), selector: #selector(NSOperation.main), userInfo: nil, repeats: false)
    }
    
    func websocketDidReceiveMessage(socket: WebSocket, text: String) {
        print("PushManager", "receive", text)
        
        let message = JSON.parse(text);
        
        if let type = message["type"].string {
            switch type {
            case "push":
                let push = message["push"];
                pushHistory.append(push)
                
                if let pushType = push["type"].string {
                    switch(pushType) {
                    case "mirror":
                        let notification = NSUserNotification()
                        notification.title = push["title"].string
                        notification.informativeText = push["body"].string
                        notification.identifier = push["notification_id"].string
                        notification.subtitle = push["application_name"].string // todo: keep or remove?
                        
                        let data = NSData(base64EncodedString: push["icon"].string!, options: NSDataBase64DecodingOptions(rawValue: 0))!
                        notification.setValue(NSImage(data: data), forKeyPath: "_identityImage")
                        notification.setValue(false, forKeyPath: "_identityImageHasBorder")
                        
                        if push["conversation_iden"].isExists() {
                            notification.hasReplyButton = true
                        }
                        
                        if let actions = push["actions"].array {
                            notification.hasActionButton = true
                            if(actions.count == 1) {
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
                        
                        notification.soundName = NSUserNotificationDefaultSoundName
                        
                        center.deliverNotification(notification)
                        break;
                    case "dismissal":
                        //loop through current user notifications, if identifier matches, remove it
                        for noti in center.deliveredNotifications {
                            if noti.identifier == push["notification_id"].string {
                                center.removeDeliveredNotification(noti)
                                print("Removed a noti (", noti.identifier, ")")
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
                            pushHistory.removeAtIndex(indexToBeRemoved)
                        }
                        
                        break;
                    case "sms_changed":
                        if push["notifications"].isExists() {
                            for sms in push["notifications"].array! {
                                let notification = NSUserNotification()
                                
                                notification.title = "SMS from " + sms["title"].string!
                                notification.informativeText = sms["body"].string
                                notification.hasReplyButton = true
                                notification.identifier = "sms_" + push["source_device_iden"].string! + "|" + sms["thread_id"].string!
                                
                                notification.soundName = "Glass"
                                
                                if let photo = sms["image_url"].string {
                                    Alamofire.request(.GET, photo)
                                        .responseData{response in
                                            debugPrint(response)
                                            notification.setValue(NSImage(data: response.result.value!), forKey: "_identityImage")
                                            
                                            self.center.deliverNotification(notification)
                                    }
                                } else {
                                    self.center.deliverNotification(notification)
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
                print("Unknown type of message ", message["type"].string)
                break;
            }
        }
        
    }
    
    func websocketDidReceiveData(socket: WebSocket, data: NSData) {
        print("PushManager", "Received data???: \(data.length)")
        print("PushManager", "We don't handle raw data, so ignored...")
    }
}