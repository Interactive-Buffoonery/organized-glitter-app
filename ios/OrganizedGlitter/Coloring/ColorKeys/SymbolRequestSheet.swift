import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// What the picker needs to send a symbol missing from the catalog.
struct SymbolRequester {
  let bookLabel: String
  let email: String
  let send: (SymbolRequestDraft) async -> Result<String, ColorKeysModel.Failure>
}

/// "Can't find your symbol?": a photo of the symbol, where it's from, and how to reach the user.
struct SymbolRequestSheet: View {
  @Environment(\.connectionAvailable) private var connectionAvailable
  @Environment(\.dismiss) private var dismiss
  @Environment(\.theme) private var theme

  let requester: SymbolRequester
  /// Called with the request's `r:<id>` when the photo stands in for the symbol.
  let onUse: (String) -> Void

  @State private var draft: SymbolRequestDraft
  @State private var usePhoto = true
  @State private var selectedItem: PhotosPickerItem?
  @State private var isTakingPhoto = false
  @State private var cropPhoto: CropSelection?
  @State private var isPreparing = false
  @State private var isSending = false
  @State private var errorMessage: String?
  @State private var isSent = false
  /// Decoded once per photo, so typing in the form doesn't decode it again.
  @State private var preview: UIImage?

  init(requester: SymbolRequester, onUse: @escaping (String) -> Void) {
    self.requester = requester
    self.onUse = onUse
    _draft = State(initialValue: SymbolRequestDraft(bookLabel: requester.bookLabel, email: requester.email))
  }

  var body: some View {
    NavigationStack {
      Group {
        if isSent { sent } else { form }
      }
      .navigationTitle("Send a symbol")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        if isSent {
          ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
        } else {
          ToolbarItem(placement: .cancellationAction) {
            Button("Cancel", role: .cancel) { dismiss() }.disabled(isSending)
          }
          ToolbarItem(placement: .confirmationAction) {
            if isSending {
              ProgressView().accessibilityLabel("Sending photo")
            } else {
              Button("Send") {
                // Set before the Task starts so a second tap can't send twice.
                isSending = true
                Task { await send() }
              }
                .disabled(!connectionAvailable || isPreparing || draft.photo == nil)
                .accessibilityIdentifier("symbolRequest.send")
            }
          }
        }
      }
    }
    .interactiveDismissDisabled(isSending)
  }

  private var form: some View {
    Form {
      Section {
        if let image = preview {
          Image(uiImage: image)
            .resizable()
            .scaledToFit()
            .frame(maxWidth: .infinity, maxHeight: 200)
            .accessibilityLabel("Symbol photo")
        }
        let photoAction = draft.photo == nil ? "Choose Photo" : "Replace Photo"
        PhotosPicker(selection: $selectedItem, matching: .images) {
          Label(photoAction, systemImage: "photo")
            .frame(minHeight: 44)
        }
        .accessibilityIdentifier("symbolRequest.choosePhoto")
        // A modifier on the Section repeats on every row, so the task lives on this one.
        .task(id: selectedItem) { await prepareSelection() }
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
          Button("Take Photo", systemImage: "camera") { isTakingPhoto = true }
            .frame(minHeight: 44)
            .accessibilityLabel("Take symbol photo")
        }
        if let photo = draft.photo {
          Button("Crop", systemImage: "crop") { cropPhoto = CropSelection(photo: photo) }
            .frame(minHeight: 44)
        }
        if isPreparing { ProgressView("Preparing photo") }
      } header: {
        Text("Photo")
      } footer: {
        Text("A close-up of one symbol works best.")
      }
      .disabled(isPreparing)

      Section("Book and page") {
        TextField("Book and page", text: $draft.bookLabel)
          .accessibilityIdentifier("symbolRequest.bookLabel")
      }
      Section("Description") {
        TextField("Optional, like “two w’s stacked”", text: $draft.description, axis: .vertical)
          .accessibilityLabel("Description, optional")
          .accessibilityIdentifier("symbolRequest.description")
      }
      Section {
        TextField("Email", text: $draft.email)
          .keyboardType(.emailAddress)
          .textContentType(.emailAddress)
          .textInputAutocapitalization(.never)
          .autocorrectionDisabled()
          .accessibilityIdentifier("symbolRequest.email")
      } header: {
        Text("Email")
      } footer: {
        Text("We’ll email you when your symbol is added.")
      }
      Section {
        Toggle("Use my photo as the symbol on this page for now", isOn: $usePhoto)
          .accessibilityIdentifier("symbolRequest.usePhoto")
        if let errorMessage { AccessibleErrorLabel(message: errorMessage) }
        NeedsConnectionHint()
      }
    }
    // The draft is already captured once sending starts, so edits then would be lost.
    .disabled(isSending)
    .font(.karla(.body))
    .scrollContentBackground(.hidden)
    .background(theme.themedBackground.ignoresSafeArea())
    .fullScreenCover(isPresented: $isTakingPhoto) {
      CameraPicker { image in
        isTakingPhoto = false
        guard let image else { return }
        Task { await prepare { try await DetailPhotoProcessor.process(image: image) } }
      }
      .ignoresSafeArea()
    }
    .fullScreenCover(item: $cropPhoto) { selection in
      CoverCropView(photo: selection.photo, aspectRatio: 1, title: "Crop Photo",
        previewLabel: "Photo crop preview") { setPhoto($0) }
    }
  }

  private var sent: some View {
    ContentUnavailableView {
      Label("Thanks for sending it", systemImage: "checkmark.circle")
    } description: {
      Text("We’ll add your symbol and email you when it’s ready.")
    }
    .accessibilityIdentifier("symbolRequest.sent")
  }

  private func prepareSelection() async {
    guard let selectedItem else { return }
    defer { self.selectedItem = nil }
    await prepare { try await DetailPhotoProcessor.process(item: selectedItem) }
  }

  private func prepare(_ work: () async throws -> ProcessedDetailPhoto) async {
    isPreparing = true
    errorMessage = nil
    defer { isPreparing = false }
    do {
      let photo = try await work()
      try Task.checkCancellation()
      setPhoto(photo)
    } catch {
      errorMessage = DetailPhotoProcessingError.message(for: error)
    }
  }

  private func setPhoto(_ photo: ProcessedDetailPhoto) {
    draft.photo = photo
    preview = UIImage(data: photo.data)
  }

  private func send() async {
    errorMessage = nil
    defer { isSending = false }
    switch await requester.send(draft) {
    case .success(let symbol):
      if usePhoto {
        onUse(symbol)
      } else {
        isSent = true
        AccessibilityNotification.Announcement("Photo sent").post()
      }
    case .failure(let failure):
      errorMessage = failure.message
    }
  }
}
