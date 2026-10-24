import SwiftUI
import UIKit

struct PickForMeView: View {
  @Environment(\.horizontalSizeClass) private var sizeClass
  @Environment(\.dynamicTypeSize) private var textSize
  @Environment(\.theme) private var theme
  @Environment(FormDrawer.self) private var formDrawer
  @Environment(\.protectedFiles) private var protectedFiles
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var model: LibraryRandomizer
  @State private var mode: RandomizerMode
  @State private var statuses = Dictionary(uniqueKeysWithValues:
    RandomizerMode.allCases.map { ($0, $0.defaultStatuses) })
  @State private var itemSelection = RandomizerItemSelection()
  @State private var search = ""
  @State private var presentedPanel: Panel?
  @State private var openedTarget: LibraryItem?
  @State private var logEditor: LibraryItemDetailModel?
  @State private var isPageVisible = false
  @State private var failureAnnouncements = SpinHistoryFailureAnnouncements()
  @State private var announcedNoSearchMatches = false
  @State private var wheelDisplayID = UUID()
  @State private var tickTask: Task<Void, Never>?

  let verticals: VerticalPreferences
  let onCollectionChanged: @MainActor @Sendable () async -> Void

  init(
    library: LibrarySession, initialSection: LibrarySection = .diamonds,
    verticals: VerticalPreferences,
    onCollectionChanged: @escaping @MainActor @Sendable () async -> Void
  ) {
    _model = State(initialValue: LibraryRandomizer(library: library))
    let requested = RandomizerMode.allCases.first { $0.section == initialSection } ?? .diamond
    _mode = State(initialValue: requested.isEnabled(for: verticals) ? requested
      : RandomizerMode.allCases.first { $0.isEnabled(for: verticals) } ?? requested)
    self.verticals = verticals
    self.onCollectionChanged = onCollectionChanged
  }

