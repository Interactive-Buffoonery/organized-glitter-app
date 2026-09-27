import CryptoKit
import Foundation

actor PrivateArtworkStore {
  private let root: URL
  private let maximumBytes: Int

  init(root: URL = URL.cachesDirectory.appending(path: "PrivateArtwork"), maximumBytes: Int = 128 * 1_024 * 1_024) {
    self.root = root
    self.maximumBytes = maximumBytes
  }

  func data(for url: URL, scope: LocalAccountScope) throws -> Data? {
    let file = fileURL(for: url, scope: scope)
    guard FileManager.default.fileExists(atPath: file.path) else { return nil }
    let size = try file.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
    guard size <= RemoteArtworkLoader.maximumDownloadByteCount else {
      throw RemoteArtworkError.payloadTooLarge
    }
    return try Data(contentsOf: file)
  }

  func save(_ data: Data, for url: URL, scope: LocalAccountScope) throws {
    guard data.count <= min(maximumBytes, RemoteArtworkLoader.maximumDownloadByteCount) else { return }
    let directory = directory(for: scope)
    try FileManager.default.createDirectory(
      at: directory, withIntermediateDirectories: true,
      attributes: [.protectionKey: FileProtectionType.complete])
    var protectedDirectory = directory
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try protectedDirectory.setResourceValues(values)
    try data.write(to: fileURL(for: url, scope: scope), options: [.atomic, .completeFileProtection])
    let files = try FileManager.default.contentsOfDirectory(
      at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey])
    let sizes = try files.map { url in
      let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
      return (url: url, size: values.fileSize ?? 0, date: values.contentModificationDate ?? .distantPast)
    }
    var total = sizes.reduce(0) { $0 + $1.size }
    for file in sizes.sorted(by: { $0.date < $1.date }) where total > maximumBytes {
      try FileManager.default.removeItem(at: file.url)
      total -= file.size
    }
  }

  func retain(_ urls: [URL], scope: LocalAccountScope) throws {
    let directory = directory(for: scope)
    guard FileManager.default.fileExists(atPath: directory.path) else { return }
    let allowed = Set(urls.map { fileURL(for: $0, scope: scope).lastPathComponent })
    for file in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
      where !allowed.contains(file.lastPathComponent)
    {
      try FileManager.default.removeItem(at: file)
    }
  }

  func remove(scope: LocalAccountScope) throws {
    let directory = directory(for: scope)
    if FileManager.default.fileExists(atPath: directory.path) {
      try FileManager.default.removeItem(at: directory)
    }
  }

  private func directory(for scope: LocalAccountScope) -> URL {
    root.appending(path: Self.digest(scope.storageKey), directoryHint: .isDirectory)
  }

  private func fileURL(for url: URL, scope: LocalAccountScope) -> URL {
    directory(for: scope).appending(path: Self.digest(RemoteArtworkCacheKey.url(for: url).absoluteString))
  }

  private static func digest(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
}
