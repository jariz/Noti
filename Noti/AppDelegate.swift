//
//  AppDelegate.swift
//  Noti
//
//  Created by Jari on 22/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa
import Starscream
import SwiftyBeaver
let log = SwiftyBeaver.self

@NSApplicationMain
class AppDelegate: NSObject, NSApplicationDelegate {
    
    var pushManager: PushManager?
    let userDefaults: UserDefaults = UserDefaults.standard
    var iwc:NSWindowController?;
    var pwc:NSWindowController?;
    
    func setPassword(password: String) {
        pushManager?.setPassword(password: password)
    }
    
    func loadPushManager() {
        let token = userDefaults.string(forKey: "token")
        
        if(token != nil) {
            pushManager = PushManager(token: token!)
        } else {
            print("WARN: PushManager not initialized because of missing token. Displaying Intro")
            
            if(pushManager != nil) {
                pushManager!.disconnect()
            }
            
            let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
            iwc = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "IntroWindowController")) as? NSWindowController
            NSApplication.shared.activate(ignoringOtherApps: true)
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
        
        let storyboard = NSStoryboard(name: NSStoryboard.Name(rawValue: "Main"), bundle: nil)
        pwc = storyboard.instantiateController(withIdentifier: NSStoryboard.SceneIdentifier(rawValue: "PreferencesWindowController")) as? NSWindowController
        NSApplication.shared.activate(ignoringOtherApps: true)
        pwc!.showWindow(self)
        pwc!.window?.makeKeyAndOrderFront(self)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        let file = FileDestination()  // Adding file destination of log output
        var url = try? FileManager.default.url(for: .libraryDirectory,      // getting ~/Library/
                                               in: .userDomainMask,
                                               appropriateFor: nil,
                                               create: true)
        url = url?.appendingPathComponent("Logs/Noti.log")
        file.logFileURL = url
        log.addDestination(file)
        loadPushManager()
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        // Insert code here to tear down your application
    }
    
    
}
