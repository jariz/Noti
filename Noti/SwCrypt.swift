import Foundation

public class SwKeyStore {

	public enum SecError: OSStatus, ErrorType {
		case unimplemented = -4
		case param = -50
		case allocate = -108
		case notAvailable = -25291
		case authFailed = -25293
		case duplicateItem = -25299
		case itemNotFound = -25300
		case interactionNotAllowed = -25308
		case decode = -26275

		public static var debugLevel = 1

		init(_ status: OSStatus, function: String = #function, file: String = #file, line: Int = #line) {
			self = SecError(rawValue: status)!
			if SecError.debugLevel > 0 {
				print("\(file):\(line): [\(function)] \(self._domain): \(self) (\(self.rawValue))")
			}
		}
		init(_ type: SecError, function: String = #function, file: String = #file, line: Int = #line) {
			self = type
			if SecError.debugLevel > 0 {
				print("\(file):\(line): [\(function)] \(self._domain): \(self) (\(self.rawValue))")
			}
		}
	}

	public static func upsertKey(pemKey: String, keyTag: String,
	                             options: [NSString : AnyObject] = [:]) throws {
		let pemKeyAsData = pemKey.dataUsingEncoding(NSUTF8StringEncoding)!

		var parameters: [NSString : AnyObject] = [
			kSecClass: kSecClassKey,
			kSecAttrKeyType: kSecAttrKeyTypeRSA,
			kSecAttrIsPermanent: true,
			kSecAttrApplicationTag: keyTag,
			kSecValueData: pemKeyAsData
		]
		options.forEach { k, v in
			parameters[k] = v
		}

		var status = SecItemAdd(parameters, nil)
		if status == errSecDuplicateItem {
			try delKey(keyTag)
			status = SecItemAdd(parameters, nil)
		}
		guard status == errSecSuccess else { throw SecError(status) }
	}

	public static func getKey(keyTag: String) throws -> String {
		let parameters: [NSString : AnyObject] = [
			kSecClass : kSecClassKey,
			kSecAttrKeyType : kSecAttrKeyTypeRSA,
			kSecAttrApplicationTag : keyTag,
			kSecReturnData : true
		]
		var data: AnyObject?
		let status = SecItemCopyMatching(parameters, &data)
		guard status == errSecSuccess else { throw SecError(status) }

		guard let pemKeyAsData = data as? NSData else {
			throw SecError(.decode)
		}
		guard let result = String(data: pemKeyAsData, encoding: NSUTF8StringEncoding) else {
			throw SecError(.decode)
		}
		return result
	}

	public static func delKey(keyTag: String) throws {
		let parameters: [NSString : AnyObject] = [
			kSecClass : kSecClassKey,
			kSecAttrApplicationTag: keyTag
		]
		let status = SecItemDelete(parameters)
		guard status == errSecSuccess else { throw SecError(status) }
	}
}

public class SwKeyConvert {

	public enum Error: ErrorType {
		case invalidKey
		case badPassphrase
		case keyNotEncrypted

		public static var debugLevel = 1

		init(_ type: Error, function: String = #function, file: String = #file, line: Int = #line) {
			self = type
			if Error.debugLevel > 0 {
				print("\(file):\(line): [\(function)] \(self._domain): \(self)")
			}
		}
	}

	public class PrivateKey {

		public static func pemToPKCS1DER(pemKey: String) throws -> NSData {
			guard let derKey = try? PEM.PrivateKey.toDER(pemKey) else {
				throw Error(.invalidKey)
			}
			guard let pkcs1DERKey = PKCS8.PrivateKey.stripHeaderIfAny(derKey) else {
				throw Error(.invalidKey)
			}
			return pkcs1DERKey
		}

		public static func derToPKCS1PEM(derKey: NSData) -> String {
			return PEM.PrivateKey.toPEM(derKey)
		}

		public typealias EncMode = PEM.EncryptedPrivateKey.EncMode

		public static func encryptPEM(pemKey: String, passphrase: String,
		                              mode: EncMode) throws -> String {
			do {
				let derKey = try PEM.PrivateKey.toDER(pemKey)
				return PEM.EncryptedPrivateKey.toPEM(derKey, passphrase: passphrase, mode: mode)
			} catch {
				throw Error(.invalidKey)
			}
		}

		public static func decryptPEM(pemKey: String, passphrase: String) throws -> String {
			do {
				let derKey = try PEM.EncryptedPrivateKey.toDER(pemKey, passphrase: passphrase)
				return PEM.PrivateKey.toPEM(derKey)
			} catch PEM.Error.badPassphrase {
				throw Error(.badPassphrase)
			} catch PEM.Error.keyNotEncrypted {
				throw Error(.keyNotEncrypted)
			} catch {
				throw Error(.invalidKey)
			}
		}
	}

	public class PublicKey {

		public static func pemToPKCS1DER(pemKey: String) throws -> NSData {
			guard let derKey = try? PEM.PublicKey.toDER(pemKey) else {
				throw Error(.invalidKey)
			}
			guard let pkcs1DERKey = PKCS8.PublicKey.stripHeaderIfAny(derKey) else {
				throw Error(.invalidKey)
			}
			return pkcs1DERKey
		}

		public static func derToPKCS1PEM(derKey: NSData) -> String {
			return PEM.PublicKey.toPEM(derKey)
		}

		public static func derToPKCS8PEM(derKey: NSData) -> String {
			let pkcs8Key = PKCS8.PublicKey.addHeader(derKey)
			return PEM.PublicKey.toPEM(pkcs8Key)
		}

	}

}

public class PKCS8 {

	public class PrivateKey {

		//https://lapo.it/asn1js/
		public static func getPKCS1DEROffset(derKey: NSData) -> Int? {
			let bytes = derKey.bytesView

			var offset = 0
			guard bytes.length > offset else { return nil }
			guard bytes[offset] == 0x30 else { return nil }

			offset += 1

			guard bytes.length > offset else { return nil }
			if bytes[offset] > 0x80 {
				offset += Int(bytes[offset]) - 0x80
			}
			offset += 1

			guard bytes.length > offset else { return nil }
			guard bytes[offset] == 0x02 else { return nil }

			offset += 3

			//without PKCS8 header
			guard bytes.length > offset else { return nil }
			if bytes[offset] == 0x02 {
				return 0
			}

			let OID: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
			                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]

			guard bytes.length > offset + OID.count else { return nil }
			let slice = derKey.bytesViewRange(NSRange(location: offset, length: OID.count))

			guard OID.elementsEqual(slice) else { return nil }

			offset += OID.count

			guard bytes.length > offset else { return nil }
			guard bytes[offset] == 0x04 else { return nil }

			offset += 1

			guard bytes.length > offset else { return nil }
			if bytes[offset] > 0x80 {
				offset += Int(bytes[offset]) - 0x80
			}
			offset += 1

			guard bytes.length > offset else { return nil }
			guard bytes[offset] == 0x30 else { return nil }

			return offset
		}

		public static func stripHeaderIfAny(derKey: NSData) -> NSData? {
			guard let offset = getPKCS1DEROffset(derKey) else {
				return nil
			}
			return derKey.subdataWithRange(NSRange(location: offset, length: derKey.length - offset))
		}

		public static func hasCorrectHeader(derKey: NSData) -> Bool {
			return getPKCS1DEROffset(derKey) != nil
		}

	}

	public class PublicKey {

		public static func addHeader(derKey: NSData) -> NSData {
			let result = NSMutableData()

			let encodingLength: Int = encodedOctets(derKey.length + 1).count
			let OID: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
			                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]

			var builder: [UInt8] = []

			// ASN.1 SEQUENCE
			builder.append(0x30)

			// Overall size, made of OID + bitstring encoding + actual key
			let size = OID.count + 2 + encodingLength + derKey.length
			let encodedSize = encodedOctets(size)
			builder.appendContentsOf(encodedSize)
			result.appendBytes(builder, length: builder.count)
			result.appendBytes(OID, length: OID.count)
			builder.removeAll(keepCapacity: false)

			builder.append(0x03)
			builder.appendContentsOf(encodedOctets(derKey.length + 1))
			builder.append(0x00)
			result.appendBytes(builder, length: builder.count)

			// Actual key bytes
			result.appendData(derKey)

			return result as NSData
		}

		//https://lapo.it/asn1js/
		public static func getPKCS1DEROffset(derKey: NSData) -> Int? {
			let bytes = derKey.bytesView

			var offset = 0
			guard bytes.length > offset else { return nil }
			guard bytes[offset] == 0x30 else { return nil }

			offset += 1

			guard bytes.length > offset else { return nil }
			if bytes[offset] > 0x80 {
				offset += Int(bytes[offset]) - 0x80
			}
			offset += 1

			//without PKCS8 header
			guard bytes.length > offset else { return nil }
			if bytes[offset] == 0x02 {
				return 0
			}

			let OID: [UInt8] = [0x30, 0x0d, 0x06, 0x09, 0x2a, 0x86, 0x48, 0x86,
			                    0xf7, 0x0d, 0x01, 0x01, 0x01, 0x05, 0x00]

			guard bytes.length > offset + OID.count else { return nil }
			let slice = derKey.bytesViewRange(NSRange(location: offset, length: OID.count))

			guard OID.elementsEqual(slice) else { return nil }
			offset += OID.count

			// Type
			guard bytes.length > offset else { return nil }
			guard bytes[offset] == 0x03 else { return nil }

			offset += 1

			guard bytes.length > offset else { return nil }
			if bytes[offset] > 0x80 {
				offset += Int(bytes[offset]) - 0x80
			}
			offset += 1

			// Contents should be separated by a null from the header
			guard bytes.length > offset else { return nil }
			guard bytes[offset] == 0x00 else { return nil }

			offset += 1
			guard bytes.length > offset else { return nil }

			return offset
		}

		public static func stripHeaderIfAny(derKey: NSData) -> NSData? {
			guard let offset = getPKCS1DEROffset(derKey) else {
				return nil
			}
			return derKey.subdataWithRange(NSRange(location: offset, length: derKey.length - offset))
		}

		public static func hasCorrectHeader(derKey: NSData) -> Bool {
			return getPKCS1DEROffset(derKey) != nil
		}

		private static func encodedOctets(int: Int) -> [UInt8] {
			// Short form
			if int < 128 {
				return [UInt8(int)]
			}

			// Long form
			let i = (int / 256) + 1
			var len = int
			var result: [UInt8] = [UInt8(i + 0x80)]

			for _ in 0..<i {
				result.insert(UInt8(len & 0xFF), atIndex: 1)
				len = len >> 8
			}

			return result
		}
	}
}

