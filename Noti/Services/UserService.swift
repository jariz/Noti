//
//  UserService.swift
//  Noti
//
//  Created by Brian Clymer on 11/12/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Foundation
import Alamofire
import SwiftyJSON

class UserService {
    
    private let token: String

    init(token: String) {
        self.token = token
    }

    func fetchUserInfo(success: @escaping (User) -> Void, failure: @escaping (() -> Void)) {
        let headers = [
            "Access-Token": self.token
        ]

        Alamofire.request("https://api.pushbullet.com/v2/users/me", method: .get, headers: headers)
            .responseString { response in
                if let info = response.result.value {
                    let json = JSON.parse(info)

                    if json["error"].exists() {
                        failure()
                    } else {
                        let user = User(data: json)
                        success(user)
                    }

                } else if response.result.error != nil {
                    failure()
                }
        }
    }

}

struct User {

    let email: String?
    let emailNormalized: String?
    let iden: String
    let imageUrl: String?
    let name: String
    let maxUploadSize: Double
    let pro: Bool

    init(data: JSON) {
        self.email = data["email"].string
        self.emailNormalized = data["email_normalized"].string
        self.iden = data["iden"].stringValue
        self.imageUrl = data["image_url"].string
        self.maxUploadSize = data["max_upload_size"].double ?? 0
        self.name = data["name"].string ?? "(null)"
        self.pro = data["pro"].exists()
    }

}
