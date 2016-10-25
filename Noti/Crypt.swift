//
//  Crypt.swift
//  Noti
//
//  Created by Jari on 12/07/16.
//  Copyright © 2016 Jari Zwarts. All rights reserved.
//

import Foundation
import CryptoSwift
import SwCrypt

open class Crypt {
    var key: [UInt8];
    
    init(key: [UInt8]) {
        self.key = key
    }
    
    static func generateKey(_ password: String, salt: String) -> [UInt8]? {
        print("Generating a new key...")
//        return try? PKCS5.PBKDF2(password: password.utf8.map {$0}, salt: salt.utf8.map {$0}, iterations: 30000, variant: .sha256).calculate()
        return try? CC.KeyDerivation.PBKDF2(password, salt: salt.data(using: String.Encoding.utf8)!, prf: .sha256, rounds: 30000)
    }
    
    func decryptMessage(_ cipher: String) -> String? {
        let rawData = Data(base64Encoded: cipher, options: NSData.Base64DecodingOptions(rawValue: 0))
        var rawBytes = rawData!.toArray()
        
        let tag = Data(bytes: [UInt8](rawBytes[1...16]))
        let iv = [UInt8](rawBytes[17...28])
        let message = [UInt8](rawBytes[29..<rawBytes.count])
//        message.decrypt(AES(key: key, iv: iv, blockMode: ., padding: <#T##Padding#>)
        let res = try? CC.GCM.crypt(.decrypt, algorithm: .aes, data: Data(bytes: message), key: Data(bytes: key), iv: Data(bytes: iv), aData: Data(), tagLength: 16)
        if res == nil {
            return nil
        } else {
            //verify the resulting tag...
            if tag == res!.1 {
                return String(data: res!.0, encoding: String.Encoding.utf8)
            } else {
                return nil
            }
        }
    }
    
    func encryptMessage(_ message: String) -> String? {
        let iv = CC.generateRandom(12)
        let messageData = message.data(using: String.Encoding.utf8)!
        let res = try? CC.GCM.crypt(CC.OpMode.encrypt, algorithm: .aes, data: messageData, key: Data(bytes: key), iv: iv, aData: Data(), tagLength: 16)
        if res == nil {
            return nil
        }
        
        let tag = res!.1
        var data = [UInt8]()
        data.append(49) // 1
        data.appendContentsOf(tag.toArray())
        data.append(contentsOf: iv.toArray())
        data.appendContentsOf(res!.0.toArray())
        
        let out = Data(bytes: data).base64EncodedStringWithOptions(NSData.Base64EncodingOptions.init(rawValue: 0))
        
        return out
    }
    
}

extension Data {
    func toArray() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: self.count / MemoryLayout<UInt8>.size)
        (self as NSData).getBytes(&bytes, length: bytes.count)
        return bytes
    }
}