public class PEM {

	public enum Error: ErrorType {
		case parse(String)
		case badPassphrase
		case keyNotEncrypted

		public static var debugLevel = 1

		init(_ type: Error, function: String = #function, file: String = #file, line: Int = #line) {
			self = type
			if Error.debugLevel > 0 {
				print("\(file):\(line): [\(function)] \(self._domain): \(self)")
			}
		}
	}

	public class PrivateKey {

		public static func toDER(pemKey: String) throws -> NSData {
			guard let strippedKey = stripHeader(pemKey) else {
				throw Error(.parse("header"))
			}
			guard let data = PEM.base64Decode(strippedKey) else {
				throw Error(.parse("base64decode"))
			}
			return data
		}

		public static func toPEM(derKey: NSData) -> String {
			let base64 = PEM.base64Encode(derKey)
			return addRSAHeader(base64)
		}

		private static let prefix = "-----BEGIN PRIVATE KEY-----\n"
		private static let suffix = "\n-----END PRIVATE KEY-----"
		private static let rsaPrefix = "-----BEGIN RSA PRIVATE KEY-----\n"
		private static let rsaSuffix = "\n-----END RSA PRIVATE KEY-----"

		private static func addHeader(base64: String) -> String {
			return prefix + base64 + suffix
		}

		private static func addRSAHeader(base64: String) -> String {
			return rsaPrefix + base64 + rsaSuffix
		}

		private static func stripHeader(pemKey: String) -> String? {
			return PEM.stripHeaderFooter(pemKey, header: prefix, footer: suffix) ??
				PEM.stripHeaderFooter(pemKey, header: rsaPrefix, footer: rsaSuffix)
		}
	}

	public class PublicKey {

		public static func toDER(pemKey: String) throws -> NSData {
			guard let strippedKey = stripHeader(pemKey) else {
				throw Error(.parse("header"))
			}
			guard let data = PEM.base64Decode(strippedKey) else {
				throw Error(.parse("base64decode"))
			}
			return data
		}

		public static func toPEM(derKey: NSData) -> String {
			let base64 = PEM.base64Encode(derKey)
			return addHeader(base64)
		}

		private static let pemPrefix = "-----BEGIN PUBLIC KEY-----\n"
		private static let pemSuffix = "\n-----END PUBLIC KEY-----"

		private static func addHeader(base64: String) -> String {
			return pemPrefix + base64 + pemSuffix
		}

		private static func stripHeader(pemKey: String) -> String? {
			return PEM.stripHeaderFooter(pemKey, header: pemPrefix, footer: pemSuffix)
		}
	}

	public class EncryptedPrivateKey {

		public enum EncMode {
			case aes128CBC, aes256CBC
		}

		public static func toDER(pemKey: String, passphrase: String) throws -> NSData {
			guard let strippedKey = PrivateKey.stripHeader(pemKey) else {
				throw Error(.parse("header"))
			}
			guard let mode = getEncMode(strippedKey) else {
				throw Error(.keyNotEncrypted)
			}
			guard let iv = getIV(strippedKey) else {
				throw Error(.parse("iv"))
			}
			let aesKey = getAESKey(mode, passphrase: passphrase, iv: iv)
			let base64Data = strippedKey.substringFromIndex(strippedKey.startIndex + aesHeaderLength)
			guard let data = PEM.base64Decode(base64Data) else {
				throw Error(.parse("base64decode"))
			}
			guard let decrypted = try? decryptKey(data, key: aesKey, iv: iv) else {
				throw Error(.badPassphrase)
			}
			guard PKCS8.PrivateKey.hasCorrectHeader(decrypted) else {
				throw Error(.badPassphrase)
			}
			return decrypted
		}

		public static func toPEM(derKey: NSData, passphrase: String, mode: EncMode) -> String {
			let iv = CC.generateRandom(16)
			let aesKey = getAESKey(mode, passphrase: passphrase, iv: iv)
			let encrypted = encryptKey(derKey, key: aesKey, iv: iv)
			let encryptedDERKey = addEncryptHeader(encrypted, iv: iv, mode: mode)
			return PrivateKey.addRSAHeader(encryptedDERKey)
		}

		private static let aes128CBCInfo = "Proc-Type: 4,ENCRYPTED\nDEK-Info: AES-128-CBC,"
		private static let aes256CBCInfo = "Proc-Type: 4,ENCRYPTED\nDEK-Info: AES-256-CBC,"
		private static let aesInfoLength = aes128CBCInfo.characters.count
		private static let aesIVInHexLength = 32
		private static let aesHeaderLength = aesInfoLength + aesIVInHexLength

		private static func addEncryptHeader(key: NSData, iv: NSData, mode: EncMode) -> String {
			return getHeader(mode) + iv.hexadecimalString() + "\n\n" + PEM.base64Encode(key)
		}

		private static func getHeader(mode: EncMode) -> String {
			switch mode {
			case .aes128CBC: return aes128CBCInfo
			case .aes256CBC: return aes256CBCInfo
			}
		}

		private static func getEncMode(strippedKey: String) -> EncMode? {
			if strippedKey.hasPrefix(aes128CBCInfo) {
				return .aes128CBC
			}
			if strippedKey.hasPrefix(aes256CBCInfo) {
				return .aes256CBC
			}
			return nil
		}

		private static func getIV(strippedKey: String) -> NSData? {
			let ivInHex = strippedKey.substringWithRange(
				strippedKey.startIndex + aesInfoLength ..< strippedKey.startIndex + aesHeaderLength)
			return ivInHex.dataFromHexadecimalString()
		}

		private static func getAESKey(mode: EncMode, passphrase: String, iv: NSData) -> NSData {
			switch mode {
			case .aes128CBC: return getAES128Key(passphrase, iv: iv)
			case .aes256CBC: return getAES256Key(passphrase, iv: iv)
			}
		}

		private static func getAES128Key(passphrase: String, iv: NSData) -> NSData {
			//128bit_Key = MD5(Passphrase + Salt)
			let pass = passphrase.dataUsingEncoding(NSUTF8StringEncoding)!
			let salt = iv.subdataWithRange(NSRange(location: 0, length: 8))

			let key = NSMutableData(data: pass)
			key.appendData(salt)
			return CC.digest(key, alg: .md5)
		}

		private static func getAES256Key(passphrase: String, iv: NSData) -> NSData {
			//128bit_Key = MD5(Passphrase + Salt)
			//256bit_Key = 128bit_Key + MD5(128bit_Key + Passphrase + Salt)
			let pass = passphrase.dataUsingEncoding(NSUTF8StringEncoding)!
			let salt = iv.subdataWithRange(NSRange(location: 0, length: 8))

			let first = NSMutableData(data: pass)
			first.appendData(salt)
			let aes128Key = CC.digest(first, alg: .md5)

			let sec = NSMutableData(data: aes128Key)
			sec.appendData(pass)
			sec.appendData(salt)

			let aes256Key = NSMutableData(data: aes128Key)
			aes256Key.appendData(CC.digest(sec, alg: .md5))
			return aes256Key
		}

		private static func encryptKey(data: NSData, key: NSData, iv: NSData) -> NSData {
			return try! CC.crypt(
				.encrypt, blockMode: .cbc, algorithm: .aes, padding: .pkcs7Padding,
				data: data, key: key, iv: iv)
		}

		private static func decryptKey(data: NSData, key: NSData, iv: NSData) throws -> NSData {
			return try CC.crypt(
				.decrypt, blockMode: .cbc, algorithm: .aes, padding: .pkcs7Padding,
				data: data, key: key, iv: iv)
		}

	}

	private static func stripHeaderFooter(data: String, header: String, footer: String) -> String? {
		guard data.hasPrefix(header) else {
			return nil
		}
		guard let r = data.rangeOfString(footer) else {
			return nil
		}
		return data.substringWithRange(header.endIndex..<r.startIndex)
	}

	private static func base64Decode(base64Data: String) -> NSData? {
		return NSData(base64EncodedString: base64Data, options: [.IgnoreUnknownCharacters])
	}

	private static func base64Encode(key: NSData) -> String {
		return key.base64EncodedStringWithOptions(
			[.Encoding64CharacterLineLength, .EncodingEndLineWithLineFeed])
	}

}

public class CC {

	public typealias CCCryptorStatus = Int32
	public enum CCError: CCCryptorStatus, ErrorType {
		case paramError = -4300
		case bufferTooSmall = -4301
		case memoryFailure = -4302
		case alignmentError = -4303
		case decodeError = -4304
		case unimplemented = -4305
		case overflow = -4306
		case rngFailure = -4307

