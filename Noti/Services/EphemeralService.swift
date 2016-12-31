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

class EphemeralService {

    var token:String
    var crypt:Crypt?
    
    init(token:String) {
        self.token = token
    }

    private func send(ephemeral: Ephemeral) {
        var body = ephemeral.toJson()

        if crypt != nil && ephemeral.type == "push" {
            print("Encrypting ephemeral...")
            let json = JSON.init(body)

            let cipher = crypt!.encryptMessage(message: json["push"].rawString()!)
            body["push"] = [
                "encrypted": true,
                "ciphertext": cipher!
            ]
        }

        print("Sending ephemeral...")
        print("-------- BODY --------")
        debugPrint(body)
        print("----------------------")

        let headers = ["Access-Token": token]
        Alamofire.request("https://api.pushbullet.com/v2/ephemerals", method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
            .responseString { response in
                var result = JSON.parse(response.result.value!)
                if(response.response?.statusCode != 200) {

                    let alert = NSAlert()
                    alert.messageText = "Unable to send ephemeral!"
                    if result["error"].exists() {
                        alert.informativeText = result["error"]["type"].string! + ": " + result["error"]["message"].string!
                    }

                    alert.runModal()
                }
                debugPrint(response)
        }
    }
    
    func respondToSMS(_ message: String!, thread_id: String!, source_device_iden: String!, source_user_iden: String!) {
        print("respondToSMS", "message", message, "thread_id", thread_id, "source_device_iden", source_device_iden)
        
        //get api key from cookies
        var APIkey:String = ""
        for cookie in HTTPCookieStorage.shared.cookies! {
            if(cookie.domain == "www.pushbullet.com" && cookie.isSecure && cookie.name == "api_key" && cookie.path == "/") {
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
        ]
        
        //get thread recipients & send reply to them
        let body = [
            "key": source_device_iden + "_threads"
        ]
        
        Alamofire.request("https://api.pushbullet.com/v3/get-permanent", method: .post, parameters: body, encoding: JSONEncoding.default, headers: headers)
            .responseString { response in
                debugPrint(response)
                var parsed = JSON.parse(response.result.value!)
                
                //decrypt if needed....
                if self.crypt != nil && parsed["data"]["encrypted"].exists() {
                    parsed["data"] = JSON.parse((self.crypt!.decryptMessage(parsed["data"]["ciphertext"].string!))!)
                }
                
                if let threads = parsed["data"]["threads"].array {
                    for thread in threads {
                        if thread["id"].string == thread_id {
                            for recipient in thread["recipients"].array! {
                                let ephemeral = Ephemeral(push: EphemeralPushSms(
                                    type: "messaging_extension_reply",
                                    sourceUserIden: source_user_iden,
                                    packageName: "com.pushbullet.android",
                                    targetDeviceIden: source_device_iden,
                                    conversationIden: recipient["address"].stringValue,
                                    message: message))
                                
                                self.send(ephemeral: ephemeral)
                            }
                        }
                    }
                }
        }
    }
    
    func quickReply(_ push: JSON, reply: String) {
        let ephemeral = Ephemeral(push: EphemeralPushSms(
            type: "messaging_extension_reply",
            sourceUserIden: push["source_user_iden"].stringValue,
            packageName: push["package_name"].stringValue,
            targetDeviceIden: push["source_device_iden"].stringValue,
            conversationIden: push["conversation_iden"].stringValue,
            message: reply))
        
        self.send(ephemeral: ephemeral)
    }
    
    func dismissPush(_ push: JSON, triggerKey: String?) {
        let ephemeral = Ephemeral(push: EphemeralPushDismiss(
            type: "dismissal",
            sourceUserIden: push["source_user_iden"].stringValue,
            packageName: push["package_name"].stringValue,
            notificationId: push["notification_id"].stringValue,
            triggerAction: triggerKey))

        self.send(ephemeral: ephemeral)
    }

    func sendSms(message: String, device: Device, sourceUserId: String, conversationId: String) {
        let ephemeral = Ephemeral(push: EphemeralPushSms(
            type: "messaging_extension_reply",
            sourceUserIden: sourceUserId,
            packageName: "com.pushbullet.android",
            targetDeviceIden: device.id,
            conversationIden: conversationId,
            message: message))

        self.send(ephemeral: ephemeral)
    }
}

struct Ephemeral {

    let type: String = "push"
    let push: EphemeralPush

    func toJson() -> [String: Any]{
        return [
            "type": self.type,
            "push": self.push.toJson()
        ]
    }

}

protocol EphemeralPush {
    var type: String { get }
    var sourceUserIden: String { get }
    func toJson() -> [String: String]
}

struct EphemeralPushSms: EphemeralPush {

    let type: String
    let sourceUserIden: String
    let packageName: String
    let targetDeviceIden: String
    let conversationIden: String
    let message: String

    func toJson() -> [String : String] {
        return [
            "type": self.type,
            "package_name": self.packageName,
            "source_user_iden": self.sourceUserIden,
            "target_device_iden": self.targetDeviceIden,
            "conversation_iden": self.conversationIden,
            "message": self.message
        ]
    }
}

struct EphemeralPushDismiss: EphemeralPush {

    let type: String
    let sourceUserIden: String
    let packageName: String
    let notificationId: String
    let triggerAction: String?

    func toJson() -> [String : String] {
        return [
            "type": self.type,
            "package_name": self.packageName,
            "source_user_iden": self.sourceUserIden,
            "notification_id": self.notificationId,
        ]
    }
}
