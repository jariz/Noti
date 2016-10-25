//
//  NotificationPreferences.swift
//  Noti
//
//  Created by Jari on 01/10/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa


open class PreferencesViewController: NSViewController {
    @IBOutlet weak var sounds:NSArrayController!
    
    override open func viewDidAppear() {
        if (self.view.window != nil) {
            self.view.window!.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
            self.view.window!.titlebarAppearsTransparent = true;
            self.view.window!.isMovableByWindowBackground = true
            self.view.window!.invalidateShadow()
        }
    }
    
    override open func viewDidLoad() {
        let fileManager = FileManager.default
        let enumerator:FileManager.DirectoryEnumerator = fileManager.enumerator(atPath: "/System/Library/Sounds")!
        
        while let element = enumerator.nextObject() as? NSString {
            sounds.addObject(element.deletingPathExtension)
        }
        print(sounds.arrangedObjects)
    }
}
