//
//  StatusMenuController.swift
//  Noti
//
//  Created by Jari on 23/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Foundation
import Cocoa

class StatusMenuController: NSObject, NSUserNotificationCenterDelegate {
    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
    @IBOutlet weak var menu: NSMenu!
    
    override func awakeFromNib() {
        print("StatusMenuController alive")
        
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarButtonImage")
            statusItem.menu = menu;
        }
        
    }
    
    @IBAction func reauthorize(sender: AnyObject?) {
        //delete token & restart push manager
        let appDelegate = NSApplication.sharedApplication().delegate as! AppDelegate
        appDelegate.userDefaults.removeObjectForKey("token")
        appDelegate.loadPushManager()
    }
    
    @IBAction func setPassword(sender: AnyObject?) {
        let appDelegate = NSApplication.sharedApplication().delegate as! AppDelegate
        appDelegate.pushManager?.displayPasswordForm()
    }
    
    @IBAction func quit(sender: AnyObject?) {
        NSApplication.sharedApplication().terminate(self)
    }
}