		public static var debugLevel = 1

		init(_ status: CCCryptorStatus, function: String = #function,
		       file: String = #file, line: Int = #line) {
			self = CCError(rawValue: status)!
			if CCError.debugLevel > 0 {
				print("\(file):\(line): [\(function)] \(self._domain): \(self) (\(self.rawValue))")
			}
		}
		init(_ type: CCError, function: String = #function, file: String = #file, line: Int = #line) {
			self = type
			if CCError.debugLevel > 0 {
				print("\(file):\(line): [\(function)] \(self._domain): \(self) (\(self.rawValue))")
			}
		}
	}

	public static func generateRandom(size: Int) -> NSData {
		let data = NSMutableData(length: size)!
		CCRandomGenerateBytes!(bytes: data.mutableBytes, count: size)
		return data
	}

	public typealias CCDigestAlgorithm = UInt32
	public enum DigestAlgorithm: CCDigestAlgorithm {
		case none = 0
		case md5 = 3
		case rmd128 = 4, rmd160 = 5, rmd256 = 6, rmd320 = 7
		case sha1 = 8
		case sha224 = 9, sha256 = 10, sha384 = 11, sha512 = 12

		var length: Int {
			return CCDigestGetOutputSize!(algorithm: self.rawValue)
		}
	}

	public static func digest(data: NSData, alg: DigestAlgorithm) -> NSData {
		let output = NSMutableData(length: alg.length)!
		CCDigest!(algorithm: alg.rawValue,
		          data: data.bytes,
		          dataLen: data.length,
		          output: output.mutableBytes)
		return output
	}

	public typealias CCHmacAlgorithm = UInt32
	public enum HMACAlg: CCHmacAlgorithm {
		case sha1, md5, sha256, sha384, sha512, sha224

		var digestLength: Int {
			switch self {
			case .sha1: return 20
			case .md5: return 16
			case .sha256: return 32
			case .sha384: return 48
			case .sha512: return 64
			case .sha224: return 28
			}
		}
	}

	public static func HMAC(data: NSData, alg: HMACAlg, key: NSData) -> NSData {
		let buffer = NSMutableData(length: alg.digestLength)!
		CCHmac!(algorithm: alg.rawValue,
		       key: key.bytes, keyLength: key.length,
		       data: data.bytes, dataLength: data.length,
		       macOut: buffer.mutableBytes)
		return buffer
	}

	public typealias CCOperation = UInt32
	public enum OpMode: CCOperation {
		case encrypt = 0, decrypt
	}

	public typealias CCMode = UInt32
	public enum BlockMode: CCMode {
		case ecb = 1, cbc, cfb, ctr, f8, lrw, ofb, xts, rc4, cfb8
		var needIV: Bool {
			switch self {
			case .cbc, .cfb, .ctr, .ofb, .cfb8: return true
			default: return false
			}
		}
	}

	public enum AuthBlockMode: CCMode {
		case gcm = 11, ccm
	}

	public typealias CCAlgorithm = UInt32
	public enum Algorithm: CCAlgorithm {
		case aes = 0, des, threeDES, cast, rc4, rc2, blowfish

		var blockSize: Int? {
			switch self {
			case .aes: return 16
			case .des: return 8
			case .threeDES: return 8
			case .cast: return 8
			case .rc2: return 8
			case .blowfish: return 8
			default: return nil
			}
		}
	}

	public typealias CCPadding = UInt32
	public enum Padding: CCPadding {
		case noPadding = 0, pkcs7Padding
	}

	public static func crypt(opMode: OpMode, blockMode: BlockMode,
	                         algorithm: Algorithm, padding: Padding,
	                         data: NSData, key: NSData, iv: NSData) throws -> NSData {
		if blockMode.needIV {
			guard iv.length == algorithm.blockSize else { throw CCError(.paramError) }
		}

		var cryptor: CCCryptorRef = nil
		var status = CCCryptorCreateWithMode!(
			op: opMode.rawValue, mode: blockMode.rawValue,
			alg: algorithm.rawValue, padding: padding.rawValue,
			iv: iv.bytes, key: key.bytes, keyLength: key.length,
			tweak: nil, tweakLength: 0, numRounds: 0,
			options: CCModeOptions(), cryptorRef: &cryptor)
		guard status == noErr else { throw CCError(status) }

		defer { CCCryptorRelease!(cryptorRef: cryptor) }

		let needed = CCCryptorGetOutputLength!(cryptorRef: cryptor, inputLength: data.length, final: true)
		let result = NSMutableData(length: needed)!
		var updateLen: size_t = 0
		status = CCCryptorUpdate!(
			cryptorRef: cryptor,
			dataIn: data.bytes, dataInLength: data.length,
			dataOut: result.mutableBytes, dataOutAvailable: result.length,
			dataOutMoved: &updateLen)
		guard status == noErr else { throw CCError(status) }


		var finalLen: size_t = 0
		status = CCCryptorFinal!(
			cryptorRef: cryptor,
			dataOut: result.mutableBytes + updateLen,
			dataOutAvailable: result.length - updateLen,
			dataOutMoved: &finalLen)
		guard status == noErr else { throw CCError(status) }


		result.length = updateLen + finalLen
		return result
	}

	//The same behaviour as in the CCM pdf
	//http://csrc.nist.gov/publications/nistpubs/800-38C/SP800-38C_updated-July20_2007.pdf
	public static func cryptAuth(opMode: OpMode, blockMode: AuthBlockMode, algorithm: Algorithm,
	                             data: NSData, aData: NSData,
	                             key: NSData, iv: NSData, tagLength: Int) throws -> NSData {
		let cryptFun = blockMode == .gcm ? GCM.crypt : CCM.crypt
		if opMode == .encrypt {
			let (cipher, tag) = try cryptFun(opMode, algorithm: algorithm, data: data,
			                                 key: key, iv: iv, aData: aData, tagLength: tagLength)
			let result = NSMutableData(data: cipher)
			result.appendData(tag)
			return result
		} else {
			let cipher = data.subdataWithRange(NSRange(location: 0, length: data.length - tagLength))
			let tag = data.subdataWithRange(
				NSRange(location: data.length - tagLength, length: tagLength))
			let (plain, vTag) = try cryptFun(opMode, algorithm: algorithm, data: cipher,
			                                 key: key, iv: iv, aData: aData, tagLength: tagLength)
			guard tag == vTag else {
				throw CCError(.decodeError)
			}
			return plain
		}
	}

	public static func digestAvailable() -> Bool {
		return CCDigest != nil &&
			CCDigestGetOutputSize != nil
	}

	public static func randomAvailable() -> Bool {
		return CCRandomGenerateBytes != nil
	}

	public static func hmacAvailable() -> Bool {
		return CCHmac != nil
	}

	public static func cryptorAvailable() -> Bool {
		return CCCryptorCreateWithMode != nil &&
			CCCryptorGetOutputLength != nil &&
			CCCryptorUpdate != nil &&
			CCCryptorFinal != nil &&
			CCCryptorRelease != nil
	}

	public static func available() -> Bool {
		return digestAvailable() &&
			randomAvailable() &&
			hmacAvailable() &&
			cryptorAvailable() &&
			KeyDerivation.available() &&
			KeyWrap.available() &&
			RSA.available() &&
			DH.available() &&
			EC.available() &&
			CRC.available() &&
			CMAC.available() &&
			GCM.available() &&
			CCM.available()
	}

	private typealias CCCryptorRef = UnsafePointer<Void>
	private typealias CCRNGStatus = CCCryptorStatus
	private typealias CC_LONG = UInt32
	private typealias CCModeOptions = UInt32

	private typealias CCRandomGenerateBytesT = @convention(c) (
		bytes: UnsafeMutablePointer<Void>,
		count: size_t) -> CCRNGStatus
	private typealias CCDigestGetOutputSizeT = @convention(c) (
		algorithm: CCDigestAlgorithm) -> size_t
	private typealias CCDigestT = @convention(c) (
		algorithm: CCDigestAlgorithm,
		data: UnsafePointer<Void>,
		dataLen: size_t,
		output: UnsafeMutablePointer<Void>) -> CInt

	private typealias CCHmacT = @convention(c) (
		algorithm: CCHmacAlgorithm,
		key: UnsafePointer<Void>,
		keyLength: Int,
		data: UnsafePointer<Void>,
		dataLength: Int,
		macOut: UnsafeMutablePointer<Void>) -> Void
	private typealias CCCryptorCreateWithModeT = @convention(c)(
		op: CCOperation,
		mode: CCMode,
		alg: CCAlgorithm,
		padding: CCPadding,
		iv: UnsafePointer<Void>,
		key: UnsafePointer<Void>, keyLength: Int,
		tweak: UnsafePointer<Void>, tweakLength: Int,
		numRounds: Int32, options: CCModeOptions,
		cryptorRef: UnsafeMutablePointer<CCCryptorRef>) -> CCCryptorStatus
	private typealias CCCryptorGetOutputLengthT = @convention(c)(
		cryptorRef: CCCryptorRef,
		inputLength: size_t,
		final: Bool) -> size_t
	private typealias CCCryptorUpdateT = @convention(c)(
		cryptorRef: CCCryptorRef,
		dataIn: UnsafePointer<Void>,
		dataInLength: Int,
		dataOut: UnsafeMutablePointer<Void>,
		dataOutAvailable: Int,
		dataOutMoved: UnsafeMutablePointer<Int>) -> CCCryptorStatus
	private typealias CCCryptorFinalT = @convention(c)(
		cryptorRef: CCCryptorRef,
		dataOut: UnsafeMutablePointer<Void>,
		dataOutAvailable: Int,
		dataOutMoved: UnsafeMutablePointer<Int>) -> CCCryptorStatus
	private typealias CCCryptorReleaseT = @convention(c)
		(cryptorRef: CCCryptorRef) -> CCCryptorStatus


