//
//  StatusMenuController.swift
//  Noti
//
//  Created by Jari on 23/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Foundation
import Cocoa
import ImageIO

class StatusMenuController: NSObject, NSUserNotificationCenterDelegate {
    let statusItem = NSStatusBar.systemStatusBar().statusItemWithLength(NSVariableStatusItemLength)
    @IBOutlet weak var menu: NSMenu!
    @IBOutlet weak var menuItem: NSMenuItem!
    
    override func awakeFromNib() {
        print("StatusMenuController alive")
        
        if let button = statusItem.button {
            button.image = NSImage(named: "StatusBarButtonImage")
            statusItem.menu = menu;
        }
        menuItem.enabled = true
        
        NSNotificationCenter.defaultCenter().addObserver(self, selector: #selector(StatusMenuController.stateChange(_:)), name:"StateChange", object: nil)
    }
    
    func stateChange(notification: NSNotification) {
        
        if let info = notification.object as? [String: AnyObject] {
            if let title = info["title"] as? String {
                menuItem.title = title
            }
            
            if let disabled = info["disabled"] as? Bool {
                statusItem.button?.appearsDisabled = disabled
            }
            
            if let image = info["image"] as? NSImage {
                let destSize = NSMakeSize(CGFloat(20), CGFloat(20)), newImage = NSImage(size: destSize)
                newImage.lockFocus()
                image.drawInRect(NSMakeRect(0, 0, destSize.width, destSize.height), fromRect: NSMakeRect(0, 0, image.size.width, image.size.height), operation: NSCompositingOperation.CompositeSourceOver, fraction: CGFloat(1))
                newImage.unlockFocus()
                newImage.size = destSize
                let finalImage = NSImage(data: newImage.TIFFRepresentation!)!
                menuItem.image = finalImage
                
            } else {
                menuItem.image = nil
            }
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