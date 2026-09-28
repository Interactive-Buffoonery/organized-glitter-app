import PhotosUI
import SwiftUI
import UIKit

struct DiamondProjectDetailView: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  @Environment(\.theme) private var theme

  let project: DiamondProjectRecord
  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var isAddingNote = false
  @State private var revealedNoteID: String?
  @State private var highlightedNoteID: String?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          header
          DetailStatusRecovery(model: model, onCollectionChanged: onCollectionChanged)

          if !specs.isEmpty {
            DetailSpecStrip(
              specs: specs, isDisabled: model.isMutating || model.unresolvedWriteState != nil)
          }

          VStack(alignment: .leading, spacing: 12) {
            progressHeader
            if progressPhotos.isEmpty {
              ContentUnavailableView(
                "No progress photos",
                systemImage: "photo.on.rectangle",
                description: Text("Log a dated photo as your project changes.")
              )
              .frame(maxWidth: .infinity)
            } else {
              DetailPhotoContactSheet(
                photos: progressPhotos,
                pendingID: pendingNoteID,
                highlightedID: highlightedNoteID)
            }

            if model.canLoadMoreProgressNotes {
              Button {
                Task { await model.loadMoreProgressNotes() }
              } label: {
                HStack {
                  if model.isLoadingMore { ProgressView() }
                  Text(model.isLoadingMore ? "Loading more progress" : "Load more progress")
                }
                .frame(maxWidth: .infinity, minHeight: 44)
              }
              .buttonStyle(.bordered)
              .disabled(model.isLoadingMore)
              .accessibilityIdentifier("detail.diamond.loadMoreProgress")
            }

            if !isAddingNote, !model.unresolvedStatusWrite {
              unresolvedWriteRecovery
            }
          }

          detailSection("Details") {
            DetailMetadataCard {
              if let company = project.expand?.company?.name.nonEmpty {
                DetailMetadataRow(label: "Company", value: company)
              }
              if let artist = project.expand?.artist?.name.nonEmpty {
                DetailMetadataRow(label: "Artist", value: artist)
              }
              DetailMetadataRow(label: "Kit", value: project.kitCategory.capitalized)
              ForEach(dateFields, id: \.field) { row in
                DetailDateRow(
                  label: row.label,
                  value: row.value,
                  isDisabled: model.isMutating || model.unresolvedWriteState != nil
                ) { date in
                  save { await model.setDate(row.field, to: date) }
                }
              }
              if !project.tags.isEmpty {
                DetailMetadataRow(label: "Tags", value: project.tags.map(\.name).formatted(.list(type: .and)))
              }
              if let source = sourceURL {
                DetailMetadataRow(label: "Source") {
                  Link(source.host() ?? source.absoluteString, destination: source)
                    .lineLimit(1)
                }
                .accessibilityIdentifier("detail.diamond.source")
              }
            }

            if let notes = project.generalNotes?.plainTextFromHTML.nonEmpty {
              Text(notes)
                .foregroundStyle(theme.foreground)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
            }
          }

          if !model.progressNotes.isEmpty {
            detailSection("Progress notes") {
              ForEach(model.progressNotes) { note in
                VStack(alignment: .leading, spacing: 6) {
                  Text(noteDate(note.date))
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(theme.pageSecondaryForeground)
                  if let content = note.content.nonEmpty {
                    Text(content)
                      .foregroundStyle(theme.foreground)
                  }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
                .savedEntryReveal(
                  isPending: note.id == pendingNoteID, isHighlighted: note.id == highlightedNoteID)
                .id("note-\(note.id)")
              }
            }
          }

          if let errorMessage = model.errorMessage {
            VStack(alignment: .leading, spacing: 12) {
              AccessibleErrorLabel(message: errorMessage)
              Button("Try again") {
                Task { await model.load() }
              }
            }
          }

          if let mutationErrorMessage = model.mutationErrorMessage,
            !isAddingNote, model.unresolvedWriteState == nil
          {
            AccessibleErrorLabel(message: mutationErrorMessage)
          }
        }
        .frame(maxWidth: 760, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity)
      }
      .background {
        theme.themedBackground.ignoresSafeArea()
      }
      .refreshable { await model.refresh() }
      .sheet(isPresented: $isAddingNote, onDismiss: { revealSavedNote(proxy) }) {
        DiamondProgressNoteEditor(
          model: model,
          onCollectionChanged: onCollectionChanged
        )
        .drawer([.medium, .large])
      }
      .task(id: highlightedNoteID) {
        guard highlightedNoteID != nil else { return }
        do { try await Task.sleep(for: .seconds(1.6)) } catch { return }
        withAnimation(Theme.motion) { highlightedNoteID = nil }
      }
    }
  }

  /// A confirmed note stays invisible behind the editor until the sheet closes.
  private var pendingNoteID: String? {
    model.lastAddedProgressNoteID == revealedNoteID ? nil : model.lastAddedProgressNoteID
  }

  private func revealSavedNote(_ proxy: ScrollViewProxy) {
    guard let id = pendingNoteID else { return }
    let target = progressPhotos.contains { $0.id == id } ? "photo-\(id)" : "note-\(id)"
    withAnimation(reduceMotion ? nil : Theme.motion) {
      proxy.scrollTo(target, anchor: .center)
    }
    withAnimation(Theme.motion) {
      revealedNoteID = id
      highlightedNoteID = id
    }
  }

  private var progressPhotos: [DetailPhoto] {
    model.progressNotes.compactMap { note in
      guard let image = note.image?.nonEmpty,
        let url = protectedFiles?.url(
          collection: "progress_notes", recordID: note.id, filename: image,
          thumb: ArtworkThumb.gallery)
      else { return nil }
      return DetailPhoto(
        id: note.id,
        url: url,
        accessibilityLabel: progressPhotoLabel(for: note)
      )
    }
  }

  @ViewBuilder
  private var unresolvedWriteRecovery: some View {
    switch model.unresolvedWriteState {
    case .needsRefresh:
      if let message = model.mutationErrorMessage {
        AccessibleErrorLabel(message: message)
      }
      Button("Refresh status") {
        Task {
          if await model.refreshUnresolvedWriteStatus() {
            await onCollectionChanged()
          }
        }
      }
      .buttonStyle(.bordered)
      .disabled(model.isMutating)
      .accessibilityIdentifier("detail.diamond.noteRefresh")
    case .refreshed:
      if let message = model.mutationErrorMessage {
        Label(message, systemImage: "checkmark.circle")
          .foregroundStyle(theme.foreground)
      }
      Button("Done reviewing progress notes") {
        model.clearUnresolvedWriteRecovery()
      }
      .buttonStyle(.bordered)
    case nil:
      EmptyView()
    }
  }

  private var header: some View {
    VStack(spacing: 8) {
      CoverArtwork(
        item: .diamond(project),
        url: protectedFiles?.artworkURL(for: .diamond(project)),
        maxPixelDimension: 1_200,
        loadedAccessibilityLabel: "Project artwork"
      )
      .frame(width: horizontalSizeClass == .regular ? 300 : 204)
      .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
      .padding(.bottom, 8)
      .accessibilityIdentifier("detail.hero")

      DetailInlineTitle(
        value: project.title, field: "title", label: "Title", model: model,
        onCollectionChanged: onCollectionChanged)
      if !LibraryItem.diamond(project).subtitle.isEmpty {
        Text(LibraryItem.diamond(project).subtitle)
          .foregroundStyle(theme.pageSecondaryForeground)
      }
      DetailStatusMenu<DiamondStatus>(
        current: project.status, model: model, onCollectionChanged: onCollectionChanged)
      .padding(.top, 4)
    }
    .multilineTextAlignment(.center)
    .frame(maxWidth: .infinity)
  }

  private var progressHeader: some View {
    let layout =
      dynamicTypeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
      : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
    return layout {
      sectionTitle("Progress")
      if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }

      Button {
        isAddingNote = true
      } label: {
        Label("Log progress", systemImage: "plus.circle")
          .labelStyle(.titleAndIcon)
          .font(.subheadline)
          .frame(minHeight: 44)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .foregroundStyle(theme.pageAction)
      .disabled(model.isMutating || model.unresolvedWriteState != nil)
      .accessibilityIdentifier("detail.diamond.addNote")
    }
  }

  private var specs: [DetailSpec] {
    var specs: [DetailSpec] = []
    if let width = project.width, let height = project.height {
      specs.append(
        DetailSpec(
          title: "Size", value: "\(width.formatted())×\(height.formatted())", caption: "cm",
          accessibilityValue: "\(width.formatted()) by \(height.formatted()) centimeters"))
    }
    let drill = project.drillShape?.nonEmpty
    let kit = "\(project.kitCategory.lowercased()) kit"
    specs.append(
      DetailSpec(
        title: "Drill", value: drill?.capitalized ?? "Not set", caption: kit,
        accessibilityValue: "\(drill ?? "Not set"), \(kit)",
        choices: [
          DetailSpecChoice(
            title: "Drill shape",
            options: [("", "Not set"), ("round", "Round"), ("square", "Square")],
            selection: drill ?? ""
          ) { value in
            guard value != (drill ?? "") else { return }
            save { await model.updateFields(["drill_shape": value]) }
          },
          DetailSpecChoice(
            title: "Kit",
            options: [("full", "Full size"), ("mini", "Mini")],
            selection: project.kitCategory
          ) { value in
            guard value != project.kitCategory else { return }
            save { await model.updateFields(["kit_category": value]) }
          },
        ]))
    if let total = project.totalDiamonds, total > 0 {
      let colors = project.colorCount.flatMap { $0 > 0 ? "\(Int($0)) colors" : nil }
      specs.append(
        DetailSpec(
          title: "Diamonds",
          value: Int(total).formatted(.number.notation(.compactName).precision(.significantDigits(1...3))),
          caption: colors,
          accessibilityValue: [Int(total).formatted(), colors].compactMap { $0 }.joined(separator: ", ")))
    }
    if let started = project.dateStarted.flatMap({ DetailDateOnly.date($0) }),
      let day = project.dateStarted.flatMap({ DetailDateOnly.monthDay($0) })
    {
      let end = project.dateCompleted.flatMap { DetailDateOnly.date($0) } ?? .now
      let elapsed = DetailDateOnly.elapsed(from: started, to: end)
      specs.append(
        DetailSpec(
          title: "Started", value: day, caption: elapsed,
          accessibilityValue: [day, elapsed].compactMap { $0 }.joined(separator: ", ")))
    }
    return specs
  }

  private var dateFields: [(field: String, label: String, value: String?)] {
    [
      ("date_purchased", "Purchased", project.datePurchased),
      ("date_received", "Received", project.dateReceived),
      ("date_started", "Started", project.dateStarted),
      ("date_completed", "Completed", project.dateCompleted),
    ]
  }

  private func save(_ write: @escaping @MainActor () async -> Bool) {
    saveDetailChange(write, onCollectionChanged: onCollectionChanged)
  }

  private var sourceURL: URL? {
    guard let url = project.sourceURL?.nonEmpty.flatMap(URL.init(string:)),
      ["http", "https"].contains(url.scheme?.lowercased())
    else { return nil }
    return url
  }

  private func sectionTitle(_ title: String) -> some View {
    Text(title)
      .font(.title3.weight(.semibold))
      .foregroundStyle(theme.foreground)
      .accessibilityAddTraits(.isHeader)
  }

  private func noteDate(_ value: String) -> String {
    DetailDateOnly.formatted(value) ?? value
  }

  private func progressPhotoLabel(for note: DiamondProgressNoteRecord) -> String {
    let base = "Progress photo from \(noteDate(note.date))"
    let caption = note.content
      .replacingOccurrences(of: "\n", with: " ")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return caption.isEmpty ? base : "\(base): \(caption)"
  }

  private func detailSection<Content: View>(
    _ title: String,
    @ViewBuilder content: () -> Content
  ) -> some View {
    VStack(alignment: .leading, spacing: 12) {
      sectionTitle(title)
      content()
    }
  }
}

