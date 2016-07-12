//
//  Crypt.swift
//  Noti
//
//  Created by Jari on 12/07/16.
//  Copyright © 2016 Oberon. All rights reserved.
//

import Foundation
import CryptoSwift

public class Crypt {
    var key: [UInt8];
    
    init(key: [UInt8]) {
        self.key = key
    }
    
    static func generateKey(password: String, salt: String) -> [UInt8]? {
        let password: Array<UInt8> = password.utf8.map {$0}
        let salt: Array<UInt8> = salt.utf8.map {$0}
        print("Noti is generating a key!")
        return try? PKCS5.PBKDF2(password: password, salt: salt, iterations: 30000, keyLength: 32, hashVariant: .sha256).calculate()
    }
    
    func decryptMessage(cipher: String) -> String? {
        let rawData = NSData(base64EncodedString: cipher, options: NSDataBase64DecodingOptions(rawValue: 0))
        var rawBytes = [UInt8](count: rawData!.length / sizeof(UInt8), repeatedValue: 0)
        rawData?.getBytes(&rawBytes, length: rawBytes.count)
        
        let tag = [UInt8](rawBytes[1...16])
        let iv = [UInt8](rawBytes[17...28])
        let message = [UInt8](rawBytes[29..<rawBytes.count])
        
        let res = try? CC.GCM.crypt(.decrypt, algorithm: .aes, data: NSData(bytes: message), key: NSData(bytes: key), iv: NSData(bytes: iv), aData: NSData(), tagLength: 16)
        if res == nil {
            return nil
        } else {
            //todo tag verification
            return String(data: res!.0, encoding: NSUTF8StringEncoding)
        }
        
//        let input = NSData()
//        let decrypted = try! input.decrypt(AES(key: key!, iv: iv))
//
//        let decoded = NSString(data: decrypted, encoding: NSUTF8StringEncoding)
    }
    
}