  var body: some View {
    let candidates = eligibleCandidates
    let selected = candidates.filter { itemSelection.ids?.contains($0.id) ?? true }
    let searched = searchedCandidates(in: candidates)
    let searchFeedback = SearchFeedback(query: search, hasMatches: !searched.isEmpty,
      isVisible: canAnnounceFeedback, isActive: model.library.isActive)
    let wheelCandidates = model.selection?.candidates ?? selected
    ScrollView {
      VStack(alignment: .leading, spacing: Theme.Spacing.md) {
        Picker(RandomizerPageCopy.craft, selection: $mode) {
          ForEach(RandomizerMode.allCases.filter { $0.isEnabled(for: verticals) }) { mode in
            Text(RandomizerPageCopy.modeTitle(mode)).tag(mode)
          }
        }
        .pickerStyle(.menu)
        .frame(minHeight: 44)
        .disabled(model.isSelecting)
        .accessibilityIdentifier("pickForMe.mode")
        if sizeClass == .regular, !textSize.isAccessibilitySize {
          HStack(alignment: .top, spacing: Theme.Spacing.md) {
            selectionPanel(candidates: candidates, selected: selected, searched: searched)
              .frame(maxWidth: .infinity)
            wheelPanel(selected: selected, candidates: candidates, wheelCandidates: wheelCandidates)
              .frame(maxWidth: .infinity)
          }
        } else {
          wheelPanel(selected: selected, candidates: candidates, wheelCandidates: wheelCandidates)
          selectionPanel(candidates: candidates, selected: selected, searched: searched)
        }
      }
      .foregroundStyle(theme.foreground)
      .padding()
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity)
    }
    .background { theme.themedBackground.ignoresSafeArea() }
    .navigationTitle(RandomizerPageCopy.title)
    .navigationDestination(item: $openedTarget) { item in
      LibraryItemDetailDestination(item: item, library: model.library,
        logEditor: $logEditor, onCollectionChanged: onCollectionChanged,
        onEditPageCount: { book in
          formDrawer.presentPageCountEditor(book: book, library: model.library) { _ in
            Task { await onCollectionChanged() }
          }
        })
    }
    .progressNoteDrawer(editor: $logEditor) { _ in await onCollectionChanged() }
    .sheet(item: $presentedPanel) { panel in
      NavigationStack {
        switch panel {
        case .key: keyPanel(wheelCandidates)
        }
      }
      .presentationSizing(.form)
    }
    .task { await model.library.loadSpinHistory() }
    .refreshable { await model.library.loadSpinHistory() }
    .task(id: searchFeedback) { await announceSearchFeedback(searchFeedback) }
    .onAppear {
      isPageVisible = true
      announceSpinHistoryFailures()
    }
    .onDisappear {
      isPageVisible = false
      if model.isSelecting { resetSelection() }
    }
    .onChange(of: model.library.spinHistoryLoadState) { _, state in
      if canAnnounceFeedback, state == .failed {
        AccessibilityNotification.Announcement(RandomizerPageCopy.historyLoadFailed).post()
      }
    }
    .onChange(of: model.library.spinHistoryFailures()) { _, _ in announceSpinHistoryFailures() }
    .onChange(of: canAnnounceFeedback) { _, visible in
      if visible { announceSpinHistoryFailures() }
    }
    .onChange(of: mode) { _, _ in search = ""; itemSelection.selectAll(); resetSelection() }
    .onChange(of: selectedStatuses) { _, _ in
      itemSelection.reconcile(candidates: candidates)
      resetSelection()
    }
    .onChange(of: candidates) { _, candidates in
      guard !model.isSelecting else { return }
      itemSelection.reconcile(candidates: candidates)
    }
    .onChange(of: verticals) { _, next in
      resetSelection()
      itemSelection.selectAll()
      if !mode.isEnabled(for: next),
        let available = RandomizerMode.allCases.first(where: { $0.isEnabled(for: next) }) {
        mode = available
      }
    }
    .onChange(of: model.library.isActive) { _, active in
      if !active { resetSelection(); presentedPanel = nil; openedTarget = nil }
    }
    .onReceive(NotificationCenter.default.publisher(for: UIAccessibility.voiceOverStatusDidChangeNotification)) { _ in
      if UIAccessibility.isVoiceOverRunning, model.isSelecting {
        spin()
      }
    }
    .onChange(of: reduceMotion) { _, reduced in
      if reduced, let id = model.selection?.id, model.isSelecting {
        withAnimation(nil) {
          wheelDisplayID = UUID()
          finishSpin(id: id)
        }
      }
    }
  }

  private func wheelPanel(selected: [RandomizerCandidate], candidates: [RandomizerCandidate],
    wheelCandidates: [RandomizerCandidate]) -> some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
      Button(action: spin) {
        VStack(spacing: Theme.Spacing.md) {
          ClassicRandomizerWheel(candidates: wheelCandidates, rotation: model.wheelRotation,
            winnerIndex: model.isSelecting ? nil : model.wheelSpin?.winnerIndex)
            .id(wheelDisplayID)
          Text(RandomizerPageCopy.action(mode))
            .font(.karla(.headline))
            .foregroundStyle(theme.primaryForeground)
            .padding(.horizontal, 24)
            .frame(minHeight: 48)
            .background(theme.primary, in: .capsule)
        }
        .frame(maxWidth: .infinity)
      }
      .buttonStyle(.plain)
      .disabled((selected.isEmpty && !model.isSelecting) || !model.library.isActive)
      .accessibilityLabel(RandomizerPageCopy.actionAccessibility(mode, count: wheelCandidates.count))
      .accessibilityIdentifier("pickForMe.pick")

      Button(RandomizerPageCopy.key, systemImage: "list.number") { presentedPanel = .key }
        .buttonStyle(QuietActionStyle())
        .disabled(wheelCandidates.isEmpty || model.isSelecting)
        .accessibilityLabel("Open wheel key")
        .accessibilityIdentifier("pickForMe.key")

      if !model.library.hasSnapshot {
        Text(RandomizerPageCopy.connection)
          .font(.karla(.subheadline))
          .fixedSize(horizontal: false, vertical: true)
      } else if selected.isEmpty {
        Text(candidates.isEmpty ? RandomizerPageCopy.empty(mode) : RandomizerPageCopy.noSelection(mode))
          .fixedSize(horizontal: false, vertical: true)
      }
      if !model.isSelecting, let selection = model.selection {
        result(selection)
      }
      historyPanel
    }
  }

  private var selectedStatuses: Set<String> { statuses[mode] ?? mode.defaultStatuses }

  private var canAnnounceFeedback: Bool {
    isPageVisible && presentedPanel == nil && logEditor == nil && openedTarget == nil
  }

  private func announceSpinHistoryFailures() {
    for message in failureAnnouncements.messages(
      for: model.library.spinHistoryFailures(), isPageVisible: canAnnounceFeedback) {
      AccessibilityNotification.Announcement(message).post()
    }
  }

  private func announceSearchFeedback(_ feedback: SearchFeedback) async {
    guard feedback.isVisible, feedback.isActive, !feedback.hasMatches,
      !feedback.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      announcedNoSearchMatches = false
      return
    }
    guard !announcedNoSearchMatches else { return }
    do { try await Task.sleep(for: .milliseconds(500)) } catch { return }
    guard !Task.isCancelled, canAnnounceFeedback, model.library.isActive,
      UIAccessibility.isVoiceOverRunning else { return }
    announcedNoSearchMatches = true
    AccessibilityNotification.Announcement(RandomizerPageCopy.noSearchMatches).post()
  }

  private struct SearchFeedback: Hashable {
    let query: String
    let hasMatches: Bool
    let isVisible: Bool
    let isActive: Bool
  }

  private var eligibleCandidates: [RandomizerCandidate] {
    model.library.randomizerCandidates(mode: mode, statuses: selectedStatuses, verticals: verticals)
  }

  private func searchedCandidates(in candidates: [RandomizerCandidate]) -> [RandomizerCandidate] {
    let query = search.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return candidates }
    return candidates.filter {
      "\($0.title) \($0.bookTitle ?? $0.item.subtitle)".lowercased().contains(query)
    }
  }

  private func spin() {
    if model.isSelecting, let id = model.selection?.id {
      withAnimation(nil) {
        wheelDisplayID = UUID()
        finishSpin(id: id)
      }
      return
    }
    let shouldAnimate = !reduceMotion && !UIAccessibility.isVoiceOverRunning
    let selectedCount = eligibleCandidates.filter { itemSelection.ids?.contains($0.id) ?? true }.count
    if shouldAnimate, selectedCount > 1 {
      var id: UUID?
      withAnimation(Theme.randomizerSpin, completionCriteria: .logicallyComplete) {
        id = model.beginSelection(mode: mode, statuses: selectedStatuses,
          selectedIDs: itemSelection.ids, verticals: verticals, eligibility: statuses)
      } completion: {
        if let id { finishSpin(id: id) }
      }
      if let id { startTicks(id: id) }
    } else if let id = model.beginSelection(mode: mode, statuses: selectedStatuses,
      selectedIDs: itemSelection.ids, verticals: verticals, eligibility: statuses) {
      finishSpin(id: id)
    }
  }

  private func finishSpin(id: UUID) {
    guard isPageVisible, model.isSelecting, model.selection?.id == id, model.library.isActive else {
      return
    }
    tickTask?.cancel()
    tickTask = nil
    guard let selection = model.finishSelection(id: id) else { return }
    itemSelection.reconcile(candidates: eligibleCandidates)
    let completedAt = Date()
    Task { await model.library.recordSpin(selection: selection, completedAt: completedAt) }
    AccessibilityNotification.Announcement(RandomizerPageCopy.announcement(selection.winner)).post()
    if UIDevice.current.userInterfaceIdiom == .phone {
      UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
  }

  private func resetSelection() {
    tickTask?.cancel()
    tickTask = nil
    withAnimation(nil) {
      wheelDisplayID = UUID()
      model.reset()
    }
  }

  private func startTicks(id: UUID) {
    guard UIDevice.current.userInterfaceIdiom == .phone, let spin = model.wheelSpin else { return }
    tickTask?.cancel()
    tickTask = Task { @MainActor in
      var feedback = RandomizerSpinFeedback(spin: spin)
      let generator = UISelectionFeedbackGenerator()
      let start = ProcessInfo.processInfo.systemUptime
      generator.prepare()
      while !Task.isCancelled, isPageVisible, model.isSelecting,
        model.selection?.id == id, model.library.isActive {
        do { try await Task.sleep(for: .milliseconds(110)) }
        catch { feedback.cancel(); return }
        guard !Task.isCancelled, isPageVisible, model.isSelecting,
          model.selection?.id == id, model.library.isActive else { return }
        if feedback.tick(at: ProcessInfo.processInfo.systemUptime - start) {
          generator.selectionChanged()
          generator.prepare()
        }
      }
    }
  }

  private func selectionPanel(candidates: [RandomizerCandidate], selected: [RandomizerCandidate],
    searched: [RandomizerCandidate]) -> some View {
    LazyVStack(alignment: .leading, spacing: Theme.Spacing.md) {
      VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        Text(RandomizerPageCopy.statusTitle(mode)).font(.karla(.headline))
          .accessibilityAddTraits(.isHeader)
        ForEach(mode.eligibleStatuses, id: \.self) { status in
          Toggle(isOn: Binding(get: { selectedStatuses.contains(status) }, set: { included in
            if included { statuses[mode, default: []].insert(status) }
            else { statuses[mode, default: []].remove(status) }
          })) {
            Label(RandomizerPageCopy.status(status, mode: mode),
              systemImage: mode.section.statusSystemImage(status))
              .fixedSize(horizontal: false, vertical: true)
          }
          .accessibilityIdentifier("pickForMe.status.\(status)")
        }
        Button { statuses[mode] = mode.defaultStatuses } label: {
          Text(RandomizerPageCopy.resetFilters).frame(minHeight: 44, alignment: .leading)
        }
      }
      LazyVStack(alignment: .leading, spacing: Theme.Spacing.sm) {
        Text(RandomizerPageCopy.selectorTitle(mode)).font(.karla(.headline))
          .accessibilityAddTraits(.isHeader)
        Text("\(selected.count) of \(candidates.count) selected")
          .font(.karla(.subheadline))
        TextField(RandomizerPageCopy.searchTitle(mode), text: $search)
          .textFieldStyle(.roundedBorder)
          .frame(minHeight: 44)
          .accessibilityLabel(RandomizerPageCopy.searchTitle(mode))
          .accessibilityIdentifier("pickForMe.search")
        Text(RandomizerPageCopy.searchNotice).font(.karla(.footnote))
        Button { itemSelection.selectAll(); resetSelection() } label: {
          Text(RandomizerPageCopy.selectAll).frame(minHeight: 44, alignment: .leading)
        }
          .accessibilityIdentifier("pickForMe.selectAll")
        Button { itemSelection.selectNone(); resetSelection() } label: {
          Text(RandomizerPageCopy.selectNone).frame(minHeight: 44, alignment: .leading)
        }
          .accessibilityIdentifier("pickForMe.selectNone")
        if searched.isEmpty, !search.isEmpty {
          Text(RandomizerPageCopy.noSearchMatches).font(.karla(.subheadline))
        }
        ForEach(searched) { candidate in
          Toggle(isOn: Binding(get: { itemSelection.ids?.contains(candidate.id) ?? true }, set: { included in
            itemSelection.setSelected(candidate.id, selected: included, candidates: candidates)
            resetSelection()
          })) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
              Text(candidate.title).font(.karla(.headline))
              Text(candidate.bookTitle ?? candidate.item.subtitle).font(.karla(.caption))
              Label(RandomizerPageCopy.status(candidate.item.status, mode: mode),
                systemImage: candidate.item.statusSystemImage)
                .font(.karla(.caption))
            }
            .fixedSize(horizontal: false, vertical: true)
          }
          .accessibilityIdentifier("pickForMe.item.\(candidate.item.id)")
        }
      }
    }
    .disabled(model.isSelecting)
    .padding()
    .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
  }

  private func keyPanel(_ candidates: [RandomizerCandidate]) -> some View {
    List {
      ForEach(Array(candidates.enumerated()), id: \.element.id) { index, candidate in
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
          Text("\(index + 1). \(candidate.title)").font(.karla(.headline))
          if let bookTitle = candidate.bookTitle { Text(bookTitle).font(.karla(.subheadline)) }
          Label(RandomizerPageCopy.status(candidate.item.status, mode: mode),
            systemImage: candidate.item.statusSystemImage)
            .font(.karla(.caption))
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
      }
    }
    .navigationTitle(RandomizerPageCopy.keyTitle)
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Done") { presentedPanel = nil } }
    }
  }

  private func result(_ selection: RandomizerSelection) -> some View {
    let hidesAnswer = model.library.hidesMysteryThumbnail(for: selection.winner.item)
    return VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      Text(RandomizerPageCopy.selectedTitle(selection.mode)).font(.karla(.headline))
        .accessibilityAddTraits(.isHeader)
      LibraryGalleryCard(item: selection.winner.item,
        imageURL: hidesAnswer ? nil
          : protectedFiles?.artworkURL(for: selection.winner.item, thumb: ArtworkThumb.gallery),
        mode: .covers, showsStatus: false, hidesMysteryAnswer: hidesAnswer)
        .accessibilityIdentifier("pickForMe.result")
      if let bookTitle = selection.winner.bookTitle { Text(bookTitle).font(.karla(.subheadline)) }
      Label(RandomizerPageCopy.status(selection.winner.item.status, mode: selection.mode),
        systemImage: selection.winner.item.statusSystemImage)
        .fixedSize(horizontal: false, vertical: true)
      Button {
        if let item = model.currentWinner(verticals: verticals) { openedTarget = item }
      } label: {
        Label(RandomizerPageCopy.viewAction(selection.mode), systemImage: "arrow.right.circle")
      }
      .buttonStyle(QuietActionStyle())
      .disabled(model.currentWinner(verticals: verticals) == nil)
      .accessibilityIdentifier("pickForMe.open")
      if model.currentWinner(verticals: verticals) == nil {
        Text(RandomizerPageCopy.unavailable)
          .fixedSize(horizontal: false, vertical: true)
      }
      if let state = model.library.spinHistorySaveStates[selection.id] {
        saveStatus(state)
      }
      Button { resetSelection() } label: {
        Text(RandomizerPageCopy.clearResult).frame(minHeight: 44, alignment: .leading)
      }
        .foregroundStyle(theme.pageAction)
    }
  }

  private var historyPanel: some View {
    VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
      Text(RandomizerPageCopy.historyTitle).font(.karla(.headline))
        .accessibilityAddTraits(.isHeader)
      ForEach(model.library.spinHistoryFailures(excluding: model.selection?.id)) { failure in
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
          Text(failure.title).font(.karla(.headline))
          saveStatus(failure.state)
        }
        .accessibilityIdentifier("pickForMe.historyFailure.\(failure.id)")
      }
      if model.library.spinHistoryLoadState == .loading {
        ProgressView(RandomizerPageCopy.loading)
      } else if model.library.spinHistoryLoadState == .failed {
        Text(RandomizerPageCopy.historyLoadFailed)
          .fixedSize(horizontal: false, vertical: true)
        Button(RandomizerPageCopy.retry) { Task { await model.library.loadSpinHistory() } }
          .buttonStyle(QuietActionStyle())
      } else if model.library.spinHistory.isEmpty,
        model.library.spinHistoryLoadState == .loaded {
        Text(RandomizerPageCopy.noSpins)
      }
      ForEach(Array(model.library.spinHistory.enumerated()), id: \.element.id) { index, spin in
        Button {
          if let item = model.library.spinHistoryTarget(spin, verticals: verticals) {
            openedTarget = item
          }
        } label: {
          HStack(spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
              Text(spin.title).font(.karla(.headline))
              if !spin.subtitle.isEmpty { Text(spin.subtitle).font(.karla(.subheadline)) }
              Text(RandomizerPageCopy.modeTitle(spin.mode)
                + (index == 0 ? " · \(RandomizerPageCopy.latest)" : ""))
                .font(.karla(.caption))
              HStack {
                if let date = historyDate(spin.spunAt) {
                  Text(date, format: .dateTime.year().month().day().hour().minute())
                }
                if let count = spin.optionCount { Text("\(count) \(RandomizerPageCopy.options)") }
              }
              .font(.karla(.caption))
            }
            .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").accessibilityHidden(true)
          }
          .frame(minHeight: 44)
          .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(model.library.spinHistoryTarget(spin, verticals: verticals) == nil)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("pickForMe.history.\(spin.id)")
      }
      if model.library.spinHistoryTotal > model.library.spinHistory.count,
        model.library.spinHistoryLimit == 8 {
        Button(RandomizerPageCopy.moreHistory) {
          Task { await model.library.loadSpinHistory(limit: 50) }
        }
        .buttonStyle(QuietActionStyle())
        .disabled(model.library.spinHistoryLoadState == .loading)
      }
    }
    .foregroundStyle(theme.foreground)
    .padding()
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(theme.card, in: .rect(cornerRadius: Theme.Radius.medium))
  }

  @ViewBuilder
  private func saveStatus(_ state: SpinHistorySaveState) -> some View {
    switch state {
    case .saving: ProgressView(RandomizerPageCopy.loading)
    case .notSent: Text(RandomizerPageCopy.spinNotSent).fixedSize(horizontal: false, vertical: true)
    case .rejected: Text(RandomizerPageCopy.spinRejected).fixedSize(horizontal: false, vertical: true)
    case .unknown:
      Text(RandomizerPageCopy.spinUnknown).fixedSize(horizontal: false, vertical: true)
      Button(RandomizerPageCopy.refreshHistory) { Task { await model.library.loadSpinHistory() } }
        .buttonStyle(QuietActionStyle())
    case .saved: EmptyView()
    }
  }

  private func historyDate(_ value: String) -> Date? {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    let normalized = value.replacingOccurrences(of: " ", with: "T")
    if let date = formatter.date(from: normalized) { return date }
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: normalized)
  }

  private enum Panel: String, Identifiable {
    case key
    var id: Self { self }
  }
}
