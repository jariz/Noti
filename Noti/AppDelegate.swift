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

    private(set) var cache: HackyRepository!
    private(set) var pushManager: PushManager?
    private var iwc: NSWindowController?
    private var pwc: NSWindowController?

    func setPassword(password: String) {
        pushManager?.setPassword(password: password)
    }

    var messagingWindow: NSWindowController?
    
    func loadPushManager() {
        let token = UserDefaults.standard.string(forKey: "token")
        
        if let token = token {
            pushManager = PushManager(token: token)
        } else {
            print("WARN: PushManager not initialized because of missing token. Displaying Intro")

            pushManager?.disconnect()
            
            let storyboard = NSStoryboard(name: "Main", bundle: nil)
            iwc = storyboard.instantiateController(withIdentifier: "IntroWindowController") as? NSWindowController
            NSApplication.shared().activate(ignoringOtherApps: true)
            iwc!.showWindow(self)
            iwc!.window?.makeKeyAndOrderFront(self)
        }
    }

    func displayPreferencesWindow() {
        if(pushManager == nil) {
            let alert = NSAlert()
            alert.messageText = "Please authorize Noti before changing it's preferences."
            alert.runModal()
            return;
        }

        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        pwc = storyboard.instantiateController(withIdentifier: "PreferencesWindowController") as? NSWindowController
        NSApplication.shared().activate(ignoringOtherApps: true)
        pwc!.showWindow(self)
        pwc!.window?.makeKeyAndOrderFront(self)
    }

    func applicationDidFinishLaunching(_ aNotification: Notification) {
        self.cache = HackyRepository()
        loadPushManager()
    }

    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }

}

let SharedAppDelegate = NSApplication.shared().delegate as! AppDelegate