struct DiamondProgressNoteEditor: View {
  @Environment(\.dismiss) private var dismiss
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let model: LibraryItemDetailModel
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  @State private var date = Date()
  @State private var content = ""
  @State private var selectedItem: PhotosPickerItem?
  @State private var processedPhoto: ProcessedDetailPhoto?
  @State private var previewImage: UIImage?
  @State private var isPreparingPhoto = false
  @State private var photoErrorMessage: String?

  var body: some View {
    let photoPickerTitle =
      processedPhoto == nil ? "Choose photo" : "Choose a different photo"

    NavigationStack {
      Form {
        Group {
          Section("Progress") {
            DatePicker("Date", selection: $date, displayedComponents: .date)
            TextField("Caption (optional)", text: $content, axis: .vertical)
              .lineLimit(3...8)
            Text("Add a photo, a caption, or both.")
              .font(.footnote)
              .foregroundStyle(theme.pageSecondaryForeground)
          }
          .disabled(model.unresolvedWriteState != nil)

          Section("Photo") {
            if isPreparingPhoto || previewImage != nil {
              photoPreview
            }

            PhotosPicker(selection: $selectedItem, matching: .images) {
              Label(
                photoPickerTitle,
                systemImage: "photo.on.rectangle"
              )
            }
            .disabled(isPreparingPhoto || model.isMutating)
          }
          .disabled(model.unresolvedWriteState != nil)

          if model.isMutating {
            Section {
              ProgressView(
                model.unresolvedWriteState == nil
                  ? (processedPhoto == nil ? "Adding progress note…" : "Uploading photo…")
                  : "Checking save status…"
              )
            }
          }

          if let message = photoErrorMessage {
            Section {
              AccessibleErrorLabel(message: message)
            }
          } else if let message = model.mutationErrorMessage {
            Section {
              if model.unresolvedWriteState == .refreshed {
                Label(message, systemImage: "checkmark.circle")
                  .foregroundStyle(theme.foreground)
              } else {
                AccessibleErrorLabel(message: message)
              }
            }
          }
        }
        .listRowBackground(theme.card)
      }
      .themedScrollBackground()
      .navigationTitle("Add progress note")
      .navigationBarTitleDisplayMode(.inline)
      .interactiveDismissDisabled(model.isMutating)
      .accessibilityIdentifier("detail.diamond.noteEditor")
      .toolbar {
        ToolbarItem(placement: .cancellationAction) {
          Button("Cancel") { dismiss() }
            .disabled(model.isMutating)
        }
        ToolbarItem(placement: .confirmationAction) {
          switch model.unresolvedWriteState {
          case .needsRefresh:
            Button("Refresh status") {
              Task { await refreshUploadStatus() }
            }
            .disabled(model.isMutating)
            .accessibilityIdentifier("detail.diamond.noteRefresh")
          case .refreshed:
            Button("Back to project") {
              model.clearUnresolvedWriteRecovery()
              dismiss()
            }
            .accessibilityIdentifier("detail.diamond.noteReview")
          case nil:
            Button(model.mutationErrorMessage == nil ? "Add" : "Try again") {
              Task { await submit() }
            }
            .disabled(!canSubmit || isPreparingPhoto || model.isMutating)
            .accessibilityIdentifier(
              model.mutationErrorMessage == nil
                ? "detail.diamond.noteSubmit" : "detail.diamond.noteRetry"
            )
          }
        }
      }
      .task(id: selectedItem) {
        await prepareSelectedPhoto()
      }
    }
    .sensoryFeedback(.success, trigger: model.lastAddedProgressNoteID) { _, saved in saved != nil }
  }

