//
//  Crypt.swift
//  Noti
//
//  Created by Jari on 12/07/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Foundation

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
        var rawBytes = [UInt8](count: rawData!.length / sizeof(UInt8), repeatedValue: 0)
        rawData?.getBytes(&rawBytes, length: rawBytes.count)
        
        let tag = NSData(bytes: [UInt8](rawBytes[1...16]))
        let iv = [UInt8](rawBytes[17...28])
        let message = [UInt8](rawBytes[29..<rawBytes.count])
        
        let res = try? CC.GCM.crypt(.decrypt, algorithm: .aes, data: NSData(bytes: message), key: NSData(bytes: key), iv: NSData(bytes: iv), aData: NSData(), tagLength: 16)
        if res == nil {
            return nil
        } else {
            //is the resulting tag correct?
            if tag == res!.1 {
                return String(data: res!.0, encoding: NSUTF8StringEncoding)
            } else {
                return nil
            }
        }
        
    }
    
}