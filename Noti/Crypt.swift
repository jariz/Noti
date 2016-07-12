//
//  Crypt.swift
//  Noti
//
//  Created by Jari on 12/07/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Foundation
import CryptoSwift

public class Crypt {
    var key: [UInt8];
    
    init(key: [UInt8]) {
        self.key = key
    }
    
    static func generateKey(password: String, salt: String) -> NSData? {
        print("Generating a new key...")
        return try? CC.KeyDerivation.PBKDF2(password, salt: salt.dataUsingEncoding(NSUTF8StringEncoding)!, prf: .sha256, rounds: 30000)
    }
    
    func decryptMessage(cipher: String) -> String? {
        let rawData = NSData(base64EncodedString: cipher, options: NSDataBase64DecodingOptions(rawValue: 0))
        var rawBytes = rawData!.toArray()
        
        let tag = NSData(bytes: [UInt8](rawBytes[1...16]))
        let iv = [UInt8](rawBytes[17...28])
        let message = [UInt8](rawBytes[29..<rawBytes.count])
        
        let res = try? CC.GCM.crypt(.decrypt, algorithm: .aes, data: NSData(bytes: message), key: NSData(bytes: key), iv: NSData(bytes: iv), aData: NSData(), tagLength: 16)
        if res == nil {
            return nil
        } else {
            //verify the resulting tag...
            if tag == res!.1 {
                return String(data: res!.0, encoding: NSUTF8StringEncoding)
            } else {
                return nil
            }
        }
    }
    
    func encryptMessage(message: String) -> String? {
        let iv = CC.generateRandom(12)
        let messageData = message.dataUsingEncoding(NSUTF8StringEncoding)!
        let res = try? CC.GCM.crypt(CC.OpMode.encrypt, algorithm: .aes, data: messageData, key: NSData(bytes: key), iv: iv, aData: NSData(), tagLength: 16)
        if res == nil {
            return nil
        }
        
        let tag = res!.1
        var data = [UInt8]()
        data.append(49) // 1
        data.appendContentsOf(tag.toArray())
        data.appendContentsOf(iv.toArray())
        data.appendContentsOf(res!.0.toArray())
        
        let out = NSData(bytes: data).base64EncodedStringWithOptions(NSDataBase64EncodingOptions.init(rawValue: 0))
        
        return out
    }
    
}

extension NSData {
    func toArray() -> [UInt8] {
        var bytes = [UInt8](count: self.length / sizeof(UInt8), repeatedValue: 0)
        self.getBytes(&bytes, length: bytes.count)
        return bytes
    }
}