  /// A fixed 4:5 frame, so preparing and the finished preview never move the form.
  private var photoPreview: some View {
    ZStack {
      RoundedRectangle(cornerRadius: Theme.Radius.medium)
        .fill(theme.muted.opacity(0.45))
      if let previewImage {
        Image(uiImage: previewImage)
          .resizable()
          .scaledToFit()
          .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.medium))
          .transition(.opacity)
          .accessibilityLabel("Selected progress photo")
          .accessibilityIdentifier("detail.diamond.notePhoto")
      } else {
        ProgressView("Preparing photo…")
          .transition(.opacity)
      }
    }
    .aspectRatio(4 / 5, contentMode: .fit)
    .frame(maxHeight: dynamicTypeSize.isAccessibilitySize ? 440 : 320)
    .frame(maxWidth: .infinity)
    .animation(Theme.motion, value: previewImage)
  }

  private var canSubmit: Bool {
    photoErrorMessage == nil
      && (processedPhoto != nil || !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
  }

  private func prepareSelectedPhoto() async {
    guard let selectedItem else { return }
    isPreparingPhoto = true
    photoErrorMessage = nil
    model.mutationErrorMessage = nil
    processedPhoto = nil
    previewImage = nil
    AccessibilityNotification.Announcement("Preparing photo").post()
    defer { isPreparingPhoto = false }
    do {
      let photo = try await DetailPhotoProcessor.process(
        item: selectedItem
      )
      try Task.checkCancellation()
      processedPhoto = photo
      previewImage = await Task.detached(priority: .userInitiated) {
        UIImage(data: photo.data)
      }.value
    } catch is CancellationError {
      return
    } catch let error as DetailPhotoProcessingError {
      photoErrorMessage = error.message
      self.selectedItem = nil
    } catch {
      photoErrorMessage = "That photo could not be prepared. Try another image."
      self.selectedItem = nil
    }
  }

  private func submit() async {
    guard canSubmit else { return }
    AccessibilityNotification.Announcement(
      processedPhoto == nil ? "Adding progress note" : "Uploading photo"
    ).post()
    if await model.addDiamondProgressNote(content: content, date: date, photo: processedPhoto) {
      await onCollectionChanged()
      AccessibilityNotification.Announcement(
        processedPhoto == nil ? "Progress note added" : "Photo added"
      ).post()
      dismiss()
    } else if model.unresolvedWriteState == .refreshed {
      AccessibilityNotification.Announcement(
        processedPhoto == nil
          ? "Progress notes refreshed. Review them before adding another note."
          : "Progress notes and photos refreshed. Review them before adding another note."
      ).post()
    }
  }

  private func refreshUploadStatus() async {
    AccessibilityNotification.Announcement("Refreshing progress note status").post()
    if await model.refreshUnresolvedWriteStatus() {
      await onCollectionChanged()
      AccessibilityNotification.Announcement(
        processedPhoto == nil ? "Progress notes refreshed" : "Progress notes and photos refreshed"
      ).post()
    }
  }
}

