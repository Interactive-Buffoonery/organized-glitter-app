import Foundation
import Observation
import Security

enum AccountDeletionError: Error { case proofGenerationFailed }

struct AccountDeletionIntent: Codable, Equatable, Sendable {
  enum Stage: String, Codable { case prepared, submitted, serverDeleted }
  let backendURL: URL
  let userID: String
  let proof: String
  var stage: Stage = .prepared
  var cleanup: AccountDeletionCleanup?

  var scope: LocalAccountScope { LocalAccountScope(backendURL: backendURL, userID: userID) }

  static func makeProof() throws -> String {
    var bytes = [UInt8](repeating: 0, count: 32)
    guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
      throw AccountDeletionError.proofGenerationFailed
    }
    return Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
      .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
  }

  func validate() throws {
    guard !userID.isEmpty, proof.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
      stage != .serverDeleted || cleanup != nil else { throw APIError.decoding }
  }
}

enum AccountDeletionCleanup: String, Codable, Sendable { case pending, completed }

struct AccountDeletionMethods: Sendable {
  let passwordAvailable: Bool
  let appleLinked: Bool
  let appleAvailable: Bool
  let socialProviders: [SocialProvider]
}

struct AccountDeletionReceipt: Decodable, Sendable {
  let status: String
  let cleanup: AccountDeletionCleanup
}

@MainActor
struct AccountDeletionPersistence {
  let load: () throws -> AccountDeletionIntent?
  let save: (AccountDeletionIntent) throws -> Void
  let clear: () throws -> Void
}

@MainActor
@Observable
final class AccountDeletionModel {
  enum State: Equatable {
    case idle, verifying, ready, resubmissionReady, submitting, uncertain, blocked
    case localCleanupFailed(AccountDeletionCleanup)
    case completed(AccountDeletionCleanup)
  }

  let scope: LocalAccountScope
  private(set) var state: State = .idle
  private(set) var errorMessage: String?
  private(set) var methods: AccountDeletionMethods?
  private(set) var methodLoadFailed = false
  @ObservationIgnored private let client: PocketBaseClient
  @ObservationIgnored private let persistence: AccountDeletionPersistence
  @ObservationIgnored private let now: () -> Date
  @ObservationIgnored private let isCurrent: () -> Bool
  @ObservationIgnored private let lock: () async throws -> Void
  @ObservationIgnored private let prepareRecoveryAuthentication: () async throws -> Void
  @ObservationIgnored private let cleanup: (LocalAccountScope) async throws -> Void
  @ObservationIgnored private var intent: AccountDeletionIntent?
  @ObservationIgnored private var verificationStarted: Date?
  @ObservationIgnored private var generation = 0

  var isLocked: Bool { intent.map { $0.stage != .prepared } ?? false }
  var isBusy: Bool { state == .verifying || state == .submitting }

  init(
    client: PocketBaseClient, scope: LocalAccountScope, persistence: AccountDeletionPersistence,
    now: @escaping () -> Date = Date.init, isCurrent: @escaping () -> Bool = { true },
    prepareRecoveryAuthentication: @escaping () async throws -> Void = {},
    lock: @escaping () async throws -> Void,
    cleanup: @escaping (LocalAccountScope) async throws -> Void
  ) {
    self.client = client
    self.scope = scope
    self.persistence = persistence
    self.now = now
    self.isCurrent = isCurrent
    self.prepareRecoveryAuthentication = prepareRecoveryAuthentication
    self.lock = lock
    self.cleanup = cleanup
  }

  func recover() throws -> Bool {
    guard let stored = try persistence.load() else { return false }
    try stored.validate()
    guard stored.scope == scope, stored.backendURL == client.baseURL else { throw APIError.forbidden }
    if stored.stage == .prepared {
      try persistence.clear()
      return false
    }
    intent = stored
    state = stored.cleanup.map { .localCleanupFailed($0) } ?? .uncertain
    return true
  }

  func loadMethods() async {
    guard isCurrent(), !isBusy, intent?.stage != .serverDeleted else { return }
    methods = nil
    methodLoadFailed = false
    let attempt = generation
    do {
      if intent?.stage == .submitted { try await prepareRecoveryAuthentication() }
      let available = try await client.deletionMethods(scope: scope)
      guard attempt == generation, isCurrent() else { return }
      methods = available
    } catch {
      guard attempt == generation, isCurrent() else { return }
      methodLoadFailed = true
    }
  }

  func verifyPassword(_ password: String) async {
    await verify { proof in
      try await self.client.verifyDeletionWithPassword(scope: self.scope, proof: proof, password: password)
    }
  }

  func verifyApple(code: String, nonce: String) async {
    await verify { proof in
      try await self.client.verifyDeletionWithApple(scope: self.scope, proof: proof, code: code, nonce: nonce)
    }
  }

  func verifyOAuth(
    provider: SocialProvider,
    present: @escaping @MainActor @Sendable (URL, URL) async throws -> URL
  ) async {
    await verify { proof in
      try await self.client.verifyDeletionWithOAuth(scope: self.scope, proof: proof, providerName: provider.rawValue, present: present)
    }
  }

  func reverifyPassword(_ password: String) async {
    await verifyForResubmission { proof in
      try await self.client.verifyDeletionWithPassword(scope: self.scope, proof: proof, password: password)
    }
  }

  func reverifyApple(code: String, nonce: String) async {
    await verifyForResubmission { proof in
      try await self.client.verifyDeletionWithApple(scope: self.scope, proof: proof, code: code, nonce: nonce)
    }
  }

  func reverifyOAuth(
    provider: SocialProvider,
    present: @escaping @MainActor @Sendable (URL, URL) async throws -> URL
  ) async {
    await verifyForResubmission { proof in
      try await self.client.verifyDeletionWithOAuth(scope: self.scope, proof: proof,
        providerName: provider.rawValue, present: present)
    }
  }

