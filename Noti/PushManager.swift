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
    var center = NSUserNotificationCenter.defaultUserNotificationCenter()
    var pushHistory = [JSON]()
    var userInfo:JSON?;
    var token:String;
    var ephemerals:Ephemerals;
    
    init(token: String) {
        self.token = token
        self.socket = WebSocket(url: NSURL(string: "wss://stream.pushbullet.com/websocket/" + token)!)
        self.ephemerals = Ephemerals(token: token);
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
    
    //fixme
//    func userNotificationCenter(center: NSUserNotificationCenter, didDismissNotification notification: NSUserNotification) {
//        for item in pushHistory {
//            if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
//                ephemerals.dismissPush(item, trigger_key: nil)
//                break;
//            }
//        }
//    }
    
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
                            ephemerals.dismissPush(item, trigger_key: actions[alternateAction]["trigger_key"].string!)
                            break;
                        }
                    }
                }
                break;
            case .ContentsClicked:
                Alamofire.request(.GET, "https://update.pushbullet.com/android_mapping.json")
                    .responseString { response in
                        if let result = response.result.value {
                            let mapping = JSON.parse(result)
                            
                            for item in self.pushHistory {
                                if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                                    if let url = mapping[item["package_name"].string!].string {
                                        NSWorkspace.sharedWorkspace().openURL(NSURL(string: url)!)
                                    }
                                }
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
            
            case .Replied:
                let body = notification.response?.string
                
                func doQuickReply() {
                    for item in pushHistory {
                        if item["notification_id"].string == notification.identifier && item["type"].string == "mirror" {
                            ephemerals.quickReply(item, reply: body!)
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
                                ephemerals.respondToSMS(body, thread_id: metadata![1], source_device_iden: metadata![0])
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
                        notification.otherButtonTitle = "Dismiss    "
                        notification.actionButtonTitle = "Show"
                        notification.hasActionButton = true
                        notification.title = push["title"].string
                        notification.informativeText = push["body"].string
                        notification.identifier = push["notification_id"].string
                        notification.subtitle = push["application_name"].string // todo: keep or remove?
                        
                        let data = NSData(base64EncodedString: push["icon"].string!, options: NSDataBase64DecodingOptions(rawValue: 0))!
                        let img = RoundedImage(data: data)
                        notification.setValue(img?.withRoundCorners(Int(img!.size.width) / 2), forKeyPath: "_identityImage")
                        notification.setValue(false, forKeyPath: "_identityImageHasBorder")
                        notification.setValue(true, forKeyPath: "_showsButtons")
                        
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
                                
                                notification.setValue(true, forKeyPath: "_showsButtons")
                                
                                notification.soundName = "Glass"
                                
                                if let photo = sms["image_url"].string {
                                    Alamofire.request(.GET, photo)
                                        .responseData { response in
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