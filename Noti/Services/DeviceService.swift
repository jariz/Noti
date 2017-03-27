//
//  DeviceService.swift
//  Noti
//
//  Created by Brian Clymer on 10/22/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

class DeviceService {
    private let token: String

    init(token: String) {
        self.token = token
    }

    func fetchDevices(callback: @escaping (([Device]) -> Void)) {
        Alamofire.request("https://api.pushbullet.com/v2/devices", method: .get, headers: ["Access-Token": token])
            .responseString { response in
                guard
                    let string = response.result.value,
                    let devicesJson = JSON.parse(string)["devices"].array else {
                    // TODO error
                    return
                }
                let devices = devicesJson
                    .map { Device(json: $0) }
                    .filter { $0.hasSms }
                SharedAppDelegate.cache.devices = devices
                callback(devices)
        }
    }
}

struct Device {
    let id: String
    let name: String
    let hasSms: Bool

    init(json: JSON) {
        id = json["iden"].stringValue
        name = json["nickname"].stringValue
        hasSms = json["has_sms"].boolValue
    }
}
