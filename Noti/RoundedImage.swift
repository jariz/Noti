//
//  RoundedImage.swift
//  Noti
//
//  Created by Jari on 06/07/16.
//  Copyright © 2016 Oberon. All rights reserved.
//
//  Converted to Swift by me, taken from
//  https://github.com/venj/Cocoa-blog-code/blob/master/Round%20Corner%20Image/Round%20Corner%20Image/NSImage%2BRoundCorner.m
//

import Foundation
import Cocoa

class RoundedImage: NSImage {
    internal func addRoundedRectToPath(context:CGContextRef, rect:CGRect, ovalWidth:CGFloat, ovalHeight:CGFloat )
    {
        let fw:CGFloat, fh:CGFloat;
        if (ovalWidth == 0 || ovalHeight == 0) {
            CGContextAddRect(context, rect);
            return;
        }
        CGContextSaveGState(context);
        CGContextTranslateCTM (context, CGRectGetMinX(rect), CGRectGetMinY(rect));
        CGContextScaleCTM (context, ovalWidth, ovalHeight);
        fw = CGRectGetWidth (rect) / ovalWidth;
        fh = CGRectGetHeight (rect) / ovalHeight;
        CGContextMoveToPoint(context, fw, fh/2);
        CGContextAddArcToPoint(context, fw, fh, fw/2, fh, 1);
        CGContextAddArcToPoint(context, 0, fh, 0, fh/2, 1);
        CGContextAddArcToPoint(context, 0, 0, fw/2, 0, 1);
        CGContextAddArcToPoint(context, fw, 0, fw, fh/2, 1);
        CGContextClosePath(context);
        CGContextRestoreGState(context);
    }
    
    func withRoundCorners(radius: Int) -> NSImage {
        let w = self.size.width
        let h = self.size.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGBitmapContextCreate(nil, Int(w), Int(h), 8, 4 * Int(w), colorSpace, 2)
        CGContextBeginPath(context)
        let rect = CGRectMake(0, 0, w, h)
        addRoundedRectToPath(context!, rect: rect, ovalWidth: CGFloat(radius), ovalHeight: CGFloat(radius))
        CGContextClosePath(context)
        CGContextClip(context)
        let cgImage = NSBitmapImageRep(data: self.TIFFRepresentation!)!.CGImage!
        
        CGContextDrawImage(context, CGRectMake(0, 0, w, h), cgImage)
        let imageMasked = CGBitmapContextCreateImage(context)
//        CGContextRelease(context)
//        CGColorSpaceRelease(colorSpace)
        let tmpImage = NSImage(CGImage: imageMasked!, size:self.size)
        let imageData = tmpImage.TIFFRepresentation!
        let image = NSImage(data: imageData)
//        tmpImage.release()
        return image!
    }
}