//
//  HackyRepository.swift
//  Noti
//
//  Created by Brian Clymer on 11/10/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Foundation

// This is a pretty dumb way to update everything, but it's just to get something working.
class HackyRepository {

    var devices = [Device]() {
        didSet {
            self.notifyChanged()
        }
    }

    // the key is a device id
    var threads = [String: [ThreadPreview]]() {
        didSet {
            self.notifyChanged()
        }
    }

    // the key is a thread id
    var messages = [String: [Message]]() {
        didSet {
            self.notifyChanged()
        }
    }

    private func notifyChanged() {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("HackyRepository"), object: nil)
        }
    }

}
