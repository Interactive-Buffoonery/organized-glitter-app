import Foundation

enum CoverChange: Equatable, Sendable {
  case unchanged
  case replace(ProcessedDetailPhoto)
  case remove

  func multipart(field: String) -> PocketBaseMultipartForm? {
    guard case .replace(let photo) = self else { return nil }
    return PocketBaseMultipartForm(files: [
      PocketBaseMultipartFile(
        fieldName: field, fileName: photo.fileName,
        contentType: photo.contentType, data: photo.data)
    ])
  }

  func removalBody(field: String) -> [String: String]? {
    self == .remove ? [field: ""] : nil
  }
}

@MainActor
enum CoverUpload {
  static func apply<Record: Codable & Sendable>(
    _ change: CoverChange, collection: String, recordID: String,
    field: String, library: LibrarySession
  ) async throws -> Record {
    if let multipart = change.multipart(field: field) {
      return try await library.update(collection: collection, id: recordID, multipart: multipart)
    }
    if let body = change.removalBody(field: field) {
      return try await library.updateOnline(collection: collection, id: recordID, body: body)
    }
    return try library.record(collection: collection, id: recordID)
  }
}