/// A date-only field edited in place, committed only after the picker closes.
private struct DetailDateRow: View {
  @Environment(\.theme) private var theme
  @State private var isEditingDate = false
  @State private var draftDate = Date.now

  let label: String
  let value: String?
  let isDisabled: Bool
  let onChange: (Date?) -> Void

  var body: some View {
    let storedDate = value.flatMap { DetailDateOnly.date($0) }
    DetailMetadataRow(label: label, combinesChildren: false) {
      HStack(spacing: 0) {
        Button {
          draftDate = storedDate ?? .now
          isEditingDate = true
        } label: {
          if let value, let formatted = DetailDateOnly.formatted(value) {
            Text(formatted)
              .frame(minHeight: 44)
              .contentShape(.rect)
          } else {
            Label("Add date", systemImage: "plus")
              .frame(minHeight: 44)
              .contentShape(.rect)
          }
        }
        .buttonStyle(.plain)
        .foregroundStyle(theme.pageAction)
        .accessibilityLabel(storedDate == nil
          ? "Add \(label.lowercased()) date" : "Change \(label.lowercased()) date")
        .accessibilityValue(value.flatMap { DetailDateOnly.formatted($0) } ?? "No date")
        if storedDate != nil {
          Button {
            onChange(nil)
          } label: {
            Image(systemName: "xmark.circle.fill")
              .foregroundStyle(theme.pageSecondaryForeground)
              .frame(width: 44, height: 44)
              .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .accessibilityLabel("Clear \(label.lowercased()) date")
        }
      }
    }
    .disabled(isDisabled)
    .accessibilityIdentifier("detail.date.\(label.lowercased())")
    .popover(isPresented: $isEditingDate) {
      VStack(alignment: .leading, spacing: 16) {
        Text("\(storedDate == nil ? "Add" : "Change") \(label.lowercased()) date")
          .font(.headline)
          .foregroundStyle(theme.foreground)
        DatePicker(label, selection: $draftDate, displayedComponents: .date)
          .datePickerStyle(.graphical)
        HStack {
          Button("Cancel") { isEditingDate = false }
          Spacer()
          Button("Save") {
            isEditingDate = false
            if storedDate.map({ DetailDateOnly.string(from: $0) })
              != DetailDateOnly.string(from: draftDate)
            {
              onChange(draftDate)
            }
          }
          .buttonStyle(.borderedProminent)
        }
      }
      .padding()
      .frame(maxWidth: 380)
      .background(theme.card)
      .presentationCompactAdaptation(.sheet)
      .presentationDetents([.medium, .large])
      .presentationDragIndicator(.visible)
    }
  }
}

struct DetailMetadataCard<Content: View>: View {
  @Environment(\.theme) private var theme
  let content: Content

