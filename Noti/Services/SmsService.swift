//
//  SmsService.swift
//  Noti
//
//  Created by Brian Clymer on 10/22/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

class SmsService {

    private let token: String
    let device: Device
    let ephemeralService: EphemeralService

    init(token: String, device: Device) {
        self.token = token
        self.device = device
        self.ephemeralService = EphemeralService(token: token)

        NotificationCenter.default.addObserver(forName: Notification.Name("NewSMS-\(device.id)"), object: nil, queue: nil, using: { [weak self] notif in
            let threadId = notif.userInfo!["threadId"] as! String
            self?.fetchThreadMessages(threadId: threadId, callback: { _ in })
        })
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func fetchThreads(callback: @escaping (([ThreadPreview]) -> Void)) {
        let headers = [
            "Access-Token": token
        ]
        Alamofire.request("https://api.pushbullet.com/v2/permanents/\(self.device.id)_threads", method: .get, headers: headers)
            .responseString { [weak self] response in
                guard
                    let `self` = self,
                    let string = response.result.value,
                    let json = JSON.parse(string)["threads"].array else {
                        // TODO error
                        return
                }
                let threads = json.map { ThreadPreview(json: $0) }
                SharedAppDelegate.cache.threads[self.device.id] = threads
                callback(threads)
        }
    }

    func fetchThreadMessages(threadId: String, callback: @escaping (([Message]) -> Void)) {
        let headers = [
            "Access-Token": token
        ]
        Alamofire.request("https://api.pushbullet.com/v2/permanents/\(self.device.id)_thread_\(threadId)", method: .get, headers: headers)
            .responseString { response in
                guard
                    let string = response.result.value,
                    let json = JSON.parse(string)["thread"].array else {
                        // TODO error
                        return
                }
                let messages = json.map { Message(json: $0) }
                SharedAppDelegate.cache.messages[threadId] = messages
                callback(messages)
        }
    }

}

struct ThreadPreview {
    let id: String
    let recipients: [Recipient]
    let latest: Message

    init(json: JSON) {
        id = json["id"].stringValue
        recipients = json["recipients"].arrayValue.map { Recipient(json: $0) }
        latest = Message(json: json["latest"])
    }
}

struct Recipient {
    let name: String
    let address: String
    let number: String
    let imageUrl: String

    init(json: JSON) {
        name = json["name"].stringValue
        address = json["address"].stringValue
        number = json["number"].stringValue
        imageUrl = json["image_url"].stringValue
    }
}

struct Message {
    let id: String
    let type: String
    let timestamp: Int64
    let direction: String
    let body: String
    let imageUrls: [String]

    init(json: JSON) {
        id = json["id"].stringValue
        type = json["type"].stringValue
        timestamp = json["timestamp"].int64Value
        direction = json["direction"].stringValue
        body = json["body"].stringValue
        imageUrls = json["image_urls"].array?.map { $0.stringValue } ?? []
    }
}