	private static let dl = dlopen("/usr/lib/system/libcommonCrypto.dylib", RTLD_NOW)
	private static let CCRandomGenerateBytes: CCRandomGenerateBytesT? =
		getFunc(dl, f: "CCRandomGenerateBytes")
	private static let CCDigestGetOutputSize: CCDigestGetOutputSizeT? =
		getFunc(dl, f: "CCDigestGetOutputSize")
	private static let CCDigest: CCDigestT? = getFunc(dl, f: "CCDigest")
	private static let CCHmac: CCHmacT? = getFunc(dl, f: "CCHmac")
	private static let CCCryptorCreateWithMode: CCCryptorCreateWithModeT? =
		getFunc(dl, f: "CCCryptorCreateWithMode")
	private static let CCCryptorGetOutputLength: CCCryptorGetOutputLengthT? =
		getFunc(dl, f: "CCCryptorGetOutputLength")
	private static let CCCryptorUpdate: CCCryptorUpdateT? =
		getFunc(dl, f: "CCCryptorUpdate")
	private static let CCCryptorFinal: CCCryptorFinalT? =
		getFunc(dl, f: "CCCryptorFinal")
	private static let CCCryptorRelease: CCCryptorReleaseT? =
		getFunc(dl, f: "CCCryptorRelease")

	public class GCM {

		public static func crypt(opMode: OpMode, algorithm: Algorithm, data: NSData,
		                         key: NSData, iv: NSData,
		                         aData: NSData, tagLength: Int) throws -> (NSData, NSData) {
			let result = NSMutableData(length: data.length)!
			var tagLength_ = tagLength
			let tag = NSMutableData(length: tagLength)!
			let status = CCCryptorGCM!(op: opMode.rawValue, alg: algorithm.rawValue,
				key: key.bytes, keyLength: key.length, iv: iv.bytes, ivLen: iv.length,
				aData: aData.bytes, aDataLen: aData.length,
				dataIn: data.bytes, dataInLength: data.length,
				dataOut: result.mutableBytes, tag: tag.bytes, tagLength: &tagLength_)
			guard status == noErr else { throw CCError(status) }

			tag.length = tagLength_
			return (result, tag)
		}

		public static func available() -> Bool {
			if CCCryptorGCM != nil {
				return true
			}
			return false
		}

		private typealias CCCryptorGCMT = @convention(c) (op: CCOperation, alg: CCAlgorithm,
			key: UnsafePointer<Void>, keyLength: Int,
			iv: UnsafePointer<Void>, ivLen: Int,
			aData: UnsafePointer<Void>, aDataLen: Int,
			dataIn: UnsafePointer<Void>, dataInLength: Int,
			dataOut: UnsafeMutablePointer<Void>,
			tag: UnsafePointer<Void>, tagLength: UnsafeMutablePointer<Int>) -> CCCryptorStatus
		private static let CCCryptorGCM: CCCryptorGCMT? = getFunc(dl, f: "CCCryptorGCM")

	}

	public class CCM {

		public static func crypt(opMode: OpMode, algorithm: Algorithm, data: NSData,
		                         key: NSData, iv: NSData,
		                         aData: NSData, tagLength: Int) throws -> (NSData, NSData) {
			var cryptor: CCCryptorRef = nil
			var status = CCCryptorCreateWithMode!(
				op: opMode.rawValue, mode: AuthBlockMode.ccm.rawValue,
				alg: algorithm.rawValue, padding: Padding.noPadding.rawValue,
				iv: nil, key: key.bytes, keyLength: key.length, tweak: nil, tweakLength: 0,
				numRounds: 0, options: CCModeOptions(), cryptorRef: &cryptor)
			guard status == noErr else { throw CCError(status) }
			defer { CCCryptorRelease!(cryptorRef: cryptor) }

			status = CCCryptorAddParameter!(cryptorRef: cryptor,
				parameter: Parameter.dataSize.rawValue, data: nil, dataLength: data.length)
			guard status == noErr else { throw CCError(status) }

			status = CCCryptorAddParameter!(cryptorRef: cryptor,
				parameter: Parameter.macSize.rawValue, data: nil, dataLength: tagLength)
			guard status == noErr else { throw CCError(status) }

			status = CCCryptorAddParameter!(cryptorRef: cryptor,
				parameter: Parameter.iv.rawValue, data: iv.bytes, dataLength: iv.length)
			guard status == noErr else { throw CCError(status) }

			status = CCCryptorAddParameter!(cryptorRef: cryptor,
				parameter: Parameter.authData.rawValue, data: aData.bytes, dataLength: aData.length)
			guard status == noErr else { throw CCError(status) }

			let result = NSMutableData(length: data.length)!

			var updateLen: size_t = 0
			status = CCCryptorUpdate!(
				cryptorRef: cryptor, dataIn: data.bytes, dataInLength: data.length,
				dataOut: result.mutableBytes, dataOutAvailable: result.length,
				dataOutMoved: &updateLen)
			guard status == noErr else { throw CCError(status) }

			var finalLen: size_t = 0
			status = CCCryptorFinal!(cryptorRef: cryptor, dataOut: result.mutableBytes + updateLen,
			                         dataOutAvailable: result.length - updateLen,
			                         dataOutMoved: &finalLen)
			guard status == noErr else { throw CCError(status) }

			result.length = updateLen + finalLen

			var tagLength_ = tagLength
			let tag = NSMutableData(length: tagLength)!
			status = CCCryptorGetParameter!(cryptorRef: cryptor, parameter: Parameter.authTag.rawValue,
			                                data: tag.bytes, dataLength: &tagLength_)
			guard status == noErr else { throw CCError(status) }

			tag.length = tagLength_

			return (result, tag)
		}

		public static func available() -> Bool {
			if CCCryptorAddParameter != nil &&
				CCCryptorGetParameter != nil {
				return true
			}
			return false
		}

		private typealias CCParameter = UInt32
		private enum Parameter: CCParameter {
			case iv, authData, macSize, dataSize, authTag
		}
		private typealias CCCryptorAddParameterT = @convention(c) (cryptorRef: CCCryptorRef,
			parameter: CCParameter,
			data: UnsafePointer<Void>, dataLength: size_t) -> CCCryptorStatus
		private static let CCCryptorAddParameter: CCCryptorAddParameterT? =
			getFunc(dl, f: "CCCryptorAddParameter")

		private typealias CCCryptorGetParameterT = @convention(c) (cryptorRef: CCCryptorRef,
			parameter: CCParameter,
			data: UnsafePointer<Void>, dataLength: UnsafeMutablePointer<size_t>) -> CCCryptorStatus
		private static let CCCryptorGetParameter: CCCryptorGetParameterT? =
			getFunc(dl, f: "CCCryptorGetParameter")
	}

	public class RSA {

		public typealias CCAsymmetricPadding = UInt32

		public enum AsymmetricPadding: CCAsymmetricPadding {
			case pkcs1 = 1001
			case oaep = 1002
		}

		public enum AsymmetricSAPadding: UInt32 {
			case pkcs15 = 1001
			case pss = 1002
		}

		public static func generateKeyPair(keySize: Int = 4096) throws -> (NSData, NSData) {
			var privateKey: CCRSACryptorRef = nil
			var publicKey: CCRSACryptorRef = nil
			let status = CCRSACryptorGeneratePair!(
				keySize: keySize,
				e: 65537,
				publicKey: &publicKey,
				privateKey: &privateKey)
			guard status == noErr else { throw CCError(status) }

			defer {
				CCRSACryptorRelease!(privateKey)
				CCRSACryptorRelease!(publicKey)
			}

			let privDERKey = try exportToDERKey(privateKey)
			let pubDERKey = try exportToDERKey(publicKey)

			return (privDERKey, pubDERKey)
		}

		public static func encrypt(data: NSData, derKey: NSData, tag: NSData, padding: AsymmetricPadding,
		                           digest: DigestAlgorithm) throws -> NSData {
			let key = try importFromDERKey(derKey)
			defer { CCRSACryptorRelease!(key) }

			var bufferSize = getKeySize(key)
			let buffer = NSMutableData(length: bufferSize)!

			let status = CCRSACryptorEncrypt!(
				publicKey: key,
				padding: padding.rawValue,
				plainText: data.bytes,
				plainTextLen: data.length,
				cipherText: buffer.mutableBytes,
				cipherTextLen: &bufferSize,
				tagData: tag.bytes, tagDataLen: tag.length,
				digestType: digest.rawValue)
			guard status == noErr else { throw CCError(status) }


			buffer.length = bufferSize

			return buffer
		}

		public static func decrypt(data: NSData, derKey: NSData, tag: NSData, padding: AsymmetricPadding,
		                           digest: DigestAlgorithm) throws -> (NSData, Int) {
			let key = try importFromDERKey(derKey)
			defer { CCRSACryptorRelease!(key) }

			let blockSize = getKeySize(key)

			var bufferSize = blockSize
			let buffer = NSMutableData(length: bufferSize)!

			let status = CCRSACryptorDecrypt!(
				privateKey: key,
				padding: padding.rawValue,
				cipherText: data.bytes,
				cipherTextLen: bufferSize,
				plainText: buffer.mutableBytes,
				plainTextLen: &bufferSize,
				tagData: tag.bytes, tagDataLen: tag.length,
				digestType: digest.rawValue)
			guard status == noErr else { throw CCError(status) }
			buffer.length = bufferSize

			return (buffer, blockSize)
		}