  init(@ViewBuilder content: () -> Content) {
    self.content = content()
  }

  var body: some View {
    VStack(spacing: 0) {
      content
    }
    .padding(.horizontal, 16)
    .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
  }
}

struct DetailMetadataRow<Content: View>: View {
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.theme) private var theme

  let label: String
  let content: Content
  private var combinesChildren = true

  init(label: String, value: String) where Content == Text {
    self.label = label
    content = Text(value)
  }

  /// Rows holding several controls pass `combinesChildren: false` so each stays reachable.
  init(label: String, combinesChildren: Bool = true, @ViewBuilder content: () -> Content) {
    self.label = label
    self.combinesChildren = combinesChildren
    self.content = content()
  }

  var body: some View {
    Group {
      if dynamicTypeSize.isAccessibilitySize {
        VStack(alignment: .leading, spacing: 4) {
          labelView
          content
            .foregroundStyle(theme.foreground)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
      } else {
        LabeledContent {
          content
            .foregroundStyle(theme.foreground)
        } label: {
          labelView
        }
      }
    }
    .accessibilityElement(children: combinesChildren ? .combine : .contain)
    .padding(.vertical, 10)
    .frame(minHeight: 44)
    .overlay(alignment: .bottom) {
      Divider()
    }
  }

  private var labelView: some View {
    Text(label)
      .foregroundStyle(theme.pageSecondaryForeground)
  }
}
