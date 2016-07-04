//
//  AppDelegate.swift
//  Noti
//
//  Created by Jari on 22/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa
import Starscream

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var pushManager: PushManager?
    let userDefaults: NSUserDefaults = NSUserDefaults.standardUserDefaults()
    var iwc:NSWindowController?;
    
    func loadPushManager() {
        let token = userDefaults.stringForKey("token")
        
        if(token != nil) {
            pushManager = PushManager(token: token!)
        } else {
            print("WARN: PushManager not initialized because of missing token. Displaying Intro")
            
            if(pushManager != nil) {
                pushManager!.disconnect()
            }
            
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            iwc = storyboard.instantiateControllerWithIdentifier("IntroWindowController") as? NSWindowController
            iwc!.showWindow(self)
        }
    }
    
    @IBAction func reauthorize(sender: AnyObject?) {
        //delete token & restart push manager
        userDefaults.removeObjectForKey("token")
        loadPushManager()
    }

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        loadPushManager()
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


}

