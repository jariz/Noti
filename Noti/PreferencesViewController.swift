//
//  NotificationPreferences.swift
//  Noti
//
//  Created by Jari on 01/10/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa
import Foundation
import EMCLoginItem

open class PreferencesViewController: NSViewController {
    @IBOutlet weak var sounds:NSArrayController!
    
    @IBOutlet weak var enableEncryption:NSButton!
    @IBOutlet weak var encryptionField:NSSecureTextField!
    
    @IBOutlet weak var systemStartup:NSButton!
    
    var appDelegate = NSApplication.shared().delegate as? AppDelegate
    var loginItem = EMCLoginItem()
    
    var FAKE_PASSWORD = "*********"
    
    override open func viewDidAppear() {
        if (self.view.window != nil) {
            self.view.window!.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
            self.view.window!.titlebarAppearsTransparent = true
            self.view.window!.isMovableByWindowBackground = true
            self.view.window!.invalidateShadow()
        }
    }
    
    @IBAction func encryptionEnabledChange(_ sender: NSButton) {
        encryptionField.isEnabled = sender.state == NSOnState
        if sender.state == NSOffState {
            UserDefaults.standard.removeObject(forKey: "secureKey")
            appDelegate?.pushManager?.initCrypt()
        }
    }
    
    @IBAction func systemStartupChange(_ sender: NSButton) {
        if sender.state == NSOnState {
            loginItem?.add()
        } else {
            loginItem?.remove()
        }
    }
    
    open override func controlTextDidChange(_ obj: Notification) {
        //gets called every time password changes
        
        if(encryptionField.stringValue == FAKE_PASSWORD) {
            return;
        } else if encryptionField.stringValue == "" {
            UserDefaults.standard.removeObject(forKey: "secureKey")
            enableEncryption.state = NSOffState
            encryptionField.isEnabled = false
            appDelegate?.pushManager?.initCrypt()
            return;
        }
        
        appDelegate?.pushManager?.setPassword(password: encryptionField.stringValue)
        print("Changed password, reinitializing crypt...")
        appDelegate?.pushManager?.initCrypt()
    }
    
    override open func viewDidLoad() {
        let fileManager = FileManager.default
        let enumerator:FileManager.DirectoryEnumerator = fileManager.enumerator(atPath: "/System/Library/Sounds")!
        
        while let element = enumerator.nextObject() as? NSString {
            sounds.addObject(element.deletingPathExtension)
        }
        
        let key = UserDefaults.standard.object(forKey: "secureKey")
        
        enableEncryption.state = key != nil ? NSOnState : NSOffState
        
        //indicate that encryption is enabled
        if key != nil {
            encryptionField.stringValue = FAKE_PASSWORD;
        }
        
        if let loginEnabled = loginItem?.isLoginItem() {
            systemStartup.state = loginEnabled  ? NSOnState : NSOffState
        }
    }
}
