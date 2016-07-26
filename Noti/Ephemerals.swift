//
//  Ephemerals.swift
//  Noti
//
//  Created by Jari on 06/07/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//
//  Ephemerals is in charge of sending out a range of short JSON messages which could be dismissals, quick replys, etc.
//  https://docs.pushbullet.com/#ephemerals
//

import Foundation
import Cocoa
import Alamofire
import SwiftyJSON

class Ephemerals: NSObject {
    var token:String
    var crypt:Crypt?
    
    init(token:String) {
        self.token = token
    }
    
    internal func sendEphemeral(body: [String: AnyObject]) {
        var body = body
        let headers = [
            "Access-Token": token
        ];
        
        if crypt != nil && body["type"] as? String == "push" {
            print("Encrypting ephemeral...")
            let json = JSON.init(body)
            
            let cipher = crypt!.encryptMessage(json["push"].rawString()!)
            body["push"] = [
                "encrypted": true,
                "ciphertext": cipher!
            ]
        }
        
        print("Sending ephemeral...")
        print("-------- BODY --------")
        debugPrint(body)
        print("----------------------")
        
        Alamofire.request(.POST, "https://api.pushbullet.com/v2/ephemerals", headers: headers, encoding: .JSON, parameters: body)
            .responseString { response in
                var result = JSON.parse(response.result.value!)
                if(response.response?.statusCode != 200) {
                    
                    let alert = NSAlert()
                    alert.messageText = "Unable to send ephemeral!"
                    if result["error"].isExists() {
                        alert.informativeText = result["error"]["type"].string! + ": " + result["error"]["message"].string!
                    }
                    
                    alert.runModal()
                }
                debugPrint(response)
        }
    }
    
    func respondToSMS(message: String!, thread_id: String!, source_device_iden: String!, source_user_iden: String!) {
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
                var parsed = JSON.parse(response.result.value!)
                
                //decrypt if needed....
                if self.crypt != nil && parsed["data"]["encrypted"].isExists() {
                    parsed["data"] = JSON.parse((self.crypt!.decryptMessage(parsed["data"]["ciphertext"].string!))!)
                }
                
                if let threads = parsed["data"]["threads"].array {
                    for thread in threads {
                        if thread["id"].string == thread_id {
                            for recipient in thread["recipients"].array! {
                                let body = [
                                    "push": [
                                        "conversation_iden": recipient["address"].string!,
                                        "message": message,
                                        "package_name": "com.pushbullet.android",
                                        "source_user_iden": source_user_iden,
                                        "target_device_iden": source_device_iden,
                                        "type": "messaging_extension_reply"
                                    ],
                                    "type": "push"
                                ]
                                self.sendEphemeral(body)
                            }
                        }
                    }
                }
        }
    }
    
    func quickReply(push: JSON, reply: String) {
        let body = [
            "type": "push",
            "push": [
                "type": "messaging_extension_reply",
                "source_user_iden": push["source_user_iden"].string!,
                "target_device_iden": push["source_device_iden"].string!,
                "package_name": push["package_name"].string!,
                "conversation_iden": push["conversation_iden"].string!,
                "message": reply
            ]
        ];
        
        sendEphemeral(body)
    }
    
    func dismissPush(push: JSON, trigger_key: String?) {
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
            push["trigger_action"] = trigger_key!
            body["push"] = push
        }
        
        sendEphemeral(body)
    }
    
}