		private static func importFromDERKey(derKey: NSData) throws -> CCRSACryptorRef {
			var key: CCRSACryptorRef = nil
			let status = CCRSACryptorImport!(
				keyPackage: derKey.bytes,
				keyPackageLen: derKey.length,
				key: &key)
			guard status == noErr else { throw CCError(status) }

			return key
		}

		private static func exportToDERKey(key: CCRSACryptorRef) throws -> NSData {
			var derKeyLength = 8192
			let derKey = NSMutableData(length: derKeyLength)!
			let status = CCRSACryptorExport!(
				key: key,
				out: derKey.mutableBytes,
				outLen: &derKeyLength)
			guard status == noErr else { throw CCError(status) }

			derKey.length = derKeyLength
			return derKey
		}

		private static func getKeyType(key: CCRSACryptorRef) -> KeyType {
			return KeyType(rawValue: CCRSAGetKeyType!(key))!
		}

		private static func getKeySize(key: CCRSACryptorRef) -> Int {
			return Int(CCRSAGetKeySize!(key)/8)
		}

		public static func sign(message: NSData, derKey: NSData, padding: AsymmetricSAPadding,
		                        digest: DigestAlgorithm, saltLen: Int) throws -> NSData {
			let key = try importFromDERKey(derKey)
			defer { CCRSACryptorRelease!(key) }
			guard getKeyType(key) == .privateKey else { throw CCError(.paramError) }

			let keySize = getKeySize(key)

			switch padding {
			case .pkcs15:
				let hash = CC.digest(message, alg: digest)
				var signedDataLength = keySize
				let signedData = NSMutableData(length:signedDataLength)!
				let status = CCRSACryptorSign!(
					privateKey: key,
					padding: AsymmetricPadding.pkcs1.rawValue,
					hashToSign: hash.bytes, hashSignLen: hash.length,
					digestType: digest.rawValue, saltLen: 0 /*unused*/,
					signedData: signedData.mutableBytes, signedDataLen: &signedDataLength)
				guard status == noErr else { throw CCError(status) }

				signedData.length = signedDataLength
				return signedData
			case .pss:
				let encMessage = try add_pss_padding(
					digest,
					saltLength: saltLen,
					keyLength: keySize,
					message: message)
				return try crypt(encMessage, key: key)
			}
		}

		public static func verify(message: NSData, derKey: NSData, padding: AsymmetricSAPadding,
		                          digest: DigestAlgorithm, saltLen: Int,
		                          signedData: NSData) throws -> Bool {
			let key = try importFromDERKey(derKey)
			defer { CCRSACryptorRelease!(key) }
			guard getKeyType(key) == .publicKey else { throw CCError(.paramError) }

			let keySize = getKeySize(key)

			switch padding {
			case .pkcs15:
				let hash = CC.digest(message, alg: digest)
				let status = CCRSACryptorVerify!(
					publicKey: key,
					padding: padding.rawValue,
					hash: hash.bytes, hashLen: hash.length,
					digestType: digest.rawValue, saltLen: 0 /*unused*/,
					signedData: signedData.bytes, signedDataLen:signedData.length)
				let kCCNotVerified: CCCryptorStatus = -4306
				if status == kCCNotVerified {
					return false
				}
				guard status == noErr else { throw CCError(status) }
				return true
			case .pss:
				let encoded = try crypt(signedData, key:key)
				return try verify_pss_padding(
					digest,
					saltLength: saltLen,
					keyLength: keySize,
					message: message,
					encMessage: encoded)
			}
		}

		private static func crypt(data: NSData, key: CCRSACryptorRef) throws -> NSData {
			var outLength = data.length
			let out = NSMutableData(length: outLength)!
			let status = CCRSACryptorCrypt!(
				rsaKey: key,
				data: data.bytes, dataLength: data.length,
				out: out.mutableBytes, outLength: &outLength)
			guard status == noErr else { throw CCError(status) }
			out.length = outLength

			return out
		}

		private static func mgf1(digest: DigestAlgorithm,
		                         seed: NSData, maskLength: Int) -> NSMutableData {
			let tseed = NSMutableData(data: seed)
			tseed.increaseLengthBy(4)

			var interval = maskLength / digest.length
			if  maskLength % digest.length != 0 {
				interval += 1
			}

			func pack(n: Int) -> [UInt8] {
				return [
					UInt8(n>>24 & 0xff),
					UInt8(n>>16 & 0xff),
					UInt8(n>>8 & 0xff),
					UInt8(n>>0 & 0xff)
				]
			}

			let mask = NSMutableData()
			for counter in 0 ..< interval {
				tseed.replaceBytesInRange(NSRange(location: tseed.length - 4, length: 4),
				                          withBytes: pack(counter))
				mask.appendData(CC.digest(tseed, alg: digest))
			}
			mask.length = maskLength
			return mask
		}

		private static func xorData(data1: NSData, _ data2: NSData) -> NSMutableData {
			precondition(data1.length == data2.length)

			let ret = NSMutableData(length:data1.length)!
			let r = UnsafeMutablePointer<UInt8>(ret.mutableBytes)

			let bytes1 = UnsafePointer<UInt8>(data1.bytes)
			let bytes2 = UnsafePointer<UInt8>(data2.bytes)
			for i in 0 ..< ret.length {
				r[i] = bytes1[i] ^ bytes2[i]
			}
			return ret
		}

		private static func add_pss_padding(digest: DigestAlgorithm,
		                                   saltLength: Int,
		                                   keyLength: Int,
		                                   message: NSData) throws -> NSData {

			if keyLength < 16 || saltLength < 0 {
				throw CCError(.paramError)
			}

			// The maximal bit size of a non-negative integer is one less than the bit
			// size of the key since the first bit is used to store sign
			let emBits = keyLength * 8  - 1
			var emLength = emBits / 8
			if emBits % 8 != 0 {
				emLength += 1
			}

			let hash = CC.digest(message, alg: digest)

			if emLength < hash.length + saltLength + 2 {
				throw CCError(.paramError)
			}

			let salt = CC.generateRandom(saltLength)

			let mPrime = NSMutableData(length: 8)!
			mPrime.appendData(hash)
			mPrime.appendData(salt)
			let mPrimeHash = CC.digest(mPrime, alg: digest)

			let padding = NSMutableData(length: emLength - saltLength - hash.length - 2)!
			let db = NSMutableData(data: padding)
			db.appendBytes([0x01] as [UInt8], length: 1)
			db.appendData(salt)
			let dbMask = mgf1(digest, seed: mPrimeHash, maskLength: emLength - hash.length - 1)
			let maskedDB = xorData(db, dbMask)

			let zeroBits = 8 * emLength - emBits
			UnsafeMutablePointer<UInt8>(maskedDB.mutableBytes)[0] &= UInt8(0xff >> zeroBits)

			let ret = NSMutableData(data:maskedDB)
			ret.appendData(mPrimeHash)
			ret.appendBytes([0xBC] as [UInt8], length: 1)
			return ret
		}

		private static func verify_pss_padding(digest: DigestAlgorithm,
		                                      saltLength: Int, keyLength: Int,
		                                      message: NSData, encMessage: NSData) throws -> Bool {
			if keyLength < 16 || saltLength < 0 {
				throw CCError(.paramError)
			}

			guard encMessage.length > 0 else {
				return false
			}

			let emBits = keyLength * 8  - 1
			var emLength = emBits / 8
			if emBits % 8 != 0 {
				emLength += 1
			}

			let hash = CC.digest(message, alg: digest)

			if emLength < hash.length + saltLength + 2 {
				return false
			}
			if encMessage.bytesView[encMessage.length-1] != 0xBC {
				return false
			}
			let zeroBits = 8 * emLength - emBits
			let zeroBitsM = 8 - zeroBits
			let maskedDBLength = emLength - hash.length - 1
			let maskedDB = encMessage.subdataWithRange(NSRange(location: 0, length: maskedDBLength))
			if Int(maskedDB.bytesView[0]) >> zeroBitsM != 0 {
				return false
			}
			let mPrimeHash = encMessage.subdataWithRange(
				NSRange(location: maskedDBLength, length: hash.length))
			let dbMask = mgf1(digest, seed: mPrimeHash, maskLength: emLength - hash.length - 1)
			let db = xorData(maskedDB, dbMask)
			UnsafeMutablePointer<UInt8>(db.mutableBytes)[0] &= UInt8(0xff >> zeroBits)

			let zeroLength = emLength - hash.length - saltLength - 2
			let zeroString = NSMutableData(length:zeroLength)
			if db.subdataWithRange(NSRange(location: 0, length: zeroLength)) != zeroString {
				return false
			}
			if db.bytesView[zeroLength] != 0x01 {
				return false
			}
			let salt = db.subdataWithRange(
				NSRange(location:db.length - saltLength, length:saltLength))
			let mPrime = NSMutableData(length:8)!
			mPrime.appendData(hash)
			mPrime.appendData(salt)
			let mPrimeHash2 = CC.digest(mPrime, alg: digest)
			if mPrimeHash != mPrimeHash2 {
				return false
			}
			return true
		}


