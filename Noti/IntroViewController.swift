//
//  IntroViewController.swift
//  Noti
//
//  Created by Jari on 29/06/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Cocoa

class IntroViewController: NSViewController {
    var awc:NSWindowController?;
    
    override func viewDidAppear() {
        if (self.view.window != nil) {
            self.view.window!.appearance = NSAppearance(named: NSAppearanceNameVibrantDark)
            self.view.window!.titlebarAppearsTransparent = true;
            self.view.window!.movableByWindowBackground = true
            self.view.window!.invalidateShadow()
        }
    }
    
    @IBAction func startAuth(sender: AnyObject) {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        
        awc = storyboard.instantiateControllerWithIdentifier("AuthWindowController") as? NSWindowController
        print("showWindow")
        awc!.showWindow(self)
    }
}