  private func verifyForResubmission(_ operation: (String) async throws -> Void) async {
    guard state == .uncertain, !isBusy, isCurrent(),
      let intent, intent.stage == .submitted else { return }
    generation &+= 1
    let attempt = generation
    state = .verifying
    errorMessage = nil
    do {
      try await prepareRecoveryAuthentication()
      guard attempt == generation, isCurrent(), !Task.isCancelled else { return }
      let started = now()
      try await operation(intent.proof)
      guard attempt == generation, isCurrent(), !Task.isCancelled else { return }
      verificationStarted = started
      state = .resubmissionReady
    } catch {
      guard attempt == generation, isCurrent() else { return }
      verificationStarted = nil
      state = .uncertain
      errorMessage = verificationError(error)
    }
  }

  private func verify(_ operation: (String) async throws -> Void) async {
    guard !isLocked, !isBusy, isCurrent(), scope.backendURL == client.baseURL else { return }
    generation &+= 1
    let attempt = generation
    state = .verifying
    errorMessage = nil
    do {
      let prepared = AccountDeletionIntent(backendURL: scope.backendURL, userID: scope.userID, proof: try AccountDeletionIntent.makeProof())
      do { try persistence.save(prepared) }
      catch {
        state = .blocked
        errorMessage = "Identity verification did not start because secure recovery could not be saved."
        return
      }
      intent = prepared
      verificationStarted = now()
      try await operation(prepared.proof)
      guard attempt == generation, isCurrent(), !Task.isCancelled else { return }
      state = .ready
    } catch {
      guard attempt == generation, isCurrent() else { return }
      do {
        try persistence.clear()
        intent = nil
        verificationStarted = nil
        state = .idle
        errorMessage = verificationError(error)
      } catch {
        state = .blocked
        errorMessage = "Secure deletion recovery could not be saved. Try again before continuing."
      }
    }
  }

  func cancelPreparation() {
    guard !isLocked else { return }
    if case .completed = state { return }
    generation &+= 1
    do {
      try persistence.clear()
      intent = nil
      verificationStarted = nil
      state = .idle
      errorMessage = nil
    } catch { state = .blocked }
  }

  func invalidate() {
    generation &+= 1
    if !isLocked { cancelPreparation() }
  }

  func confirm() async {
    guard state == .ready, isCurrent(), var submitted = intent,
      let started = verificationStarted else { return }
    guard now().timeIntervalSince(started) >= 0, now().timeIntervalSince(started) < 300 else {
      cancelPreparation()
      errorMessage = "Verify your identity again before deleting your account."
      return
    }
    do {
      submitted.stage = .submitted
      try persistence.save(submitted)
    } catch {
      state = .blocked
      errorMessage = "Deletion did not start because secure recovery could not be saved."
      return
    }
    intent = submitted
    await submit(completionOnly: false)
  }

  func confirmResubmission() async {
    guard state == .resubmissionReady, isCurrent(), intent?.stage == .submitted,
      let started = verificationStarted else { return }
    guard now().timeIntervalSince(started) >= 0, now().timeIntervalSince(started) < 300 else {
      state = .uncertain
      verificationStarted = nil
      errorMessage = "Verification expired. Verify again or contact support."
      return
    }
    verificationStarted = nil
    await submit(completionOnly: false)
  }

  private func verificationError(_ error: Error) -> String {
    if error as? OAuthError == .unavailable || error as? AppleSignInError == .unavailable {
      return "This sign-in method is unavailable. Use another connected method or contact support."
    }
    if error as? APIError == .forbidden || error as? APIError == .conflict {
      return "This sign-in method could not verify the original account. Use another connected method or contact support."
    }
    if error as? APIError == .unauthenticated {
      return "The original session is no longer available. Account access remains locked. Contact support."
    }
    return "Identity verification could not finish. Use an existing connected sign-in method and try again."
  }

  func retry() async {
    guard isCurrent(), !isBusy, let intent else { return }
    if intent.stage == .serverDeleted { await finishLocalCleanup(); return }
    guard intent.stage == .submitted else { return }
    await submit(completionOnly: true)
  }

  private func submit(completionOnly: Bool) async {
    guard let intent, isCurrent() else { return }
    let attempt = generation
    state = .submitting
    errorMessage = nil
    do {
      try await lock()
      guard attempt == generation, isCurrent(), !Task.isCancelled else { state = .uncertain; return }
      let receipt = try await client.deleteAccount(scope: scope, proof: intent.proof, completionOnly: completionOnly)
      guard attempt == generation, isCurrent() else { return }
      var confirmed = intent
      confirmed.stage = .serverDeleted
      confirmed.cleanup = receipt.cleanup
      self.intent = confirmed
      await finishLocalCleanup()
    } catch {
      guard attempt == generation, isCurrent() else { return }
      state = .uncertain
      errorMessage = "Deletion could not be confirmed. Your local data is locked and preserved. Retry to check the same request."
    }
  }

  private func finishLocalCleanup() async {
    guard let intent, let status = intent.cleanup, intent.stage == .serverDeleted, isCurrent() else { return }
    let attempt = generation
    state = .submitting
    do {
      try persistence.save(intent)
      try await lock()
      guard attempt == generation, isCurrent() else { return }
      try await cleanup(scope)
      guard attempt == generation, isCurrent() else { return }
      try persistence.clear()
      self.intent = nil
      state = .completed(status)
    } catch {
      guard attempt == generation, isCurrent() else { return }
      state = .localCleanupFailed(status)
      errorMessage = "Your account was deleted. Local data still needs to be removed. Retry cleanup."
    }
  }
}