		public static func available() -> Bool {
			return CCRSACryptorGeneratePair != nil &&
				CCRSACryptorRelease != nil &&
				CCRSAGetKeyType != nil &&
				CCRSAGetKeySize != nil &&
				CCRSACryptorEncrypt != nil &&
				CCRSACryptorDecrypt != nil &&
				CCRSACryptorExport != nil &&
				CCRSACryptorImport != nil &&
				CCRSACryptorSign != nil &&
				CCRSACryptorVerify != nil &&
				CCRSACryptorCrypt != nil
		}

		private typealias CCRSACryptorRef = UnsafePointer<Void>
		private typealias CCRSAKeyType = UInt32
		private enum KeyType: CCRSAKeyType {
			case publicKey = 0, privateKey
			case blankPublicKey = 97, blankPrivateKey
			case badKey = 99
		}

		private typealias CCRSACryptorGeneratePairT = @convention(c) (
			keySize: Int,
			e: UInt32,
			publicKey: UnsafeMutablePointer<CCRSACryptorRef>,
			privateKey: UnsafeMutablePointer<CCRSACryptorRef>) -> CCCryptorStatus
		private static let CCRSACryptorGeneratePair: CCRSACryptorGeneratePairT? =
			getFunc(CC.dl, f: "CCRSACryptorGeneratePair")

		private typealias CCRSACryptorReleaseT = @convention(c) (CCRSACryptorRef) -> Void
		private static let CCRSACryptorRelease: CCRSACryptorReleaseT? =
			getFunc(dl, f: "CCRSACryptorRelease")

		private typealias CCRSAGetKeyTypeT = @convention(c) (CCRSACryptorRef) -> CCRSAKeyType
		private static let CCRSAGetKeyType: CCRSAGetKeyTypeT? = getFunc(dl, f: "CCRSAGetKeyType")

		private typealias CCRSAGetKeySizeT = @convention(c) (CCRSACryptorRef) -> Int32
		private static let CCRSAGetKeySize: CCRSAGetKeySizeT? = getFunc(dl, f: "CCRSAGetKeySize")

		private typealias CCRSACryptorEncryptT = @convention(c) (
			publicKey: CCRSACryptorRef,
			padding: CCAsymmetricPadding,
			plainText: UnsafePointer<Void>,
			plainTextLen: Int,
			cipherText: UnsafeMutablePointer<Void>,
			cipherTextLen: UnsafeMutablePointer<Int>,
			tagData: UnsafePointer<Void>,
			tagDataLen: Int,
			digestType: CCDigestAlgorithm) -> CCCryptorStatus
		private static let CCRSACryptorEncrypt: CCRSACryptorEncryptT? =
			getFunc(dl, f: "CCRSACryptorEncrypt")

		private typealias CCRSACryptorDecryptT = @convention (c) (
			privateKey: CCRSACryptorRef,
			padding: CCAsymmetricPadding,
			cipherText: UnsafePointer<Void>,
			cipherTextLen: Int,
			plainText: UnsafeMutablePointer<Void>,
			plainTextLen: UnsafeMutablePointer<Int>,
			tagData: UnsafePointer<Void>,
			tagDataLen: Int,
			digestType: CCDigestAlgorithm) -> CCCryptorStatus
		private static let CCRSACryptorDecrypt: CCRSACryptorDecryptT? =
			getFunc(dl, f: "CCRSACryptorDecrypt")

		private typealias CCRSACryptorExportT = @convention(c) (
			key: CCRSACryptorRef,
			out: UnsafeMutablePointer<Void>,
			outLen: UnsafeMutablePointer<Int>) -> CCCryptorStatus
		private static let CCRSACryptorExport: CCRSACryptorExportT? =
			getFunc(dl, f: "CCRSACryptorExport")

		private typealias CCRSACryptorImportT = @convention(c) (
			keyPackage: UnsafePointer<Void>,
			keyPackageLen: Int,
			key: UnsafeMutablePointer<CCRSACryptorRef>) -> CCCryptorStatus
		private static let CCRSACryptorImport: CCRSACryptorImportT? =
			getFunc(dl, f: "CCRSACryptorImport")

		private typealias CCRSACryptorSignT = @convention(c) (
			privateKey: CCRSACryptorRef,
			padding: CCAsymmetricPadding,
			hashToSign: UnsafePointer<Void>,
			hashSignLen: size_t,
			digestType: CCDigestAlgorithm,
			saltLen: size_t,
			signedData: UnsafeMutablePointer<Void>,
			signedDataLen: UnsafeMutablePointer<Int>) -> CCCryptorStatus
		private static let CCRSACryptorSign: CCRSACryptorSignT? =
			getFunc(dl, f: "CCRSACryptorSign")

		private typealias CCRSACryptorVerifyT = @convention(c) (
			publicKey: CCRSACryptorRef,
			padding: CCAsymmetricPadding,
			hash: UnsafePointer<Void>,
			hashLen: size_t,
			digestType: CCDigestAlgorithm,
			saltLen: size_t,
			signedData: UnsafePointer<Void>,
			signedDataLen: size_t) -> CCCryptorStatus
		private static let CCRSACryptorVerify: CCRSACryptorVerifyT? =
			getFunc(dl, f: "CCRSACryptorVerify")

		private typealias CCRSACryptorCryptT = @convention(c) (
			rsaKey: CCRSACryptorRef,
			data: UnsafePointer<Void>, dataLength: size_t,
			out: UnsafeMutablePointer<Void>,
			outLength: UnsafeMutablePointer<size_t>) -> CCCryptorStatus
		private static let CCRSACryptorCrypt: CCRSACryptorCryptT? =
			getFunc(dl, f: "CCRSACryptorCrypt")
	}

	public class DH {

		public enum DHParam {
			case rfc3526Group5
		}

		//this is stateful in CommonCrypto too, sry
		public class DH {
			private var ref: CCDHRef = nil

			public init(dhParam: DHParam) throws {
				ref = CCDHCreate!(dhParameter: kCCDHRFC3526Group5!)
				guard ref != nil else {
					throw CCError(.paramError)
				}
			}

			public func generateKey() throws -> NSData {
				var outputLength = 8192
				let output = NSMutableData(length: outputLength)!
				let status = CCDHGenerateKey!(
					ref: ref,
					output: output.mutableBytes, outputLength: &outputLength)
				output.length = outputLength
				guard status != -1 else {
					throw CCError(.paramError)
				}
				return output
			}

			public func computeKey(peerKey: NSData) throws -> NSData {
				var sharedKeyLength = 8192
				let sharedKey = NSMutableData(length: sharedKeyLength)!
				let status = CCDHComputeKey!(
					sharedKey: sharedKey.mutableBytes, sharedKeyLen: &sharedKeyLength,
					peerPubKey: peerKey.bytes, peerPubKeyLen: peerKey.length,
					ref: ref)
				sharedKey.length = sharedKeyLength
				guard status == 0 else {
					throw CCError(.paramError)
				}
				return sharedKey
			}

			deinit {
				if ref != nil {
					CCDHRelease!(ref: ref)
				}
			}
		}


		public static func available() -> Bool {
			return CCDHCreate != nil &&
				CCDHRelease != nil &&
				CCDHGenerateKey != nil &&
				CCDHComputeKey != nil
		}

		private typealias CCDHParameters = UnsafePointer<Void>
		private typealias CCDHRef = UnsafePointer<Void>

		private typealias kCCDHRFC3526Group5TM = UnsafePointer<CCDHParameters>
		private static let kCCDHRFC3526Group5M: kCCDHRFC3526Group5TM? =
			getFunc(dl, f: "kCCDHRFC3526Group5")
		private static let kCCDHRFC3526Group5 = kCCDHRFC3526Group5M?.memory

		private typealias CCDHCreateT = @convention(c) (
			dhParameter: CCDHParameters) -> CCDHRef
		private static let CCDHCreate: CCDHCreateT? = getFunc(dl, f: "CCDHCreate")

		private typealias CCDHReleaseT = @convention(c) (
			ref: CCDHRef) -> Void
		private static let CCDHRelease: CCDHReleaseT? = getFunc(dl, f: "CCDHRelease")

		private typealias CCDHGenerateKeyT = @convention(c) (
			ref: CCDHRef,
			output: UnsafeMutablePointer<Void>, outputLength: UnsafeMutablePointer<size_t>) -> CInt
		private static let CCDHGenerateKey: CCDHGenerateKeyT? = getFunc(dl, f: "CCDHGenerateKey")

		private typealias CCDHComputeKeyT = @convention(c) (
			sharedKey: UnsafeMutablePointer<Void>, sharedKeyLen: UnsafeMutablePointer<size_t>,
			peerPubKey: UnsafePointer<Void>, peerPubKeyLen: size_t,
			ref: CCDHRef) -> CInt
		private static let CCDHComputeKey: CCDHComputeKeyT? = getFunc(dl, f: "CCDHComputeKey")
	}

	public class EC {

		public static func generateKeyPair(keySize: Int) throws -> (NSData, NSData) {
			var privKey: CCECCryptorRef = nil
			var pubKey: CCECCryptorRef = nil
			let status = CCECCryptorGeneratePair!(
				keySize: keySize,
				publicKey: &pubKey,
				privateKey: &privKey)
			guard status == noErr else { throw CCError(status) }

			defer {
				CCECCryptorRelease!(key: privKey)
				CCECCryptorRelease!(key: pubKey)
			}

			let privKeyDER = try exportKey(privKey, format: .importKeyBinary, type: .keyPrivate)
			let pubKeyDER = try exportKey(pubKey, format: .importKeyBinary, type: .keyPublic)
			return (privKeyDER, pubKeyDER)
		}

