//
//  RoundedImage.swift
//  Noti
//
//  Created by Jari on 06/07/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//
//  Converted to Swift by me, taken from
//  https://github.com/venj/Cocoa-blog-code/blob/master/Round%20Corner%20Image/Round%20Corner%20Image/NSImage%2BRoundCorner.m
//

import Foundation
import Cocoa

class RoundedImage {
    internal static func addRoundedRectToPath(_ context:CGContext, rect:CGRect, ovalWidth:CGFloat, ovalHeight:CGFloat )
    {
        let fw:CGFloat, fh:CGFloat;
        if (ovalWidth == 0 || ovalHeight == 0) {
            context.addRect(rect);
            return;
        }
        context.saveGState();
        context.translateBy (x: rect.minX, y: rect.minY);
        context.scaleBy (x: ovalWidth, y: ovalHeight);
        fw = rect.width / ovalWidth;
        fh = rect.height / ovalHeight;
        context.move(to: CGPoint(x: fw, y: fh/2));
        context.addArc(tangent1End: CGPoint(x: fw, y: fh), tangent2End: CGPoint(x: fw / 2, y: fh), radius: 1)
        context.addArc(tangent1End: CGPoint(x: 0, y: fh), tangent2End: CGPoint(x: 0, y: fh / 2), radius: 1)
        context.addArc(tangent1End: CGPoint(x: 0, y: 0), tangent2End: CGPoint(x: fw / 2, y: 0), radius: 1)
        context.addArc(tangent1End: CGPoint(x: fw, y: 0), tangent2End: CGPoint(x: fw, y: fh / 2), radius: 1)
        context.closePath();
        context.restoreGState();
    }
    
    static func create(_ radius: Int, source: NSImage) -> NSImage {
        let w = source.size.width
        let h = source.size.height
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(data: nil, width: Int(w), height: Int(h), bitsPerComponent: 8, bytesPerRow: 4 * Int(w), space: colorSpace, bitmapInfo: 2)
        context?.beginPath()
        let rect = CGRect(x: 0, y: 0, width: w, height: h)
        addRoundedRectToPath(context!, rect: rect, ovalWidth: CGFloat(radius), ovalHeight: CGFloat(radius))
        context?.closePath()
        context?.clip()
        let cgImage = NSBitmapImageRep(data: source.tiffRepresentation!)!.cgImage!
        
        context?.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
        let imageMasked = context?.makeImage()
        let tmpImage = NSImage(cgImage: imageMasked!, size:source.size)
        let imageData = tmpImage.tiffRepresentation!
        let image = NSImage(data: imageData)
        return image!
    }
}
