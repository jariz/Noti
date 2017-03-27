//
//  MessagingWindow.swift
//  Noti
//
//  Created by Brian Clymer on 10/22/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Cocoa

class MessagingWindow: NSWindowController {

    var threadVc: ThreadsViewController?

    func setup(smsService: SmsService) {
        self.threadVc = ThreadsViewController(smsService: smsService, parentVc: nil)
        self.contentViewController = threadVc
    }

    override func windowDidLoad() {
        super.windowDidLoad()
        if let window = self.window {
            window.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
            window.invalidateShadow()
        }
    }
    
}
