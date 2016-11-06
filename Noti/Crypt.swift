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
    
    static func generateKey(_ password: String, salt: String) -> Data? {
        print("Generating a new key...")
        return try? CC.KeyDerivation.PBKDF2(password, salt: salt.data(using: String.Encoding.utf8)!, prf: .sha256, rounds: 30000)
    }
    
    func decryptMessage(_ cipher: String) -> String? {
        let rawData = Data(base64Encoded: cipher)
        var rawBytes = rawData!.toArray()
        
        let tag = Data(bytes: [UInt8](rawBytes[1...16]))
        let iv = [UInt8](rawBytes[17...28])
        let message = [UInt8](rawBytes[29..<rawBytes.count])
        
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
    
    func encryptMessage(message: String) -> String? {
        let iv = CC.generateRandom(12)
        let messageData = message.data(using: String.Encoding.utf8)!
        let res = try? CC.GCM.crypt(CC.OpMode.encrypt, algorithm: .aes, data: messageData, key: Data(bytes: key), iv: iv, aData: Data(), tagLength: 16)
        if res == nil {
            return nil
        }
        
        let tag = res!.1
        var data = [UInt8]()
        data.append(49) // 1
        data.append(contentsOf: tag.toArray())
        data.append(contentsOf: iv.toArray())
        data.append(contentsOf: res!.0.toArray())
        
        let out = Data(data).base64EncodedString();
        
        return out
    }
    
}

extension Data {
    func toArray() -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: self.count / MemoryLayout<UInt8>.size)
        self.copyBytes(to: &bytes, count: bytes.count)
        return bytes
    }
}