		public static func signHash(privateKey: NSData, hash: NSData) throws -> NSData {
			let privKey = try importKey(privateKey, format: .importKeyBinary, keyType: .keyPrivate)
			defer { CCECCryptorRelease!(key: privKey) }

			var signedDataLength = 4096
			let signedData = NSMutableData(length:signedDataLength)!
			let status = CCECCryptorSignHash!(
				privateKey: privKey,
				hashToSign: hash.bytes, hashSignLen: hash.length,
				signedData: signedData.mutableBytes, signedDataLen: &signedDataLength)
			guard status == noErr else { throw CCError(status) }

			signedData.length = signedDataLength
			return signedData
		}

		public static func verifyHash(publicKey: NSData,
		                              hash: NSData,
		                              signedData: NSData) throws -> Bool {
			let pubKey = try importKey(publicKey, format: .importKeyBinary, keyType: .keyPublic)
			defer { CCECCryptorRelease!(key: pubKey) }

			var valid: UInt32 = 0
			let status = CCECCryptorVerifyHash!(
				publicKey:pubKey,
				hash: hash.bytes, hashLen: hash.length,
				signedData: signedData.bytes, signedDataLen: signedData.length,
				valid: &valid)
			guard status == noErr else { throw CCError(status) }

			return valid != 0
		}

		public static func computeSharedSecret(privateKey: NSData,
		                                       publicKey: NSData) throws -> NSData {
			let privKey = try importKey(privateKey, format: .importKeyBinary, keyType: .keyPrivate)
			let pubKey = try importKey(publicKey, format: .importKeyBinary, keyType: .keyPublic)
			defer {
				CCECCryptorRelease!(key: privKey)
				CCECCryptorRelease!(key: pubKey)
			}

			var outSize = 8192
			let result = NSMutableData(length:outSize)!
			let status = CCECCryptorComputeSharedSecret!(
				privateKey: privKey, publicKey: pubKey, out:result.mutableBytes, outLen:&outSize)
			guard status == noErr else { throw CCError(status) }

			result.length = outSize
			return result
		}

		private static func importKey(key: NSData, format: KeyExternalFormat,
		                              keyType: KeyType) throws -> CCECCryptorRef {
			var impKey: CCECCryptorRef = nil
			let status = CCECCryptorImportKey!(format: format.rawValue,
			                                   keyPackage: key.bytes, keyPackageLen:key.length,
			                                   keyType: keyType.rawValue, key: &impKey)
			guard status == noErr else { throw CCError(status) }

			return impKey
		}

		private static func exportKey(key: CCECCryptorRef, format: KeyExternalFormat,
		                              type: KeyType) throws -> NSData {
			var expKeyLength = 8192
			let expKey = NSMutableData(length:expKeyLength)!
			let status = CCECCryptorExportKey!(
				format: format.rawValue,
				keyPackage: expKey.mutableBytes,
				keyPackageLen: &expKeyLength,
				keyType: type.rawValue,
				key: key)
			guard status == noErr else { throw CCError(status) }

			expKey.length = expKeyLength
			return expKey
		}

		public static func available() -> Bool {
			return CCECCryptorGeneratePair != nil &&
				CCECCryptorImportKey != nil &&
				CCECCryptorExportKey != nil &&
				CCECCryptorRelease != nil &&
				CCECCryptorSignHash != nil &&
				CCECCryptorVerifyHash != nil &&
				CCECCryptorComputeSharedSecret != nil
		}

		private enum KeyType: CCECKeyType {
			case keyPublic = 0, keyPrivate
			case blankPublicKey = 97, blankPrivateKey
			case badKey = 99
		}
		private typealias CCECKeyType = UInt32

		private typealias CCECKeyExternalFormat = UInt32
		private enum KeyExternalFormat: CCECKeyExternalFormat {
			case importKeyBinary = 0, importKeyDER
		}

		private typealias CCECCryptorRef = UnsafePointer<Void>
		private typealias CCECCryptorGeneratePairT = @convention(c) (
			keySize: size_t ,
			publicKey: UnsafeMutablePointer<CCECCryptorRef>,
			privateKey: UnsafeMutablePointer<CCECCryptorRef>) -> CCCryptorStatus
		private static let CCECCryptorGeneratePair: CCECCryptorGeneratePairT? =
			getFunc(dl, f: "CCECCryptorGeneratePair")

		private typealias CCECCryptorImportKeyT = @convention(c) (
			format: CCECKeyExternalFormat,
			keyPackage: UnsafePointer<Void>, keyPackageLen: size_t,
			keyType: CCECKeyType, key: UnsafeMutablePointer<CCECCryptorRef>) -> CCCryptorStatus
		private static let CCECCryptorImportKey: CCECCryptorImportKeyT? =
			getFunc(dl, f: "CCECCryptorImportKey")

		private typealias CCECCryptorExportKeyT = @convention(c) (
			format: CCECKeyExternalFormat,
			keyPackage: UnsafePointer<Void>,
			keyPackageLen: UnsafePointer<size_t>,
			keyType: CCECKeyType, key: CCECCryptorRef) -> CCCryptorStatus
		private static let CCECCryptorExportKey: CCECCryptorExportKeyT? =
			getFunc(dl, f: "CCECCryptorExportKey")

		private typealias CCECCryptorReleaseT = @convention(c) (
			key: CCECCryptorRef) -> Void
		private static let CCECCryptorRelease: CCECCryptorReleaseT? =
			getFunc(dl, f: "CCECCryptorRelease")

		private typealias CCECCryptorSignHashT = @convention(c)(
			privateKey: CCECCryptorRef,
			hashToSign: UnsafePointer<Void>,
			hashSignLen: size_t,
			signedData: UnsafeMutablePointer<Void>,
			signedDataLen: UnsafeMutablePointer<size_t>) -> CCCryptorStatus
		private static let CCECCryptorSignHash: CCECCryptorSignHashT? =
			getFunc(dl, f: "CCECCryptorSignHash")

		private typealias CCECCryptorVerifyHashT = @convention(c)(
			publicKey: CCECCryptorRef,
			hash: UnsafePointer<Void>, hashLen: size_t,
			signedData: UnsafePointer<Void>, signedDataLen: size_t,
			valid: UnsafeMutablePointer<UInt32>) -> CCCryptorStatus
		private static let CCECCryptorVerifyHash: CCECCryptorVerifyHashT? =
			getFunc(dl, f: "CCECCryptorVerifyHash")

		private typealias CCECCryptorComputeSharedSecretT = @convention(c)(
			privateKey: CCECCryptorRef,
			publicKey: CCECCryptorRef,
			out: UnsafeMutablePointer<Void>,
			outLen: UnsafeMutablePointer<size_t>) -> CCCryptorStatus
		private static let CCECCryptorComputeSharedSecret: CCECCryptorComputeSharedSecretT? =
			getFunc(dl, f: "CCECCryptorComputeSharedSecret")
	}

	public class CRC {

		public typealias CNcrc = UInt32
		public enum Mode: CNcrc {
			case crc8 = 10,
			crc8ICODE = 11,
			crc8ITU = 12,
			crc8ROHC = 13,
			crc8WCDMA = 14,
			crc16 = 20,
			crc16CCITTTrue = 21,
			crc16CCITTFalse = 22,
			crc16USB = 23,
			crc16XMODEM = 24,
			crc16DECTR = 25,
			crc16DECTX = 26,
			crc16ICODE = 27,
			crc16VERIFONE = 28,
			crc16A = 29,
			crc16B = 30,
			crc16Fletcher = 31,
			crc32Adler = 40,
			crc32 = 41,
			crc32CASTAGNOLI = 42,
			crc32BZIP2 = 43,
			crc32MPEG2 = 44,
			crc32POSIX = 45,
			crc32XFER = 46,
			crc64ECMA182 = 60
		}

		public static func crc(input: NSData, mode: Mode) throws -> UInt64 {
			var result: UInt64 = 0
			let status = CNCRC!(
				algorithm: mode.rawValue,
				input: input.bytes, inputLen: input.length,
				result: &result)
			guard status == noErr else {
				throw CCError(status)
			}
			return result
		}

		public static func available() -> Bool {
			return CNCRC != nil
		}

		private typealias CNCRCT = @convention(c) (
			algorithm: CNcrc,
			input: UnsafePointer<Void>, inputLen: size_t,
			result: UnsafeMutablePointer<UInt64>) -> CCCryptorStatus
		private static let CNCRC: CNCRCT? = getFunc(dl, f: "CNCRC")
	}

	public class CMAC {

		public static func AESCMAC(data: NSData, key: NSData) -> NSData {
			let result = NSMutableData(length: 16)!
			CCAESCmac!(key: key.bytes,
			           data: data.bytes, dataLen: data.length,
			           macOut: result.mutableBytes)
			return result
		}

		public static func available() -> Bool {
			return CCAESCmac != nil
		}

		private typealias CCAESCmacT = @convention(c) (
			key: UnsafePointer<Void>,
			data: UnsafePointer<Void>, dataLen: size_t,
			macOut: UnsafeMutablePointer<Void>) -> Void
		private static let CCAESCmac: CCAESCmacT? = getFunc(dl, f: "CCAESCmac")
	}

	public class KeyDerivation {

		public typealias CCPseudoRandomAlgorithm = UInt32
		public enum PRFAlg: CCPseudoRandomAlgorithm {
			case sha1 = 1, sha224, sha256, sha384, sha512
			var cc: CC.HMACAlg {
				switch self {
				case .sha1: return .sha1
				case .sha224: return .sha224
				case .sha256: return .sha256
				case .sha384: return .sha384
				case .sha512: return .sha512
				}
			}
		}

