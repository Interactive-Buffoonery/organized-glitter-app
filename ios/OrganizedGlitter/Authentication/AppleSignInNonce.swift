import CryptoKit
import Foundation
import Security

struct AppleSignInNonce: Sendable {
  let raw: String

  var digest: String {
    Self.hex(SHA256.hash(data: Data(raw.utf8)))
  }

  static func generate() throws -> AppleSignInNonce {
    var bytes = [UInt8](repeating: 0, count: 32)
    let status = bytes.withUnsafeMutableBytes { buffer in
      SecRandomCopyBytes(kSecRandomDefault, buffer.count, buffer.baseAddress!)
    }
    guard status == errSecSuccess else {
      throw AppleSignInError.nonceGenerationFailed
    }
    return AppleSignInNonce(bytes: bytes)
  }

  init(bytes: [UInt8]) {
    precondition(bytes.count == 32)
    raw = Self.hex(bytes)
  }

  private static func hex<Bytes: Sequence>(_ bytes: Bytes) -> String where Bytes.Element == UInt8 {
    let digits = Array("0123456789abcdef".utf8)
    var result = [UInt8]()
    for byte in bytes {
      result.append(digits[Int(byte >> 4)])
      result.append(digits[Int(byte & 0x0f)])
    }
    return String(decoding: result, as: UTF8.self)
  }
}
