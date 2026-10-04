import Foundation
import Testing
@testable import OrganizedGlitter

@MainActor
struct CoverImageTests {
  @Test func centeredCrop() {
    let rect = CoverCropView.cropRect(
      imageSize: CGSize(width: 1000, height: 1000),
      frameSize: CGSize(width: 160, height: 200))
    #expect(rect == CGRect(x: 100, y: 0, width: 800, height: 1000))
  }

  @Test func clampsToImageEdges() {
    let size = CGSize(width: 160, height: 200)
    let image = CGSize(width: 1000, height: 500)
    let first = CoverCropView.cropRect(
      imageSize: image, frameSize: size, offset: CGSize(width: 10000, height: -10000))
    let last = CoverCropView.cropRect(
      imageSize: image, frameSize: size, offset: CGSize(width: -10000, height: 10000))
    #expect(first == CGRect(x: 0, y: 0, width: 400, height: 500))
    #expect(last == CGRect(x: 600, y: 0, width: 400, height: 500))
  }

  @Test func zoomPreservesAspectAndCenter() {
    let rect = CoverCropView.cropRect(
      imageSize: CGSize(width: 1000, height: 1000),
      frameSize: CGSize(width: 160, height: 200), scale: 2)
    #expect(rect == CGRect(x: 300, y: 250, width: 400, height: 500))
    #expect(CoverCropView.cropRect(
      imageSize: CGSize(width: 1000, height: 1000),
      frameSize: CGSize(width: 160, height: 200), scale: 0.5)
      == CGRect(x: 100, y: 0, width: 800, height: 1000))
  }

  @Test func requestChoicesAndRemovalEncoding() throws {
    let photo = ProcessedDetailPhoto(data: Data([1, 2]), fileName: "artwork.jpg", contentType: "image/jpeg")
    #expect(CoverChange.unchanged.multipart(field: "image") == nil)
    #expect(CoverChange.unchanged.removalBody(field: "image") == nil)
    #expect(CoverChange.remove.multipart(field: "image") == nil)
    let body = try #require(CoverChange.remove.removalBody(field: "cover_image"))
    let decoded = try JSONDecoder().decode([String: String].self, from: JSONEncoder().encode(body))
    #expect(decoded == ["cover_image": ""])
    let form = try #require(CoverChange.replace(photo).multipart(field: "image"))
    #expect(form.files == [PocketBaseMultipartFile(
      fieldName: "image", fileName: photo.fileName, contentType: photo.contentType, data: photo.data)])
    #expect(CoverChange.replace(photo).removalBody(field: "image") == nil)
  }
}