		public static func PBKDF2(password: String, salt: NSData,
		                         prf: PRFAlg, rounds: UInt32) throws -> NSData {

			let result = NSMutableData(length:prf.cc.digestLength)!
			let passwData = password.dataUsingEncoding(NSUTF8StringEncoding)!
			let status = CCKeyDerivationPBKDF!(algorithm: PBKDFAlgorithm.pbkdf2.rawValue,
			                      password: passwData.bytes, passwordLen: passwData.length,
			                      salt: salt.bytes, saltLen: salt.length,
			                      prf: prf.rawValue, rounds: rounds,
			                      derivedKey: result.mutableBytes, derivedKeyLen: result.length)
			guard status == noErr else { throw CCError(status) }

			return result
		}

		public static func available() -> Bool {
			return CCKeyDerivationPBKDF != nil
		}

		private typealias CCPBKDFAlgorithm = UInt32
		private enum PBKDFAlgorithm: CCPBKDFAlgorithm {
			case pbkdf2 = 2
		}

		private typealias CCKeyDerivationPBKDFT = @convention(c) (
			algorithm: CCPBKDFAlgorithm,
			password: UnsafePointer<Void>, passwordLen: size_t,
			salt: UnsafePointer<Void>, saltLen: size_t,
			prf: CCPseudoRandomAlgorithm, rounds: uint,
			derivedKey: UnsafeMutablePointer<Void>, derivedKeyLen: size_t) -> CCCryptorStatus
		private static let CCKeyDerivationPBKDF: CCKeyDerivationPBKDFT? =
			getFunc(dl, f: "CCKeyDerivationPBKDF")
	}

	public class KeyWrap {

		private static let rfc3394IVData: [UInt8] = [0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6, 0xA6]
		public static let rfc3394IV = NSData(bytes: rfc3394IVData, length:rfc3394IVData.count)

		public static func SymmetricKeyWrap(iv: NSData,
		                                    kek: NSData,
		                                    rawKey: NSData) throws -> NSData {
			let alg = WrapAlg.aes.rawValue
			var wrappedKeyLength = CCSymmetricWrappedSize!(algorithm: alg, rawKeyLen: rawKey.length)
			let wrappedKey = NSMutableData(length:wrappedKeyLength)!
			let status = CCSymmetricKeyWrap!(
				algorithm: alg,
				iv: iv.bytes, ivLen: iv.length,
				kek: kek.bytes, kekLen: kek.length,
				rawKey: rawKey.bytes, rawKeyLen: rawKey.length,
				wrappedKey: wrappedKey.mutableBytes, wrappedKeyLen:&wrappedKeyLength)
			guard status == noErr else { throw CCError(status) }

			wrappedKey.length = wrappedKeyLength
			return wrappedKey
		}

		public static func SymmetricKeyUnwrap(iv: NSData,
		                                      kek: NSData,
		                                      wrappedKey: NSData) throws -> NSData {
			let alg = WrapAlg.aes.rawValue
			var rawKeyLength = CCSymmetricUnwrappedSize!(algorithm: alg, wrappedKeyLen: wrappedKey.length)
			let rawKey = NSMutableData(length:rawKeyLength)!
			let status = CCSymmetricKeyUnwrap!(
				algorithm: alg,
				iv: iv.bytes, ivLen: iv.length,
				kek: kek.bytes, kekLen: kek.length,
				wrappedKey: wrappedKey.bytes, wrappedKeyLen: wrappedKey.length,
				rawKey: rawKey.mutableBytes, rawKeyLen:&rawKeyLength)
			guard status == noErr else { throw CCError(status) }

			rawKey.length = rawKeyLength
			return rawKey
		}

		public static func available() -> Bool {
			return CCSymmetricKeyWrap != nil &&
				CCSymmetricKeyUnwrap != nil &&
				CCSymmetricWrappedSize != nil &&
				CCSymmetricUnwrappedSize != nil
		}

		private enum WrapAlg: CCWrappingAlgorithm {
			case aes = 1
		}
		private typealias CCWrappingAlgorithm = UInt32

		private typealias CCSymmetricKeyWrapT = @convention(c) (
			algorithm: CCWrappingAlgorithm,
			iv: UnsafePointer<Void>, ivLen: size_t,
			kek: UnsafePointer<Void>, kekLen: size_t,
			rawKey: UnsafePointer<Void>, rawKeyLen: size_t,
			wrappedKey: UnsafeMutablePointer<Void>,
			wrappedKeyLen: UnsafePointer<size_t>) -> CCCryptorStatus
		private static let CCSymmetricKeyWrap: CCSymmetricKeyWrapT? = getFunc(dl, f: "CCSymmetricKeyWrap")

		private typealias CCSymmetricKeyUnwrapT = @convention(c) (
			algorithm: CCWrappingAlgorithm,
			iv: UnsafePointer<Void>, ivLen: size_t,
			kek: UnsafePointer<Void>, kekLen: size_t,
			wrappedKey: UnsafePointer<Void>, wrappedKeyLen: size_t,
			rawKey: UnsafeMutablePointer<Void>,
			rawKeyLen: UnsafePointer<size_t>) -> CCCryptorStatus
		private static let CCSymmetricKeyUnwrap: CCSymmetricKeyUnwrapT? =
			getFunc(dl, f: "CCSymmetricKeyUnwrap")

		private typealias CCSymmetricWrappedSizeT = @convention(c) (
			algorithm: CCWrappingAlgorithm,
			rawKeyLen: size_t) -> size_t
		private static let CCSymmetricWrappedSize: CCSymmetricWrappedSizeT? =
			getFunc(dl, f: "CCSymmetricWrappedSize")

		private typealias CCSymmetricUnwrappedSizeT = @convention(c) (
			algorithm: CCWrappingAlgorithm,
			wrappedKeyLen: size_t) -> size_t
		private static let CCSymmetricUnwrappedSize: CCSymmetricUnwrappedSizeT? =
			getFunc(dl, f: "CCSymmetricUnwrappedSize")

	}

}

private func getFunc<T>(from: UnsafeMutablePointer<Void>, f: String) -> T? {
	let sym = dlsym(from, f)
	guard sym != nil else {
		return nil
	}
	return unsafeBitCast(sym, T.self)
}

extension NSData {
	/// Create hexadecimal string representation of NSData object.
	///
	/// - returns: String representation of this NSData object.

	public func hexadecimalString() -> String {
		var hexstr = String()
		for i in UnsafeBufferPointer<UInt8>(start: UnsafeMutablePointer<UInt8>(bytes), count: length) {
			hexstr += String(format: "%02X", i)
		}
		return hexstr
	}

	public func arrayOfBytes() -> [UInt8] {
		let count = self.length / sizeof(UInt8)
		var bytesArray = [UInt8](count: count, repeatedValue: 0)
		self.getBytes(&bytesArray, length:count * sizeof(UInt8))
		return bytesArray
	}

	private var bytesView: BytesView { return BytesView(self) }

	private func bytesViewRange(range: NSRange) -> BytesView {
		return BytesView(self, range: range)
	}

	private struct BytesView: CollectionType {
		// The view retains the NSData. That's on purpose.
		// NSData doesn't retain the view, so there's no loop.
		let data: NSData
		init(_ data: NSData) {
			self.data = data
			self.startIndex = 0
			self.endIndex = data.length
		}

		init(_ data: NSData, range: NSRange ) {
			self.data = data
			self.startIndex = range.location
			self.endIndex = range.location + range.length
		}

		subscript (position: Int) -> UInt8 {
			return UnsafePointer<UInt8>(data.bytes)[position]
		}
		subscript (bounds: Range<Int>) -> NSData {
			return data.subdataWithRange(NSRange(bounds))
		}
		var startIndex: Int
		var endIndex: Int
		var length: Int { return endIndex - startIndex }
	}
}

extension String.CharacterView.Index : Strideable { }
extension String {

	/// Create NSData from hexadecimal string representation
	///
	/// This takes a hexadecimal representation and creates a NSData object. Note, if the string has
	/// any spaces, those are removed. Also if the string started with a '<' or ended with a '>',
	/// those are removed, too. This does no validation of the string to ensure it's a valid
	/// hexadecimal string
	///
	/// The use of `strtoul` inspired by Martin R at http://stackoverflow.com/a/26284562/1271826
	///
	/// - returns: NSData represented by this hexadecimal string.
	///            Returns nil if string contains characters outside the 0-9 and a-f range.

	public func dataFromHexadecimalString() -> NSData? {
		let trimmedString = self.stringByTrimmingCharactersInSet(
			NSCharacterSet(charactersInString: "<> ")).stringByReplacingOccurrencesOfString(
				" ", withString: "")

		// make sure the cleaned up string consists solely of hex digits,
		// and that we have even number of them

		let regex = try! NSRegularExpression(pattern: "^[0-9a-f]*$", options: .CaseInsensitive)

		let found = regex.firstMatchInString(trimmedString, options: [],
		                                     range: NSRange(location: 0,
												length: trimmedString.characters.count))
		guard found != nil &&
			found?.range.location != NSNotFound &&
			trimmedString.characters.count % 2 == 0 else {
				return nil
		}

		// everything ok, so now let's build NSData

		let data = NSMutableData(capacity: trimmedString.characters.count / 2)

		for index in trimmedString.startIndex.stride(to:trimmedString.endIndex, by:2) {
			let byteString = trimmedString.substringWithRange(index..<index.successor().successor())
			let num = UInt8(byteString.withCString { strtoul($0, nil, 16) })
			data?.appendBytes([num] as [UInt8], length: 1)
		}

		return data
	}
}
