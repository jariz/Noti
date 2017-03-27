//
//  ThreadTableCellView.swift
//  Noti
//
//  Created by Brian Clymer on 10/23/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Cocoa

class ThreadTableCellView: NSTableCellView {

    @IBOutlet var threadName: NSTextField!
    @IBOutlet var threadPreview: NSTextField!
    @IBOutlet var imageViewAvatar: NSImageView! {
        didSet {
            self.imageViewAvatar.layer?.cornerRadius = self.imageViewAvatar.frame.width / 2
            self.imageViewAvatar.layer?.masksToBounds = true
            self.imageViewAvatar.image = NSImage(imageLiteralResourceName: "AppIcon")
        }
    }
    
}
