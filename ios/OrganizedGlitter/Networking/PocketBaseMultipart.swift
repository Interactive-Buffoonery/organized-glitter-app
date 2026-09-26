import Foundation

struct PocketBaseMultipartForm: Equatable, Sendable {
  let fields: [String: String]
  let files: [PocketBaseMultipartFile]

  init(
    fields: [String: String] = [:],
    files: [PocketBaseMultipartFile] = []
  ) {
    self.fields = fields
    self.files = files
  }

  func encoded(boundary: String = "Boundary-\(UUID().uuidString)") throws
    -> PocketBaseEncodedMultipartForm
  {
    var data = Data()

    for (name, value) in fields {
      try Self.validateDispositionValue(name)
      data.appendUTF8("--\(boundary)\r\n")
      data.appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      data.appendUTF8(value)
      data.appendUTF8("\r\n")
    }

    for file in files {
      try Self.validateDispositionValue(file.fieldName)
      try Self.validateDispositionValue(file.fileName)
      try Self.validateContentType(file.contentType)
      data.appendUTF8("--\(boundary)\r\n")
      data.appendUTF8(
        "Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(file.fileName)\"\r\n"
      )
      data.appendUTF8("Content-Type: \(file.contentType)\r\n\r\n")
      data.append(file.data)
      data.appendUTF8("\r\n")
    }

    data.appendUTF8("--\(boundary)--\r\n")
    return PocketBaseEncodedMultipartForm(
      data: data,
      contentType: "multipart/form-data; boundary=\(boundary)"
    )
  }

  private static func validateDispositionValue(_ value: String) throws {
    guard !value.isEmpty,
      value.unicodeScalars.allSatisfy({ scalar in
        scalar.value >= 0x20 && scalar.value != 0x7f && scalar != "\"" && scalar != "\\"
      })
    else {
      throw APIError.validation(
        "Multipart names cannot contain control characters, quotes, or backslashes."
      )
    }
  }

  private static func validateContentType(_ contentType: String) throws {
    guard !contentType.isEmpty,
      contentType.unicodeScalars.allSatisfy({ scalar in
        scalar.value >= 0x20 && scalar.value != 0x7f
      })
    else {
      throw APIError.validation("Multipart content types cannot contain control characters.")
    }
  }
}

struct PocketBaseMultipartFile: Equatable, Sendable {
  let fieldName: String
  let fileName: String
  let contentType: String
  let data: Data
}

struct PocketBaseEncodedMultipartForm: Sendable {
  let data: Data
  let contentType: String
}

private extension Data {
  mutating func appendUTF8(_ string: String) {
    append(contentsOf: string.utf8)
  }
}
