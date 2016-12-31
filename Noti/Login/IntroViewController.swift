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
            self.view.window!.isMovableByWindowBackground = true
            self.view.window!.invalidateShadow()
        }
        
        NotificationCenter.default.addObserver(self, selector: #selector(IntroViewController.authSuccess(_:)), name:NSNotification.Name(rawValue: "AuthSuccess"), object: nil)
    }
    
    @IBOutlet weak var authBtn:NSButton!;
    @IBOutlet weak var authTxt:NSTextField!;
    @IBOutlet weak var authImg:NSImageView!;
    
    func authSuccess(_ notification: Notification) {
        authBtn.isEnabled = false
        self.authTxt.alphaValue = 1
        self.authTxt.alphaValue = self.authBtn.alphaValue
        self.view.window!.styleMask.subtract(NSClosableWindowMask)
        
        NSAnimationContext.runAnimationGroup({ (context) -> Void in
            context.duration = 0.50
            self.authTxt.animator().alphaValue = 0
            self.authBtn.animator().alphaValue = 0
            
            }, completionHandler: { () -> Void in
                self.authTxt.isHidden = true
                self.authBtn.isHidden = true
                self.authImg.isHidden = false
                self.authImg.alphaValue = 0
                
                NSAnimationContext.runAnimationGroup({ (context) -> Void in
                    context.duration = 0.50
                    self.authImg.animator().alphaValue = 1
                }, completionHandler: nil)
                
        })
        
        Timer.scheduledTimer(timeInterval: 3, target: BlockOperation(block: self.view.window!.close), selector: #selector(Operation.main), userInfo: nil, repeats: false)

    }
    
    @IBAction func startAuth(_ sender: AnyObject) {
        let storyboard = NSStoryboard(name: "Main", bundle: nil)
        
        awc = storyboard.instantiateController(withIdentifier: "AuthWindowController") as? NSWindowController
        print("showWindow")
        awc!.showWindow(self)
    }
}
