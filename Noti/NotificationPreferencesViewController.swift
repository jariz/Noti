//
//  NotificationPreferences.swift
//  Noti
//
//  Created by Jari on 01/10/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa


public class NotificationPreferencesViewController: NSViewController {
    @IBOutlet weak var sounds:NSArrayController!
    
    override public func viewDidLoad() {
        let fileManager = NSFileManager.defaultManager()
        let enumerator:NSDirectoryEnumerator = fileManager.enumeratorAtPath("/System/Library/Sounds")!
        
        while let element = enumerator.nextObject() as? NSString {
            sounds.addObject(element.stringByDeletingPathExtension)
        }
        print(sounds.arrangedObjects)
    }
}