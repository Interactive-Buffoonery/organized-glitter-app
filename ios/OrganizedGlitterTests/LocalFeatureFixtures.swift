import Foundation

@testable import OrganizedGlitter

@MainActor
func localFeatureLibrary(userID: String = "feature-user") throws -> LibrarySession {
  let client = PocketBaseClient(
    baseURL: URL(string: "https://offline.example.invalid")!,
    sessionStore: KeychainSessionStore(service: "FeatureTests.\(UUID().uuidString)"))
  return LibrarySession(client: client, userID: userID, store: try LocalLibraryStore.inMemory())
}

func featureProject(
  _ id: String, title: String, status: String = "wishlist", updated: String = "2026-09-01",
  user: String = "feature-user"
) -> DiamondProjectRecord {
  DiamondProjectRecord(
    id: id, title: title, user: user, company: nil, artist: nil, status: status,
    kitCategory: "full", drillShape: "round", generalNotes: nil, width: nil, height: nil,
    image: nil, dateStarted: nil, dateCompleted: nil, created: "2026-09-01",
    updated: updated, expand: nil)
}

func featureBook(_ id: String, title: String, status: String = "purchased") -> ColoringBookRecord {
  ColoringBookRecord(
    id: id, user: "feature-user", title: title, series: nil, status: status,
    totalPages: 40, completedPages: nil, completionPercentage: nil, coverImage: nil,
    publisher: nil, illustrator: nil, created: "2026-09-01", updated: "2026-09-01",
    expand: nil)
}

func featurePage(_ id: String, book: String, number: Int, status: String = "not_started")
  -> ColoringPageRecord
{
  ColoringPageRecord(
    id: id, book: book, pageNumber: number, status: status, photos: [],
    revealedSubject: nil, completedAt: nil, startedAt: nil,
    created: "2026-09-01", updated: "2026-09-01", expand: nil)
}
