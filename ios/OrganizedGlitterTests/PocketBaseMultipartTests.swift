import Foundation
import Testing

@testable import OrganizedGlitter

struct PocketBaseMultipartTests {
  @Test
  func rejectsHeaderInjectionInDispositionValues() throws {
    let files = [
      PocketBaseMultipartFile(
        fieldName: "image\r\nX-Injected: true",
        fileName: "image.png",
        contentType: "image/png",
        data: Data([0x01])
      ),
      PocketBaseMultipartFile(
        fieldName: "image",
        fileName: "image.png\r\nX-Injected: true",
        contentType: "image/png",
        data: Data([0x01])
      ),
      PocketBaseMultipartFile(
        fieldName: "image",
        fileName: "image.png",
        contentType: "image/png\r\nX-Injected: true",
        data: Data([0x01])
      ),
    ]

    for file in files {
      do {
        _ = try PocketBaseMultipartForm(files: [file]).encoded(
          boundary: "test-boundary"
        )
        Issue.record("Expected multipart header validation to fail")
      } catch {
        guard let apiError = error as? APIError else {
          Issue.record("Expected multipart header validation error, got \(error)")
          continue
        }
        guard case .validation = apiError else {
          Issue.record("Expected multipart header validation error, got \(error)")
          continue
        }
      }
    }
  }

  @Test
  func encodesRepeatedFileFieldsAndClosingBoundary() throws {
    let form = PocketBaseMultipartForm(
      fields: ["project": "project-1"],
      files: [
        PocketBaseMultipartFile(
          fieldName: "photos+",
          fileName: "first.png",
          contentType: "image/png",
          data: Data([0x01, 0x02])
        ),
        PocketBaseMultipartFile(
          fieldName: "photos+",
          fileName: "second.png",
          contentType: "image/png",
          data: Data([0x03, 0x04])
        ),
      ]
    )

    let encoded = try form.encoded(boundary: "test-boundary")
    let body = String(decoding: encoded.data, as: UTF8.self)

    #expect(encoded.contentType == "multipart/form-data; boundary=test-boundary")
    #expect(body.contains("name=\"project\"\r\n\r\nproject-1\r\n"))
    #expect(body.components(separatedBy: "name=\"photos+\"").count - 1 == 2)
    #expect(body.hasSuffix("--test-boundary--\r\n"))
  }
}
