import SwiftUI
import UIKit

struct PhotoViewerAction {
  let namespace: Namespace.ID
  let open: @MainActor (DetailPhoto.ID) -> Void
}

extension EnvironmentValues {
  @Entry var photoViewer: PhotoViewerAction? = nil
}

extension View {
  /// Presents `photos` full screen. `DetailPhotoTile`s and `photoViewerSource` views
  /// inside this view open it at their photo and zoom from it.
  func photoViewer(_ photos: [DetailPhoto]) -> some View {
    modifier(PhotoViewerPresenter(photos: photos))
  }

  /// Makes this view open the enclosing `photoViewer` at `id`. No-op when `id` is nil
  /// or no viewer encloses it.
  func photoViewerSource(_ id: DetailPhoto.ID?, accessibilityLabel: String? = nil) -> some View {
    modifier(PhotoViewerSource(id: id, accessibilityLabel: accessibilityLabel))
  }

  /// A single tappable photo, such as a cover, that opens full screen.
  func photoViewer(opening photo: DetailPhoto?) -> some View {
    photoViewerSource(photo?.id).photoViewer(photo.map { [$0] } ?? [])
  }
}

private struct PhotoViewerPresenter: ViewModifier {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Namespace private var namespace

  let photos: [DetailPhoto]

  @State private var isPresented = false
  @State private var currentID: DetailPhoto.ID?

  func body(content: Content) -> some View {
    content
      .environment(\.photoViewer, PhotoViewerAction(namespace: namespace, open: open))
      .onChange(of: photos.map(\.id)) { _, ids in
        if let currentID, !ids.contains(currentID) {
          isPresented = false
        }
      }
      .fullScreenCover(isPresented: $isPresented) {
        let viewer = PhotoViewer(photos: photos, selection: $currentID)
          .presentationBackground(.clear)
        if reduceMotion {
          viewer
        } else {
          viewer.navigationTransition(.zoom(sourceID: currentID ?? "", in: namespace))
        }
      }
  }

  private func open(_ id: DetailPhoto.ID) {
    guard photos.contains(where: { $0.id == id }) else { return }
    currentID = id
    isPresented = true
  }
}

private struct PhotoViewerSource: ViewModifier {
  @Environment(\.photoViewer) private var viewer

  let id: DetailPhoto.ID?
  let accessibilityLabel: String?

  func body(content: Content) -> some View {
    if let viewer, let id {
      Button {
        viewer.open(id)
      } label: {
        content
      }
      .buttonStyle(.plain)
      .matchedTransitionSource(id: id, in: viewer.namespace)
      .modifier(OptionalAccessibilityLabel(label: accessibilityLabel))
      .accessibilityHint("Opens full screen")
    } else {
      content
    }
  }
}

private struct OptionalAccessibilityLabel: ViewModifier {
  let label: String?

  func body(content: Content) -> some View {
    if let label {
      content.accessibilityLabel(label)
    } else {
      content
    }
  }
}

/// Full-screen photos: swipe between them, pinch or double-tap to zoom, pull down to close.
struct PhotoViewer: View {
  @Environment(\.dismiss) private var dismiss

  let photos: [DetailPhoto]
  @Binding var selection: DetailPhoto.ID?

  @State private var pullDistance: CGFloat = 0

  var body: some View {
    TabView(selection: $selection) {
      ForEach(photos) { photo in
        PhotoViewerPage(
          photo: photo,
          onPull: { pullDistance = $0 },
          onDismiss: { dismiss() }
        )
        .accessibilityAction(named: "Next photo") { step(1) }
        .accessibilityAction(named: "Previous photo") { step(-1) }
        .tag(Optional(photo.id))
      }
    }
    .tabViewStyle(.page(indexDisplayMode: .never))
    .background {
      Color.black.opacity(1 - min(pullDistance / 400, 0.7))
        .ignoresSafeArea()
    }
    .overlay(alignment: .top) {
      topBar.opacity(pullDistance > 0 ? 0 : 1)
    }
    .environment(\.colorScheme, .dark)
    .statusBarHidden()
    .accessibilityAction(.escape) { dismiss() }
    .accessibilityIdentifier("photoViewer")
    .onChange(of: selection) { _, _ in pullDistance = 0 }
  }

  private var topBar: some View {
    HStack {
      if let position = Self.position(of: selection, in: photos) {
        Text(position)
          .font(.subheadline.weight(.semibold).monospacedDigit())
          .padding(.horizontal, 12)
          .padding(.vertical, 6)
          .background(.ultraThinMaterial, in: .capsule)
          .accessibilityLabel("Photo \(position)")
      }
      Spacer(minLength: 8)
      if photos.count > 1 {
        Button {
          step(-1)
        } label: {
          Image(systemName: "chevron.left")
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(Self.neighbor(of: selection, offset: -1, in: photos) == nil)
        .accessibilityLabel("Previous photo")
        .accessibilityIdentifier("photoViewer.previous")

        Button {
          step(1)
        } label: {
          Image(systemName: "chevron.right")
            .frame(width: 44, height: 44)
            .background(.ultraThinMaterial, in: .circle)
        }
        .buttonStyle(.plain)
        .disabled(Self.neighbor(of: selection, offset: 1, in: photos) == nil)
        .accessibilityLabel("Next photo")
        .accessibilityIdentifier("photoViewer.next")
      }
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
          .font(.body.weight(.semibold))
          .frame(width: 44, height: 44)
          .background(.ultraThinMaterial, in: .circle)
          .contentShape(.circle)
      }
      .buttonStyle(.plain)
      .accessibilityLabel("Close")
      .accessibilityIdentifier("photoViewer.close")
    }
    .foregroundStyle(.white)
    .padding(.horizontal, 16)
    .padding(.top, 8)
  }

  private func step(_ offset: Int) {
    guard let id = Self.neighbor(of: selection, offset: offset, in: photos) else { return }
    selection = id
  }

  static func position(of id: DetailPhoto.ID?, in photos: [DetailPhoto]) -> String? {
    guard photos.count > 1, let index = photos.firstIndex(where: { $0.id == id }) else {
      return nil
    }
    return "\(index + 1) of \(photos.count)"
  }

  static func neighbor(
    of id: DetailPhoto.ID?, offset: Int, in photos: [DetailPhoto]
  ) -> DetailPhoto.ID? {
    guard let index = photos.firstIndex(where: { $0.id == id }) else { return nil }
    let target = index + offset
    return photos.indices.contains(target) ? photos[target].id : nil
  }
}

private struct PhotoViewerPage: View {
  static let fullPixelDimension: CGFloat = 4_096

  @Environment(\.pocketBaseClient) private var client

  let photo: DetailPhoto
  let onPull: (CGFloat) -> Void
  let onDismiss: () -> Void

  @State private var image: UIImage?
  @State private var failed = false

  var body: some View {
    ZStack {
      if let image {
        ZoomableImage(image: image, onPull: onPull, onDismiss: onDismiss)
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(photo.accessibilityLabel)
          .accessibilityAddTraits(.isImage)
          .accessibilityIdentifier("photoViewer.image")
      } else if failed {
        ContentUnavailableView("Photo unavailable", systemImage: "photo.badge.exclamationmark")
      } else {
        ProgressView()
          .accessibilityLabel("Loading photo")
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .overlay(alignment: .bottom) { footer }
    // Token renewals change the URL, not the file.
    .task(id: photo.fullSizeURL) { await load() }
  }

  @ViewBuilder
  private var footer: some View {
    let hasCaption = photo.date != nil || photo.caption != nil
    if hasCaption {
      VStack(alignment: .leading, spacing: 4) {
        if let date = photo.date {
          Text(date)
            .font(.subheadline.weight(.semibold))
        }
        if let caption = photo.caption {
          Text(caption)
            .font(.body)
            .lineLimit(5)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .accessibilityElement(children: .combine)
      .foregroundStyle(.white)
      .padding(.horizontal, 20)
      .padding(.top, 32)
      .padding(.bottom, 12)
      .background {
        LinearGradient(colors: [.clear, .black.opacity(0.7)], startPoint: .top, endPoint: .bottom)
          .ignoresSafeArea()
          .allowsHitTesting(false)
      }
    }
  }

  private func load() async {
    failed = false
    if image == nil,
      let thumbnail = try? await RemoteArtworkLoader.shared.load(
        from: photo.url, maxPixelDimension: 480, client: client)
    {
      image = UIImage(cgImage: thumbnail.cgImage)
    }
    do {
      let full = try await RemoteArtworkLoader.shared.load(
        from: photo.fullSizeURL,
        maxPixelDimension: Self.fullPixelDimension,
        client: client,
        cachesDecodedImage: false
      )
      image = UIImage(cgImage: full.cgImage)
    } catch is CancellationError {
      return
    } catch {
      // Offline without a cached original: keep the thumbnail.
      failed = image == nil
    }
  }
}

private struct ZoomableImage: UIViewRepresentable {
  let image: UIImage
  let onPull: (CGFloat) -> Void
  let onDismiss: () -> Void

  func makeUIView(context: Context) -> ZoomingImageScrollView {
    ZoomingImageScrollView()
  }

  func updateUIView(_ view: ZoomingImageScrollView, context: Context) {
    view.onPull = onPull
    view.onDismiss = onDismiss
    view.setImage(image)
  }
}

final class ZoomingImageScrollView: UIScrollView, UIScrollViewDelegate {
  var onPull: (CGFloat) -> Void = { _ in }
  var onDismiss: () -> Void = {}

  private let imageView = UIImageView()
  private var laidOutSize = CGSize.zero

  init() {
    super.init(frame: .zero)
    delegate = self
    minimumZoomScale = 1
    maximumZoomScale = 4
    alwaysBounceVertical = true
    isDirectionalLockEnabled = true
    showsVerticalScrollIndicator = false
    showsHorizontalScrollIndicator = false
    contentInsetAdjustmentBehavior = .never
    decelerationRate = .fast
    imageView.contentMode = .scaleAspectFit
    addSubview(imageView)

    let doubleTap = UITapGestureRecognizer(target: self, action: #selector(toggleZoom(_:)))
    doubleTap.numberOfTapsRequired = 2
    addGestureRecognizer(doubleTap)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  func setImage(_ image: UIImage) {
    guard imageView.image !== image else { return }
    let aspectChanged = imageView.image.map { !Self.sameAspect($0.size, image.size) } ?? true
    imageView.image = image
    if aspectChanged {
      laidOutSize = .zero
      setNeedsLayout()
    }
  }

  override func layoutSubviews() {
    super.layoutSubviews()
    guard let imageSize = imageView.image?.size, imageSize.width > 0, imageSize.height > 0,
      bounds.width > 0, bounds.height > 0
    else { return }
    if laidOutSize != bounds.size {
      laidOutSize = bounds.size
      zoomScale = 1
      let scale = min(bounds.width / imageSize.width, bounds.height / imageSize.height)
      imageView.frame = CGRect(
        origin: .zero,
        size: CGSize(width: imageSize.width * scale, height: imageSize.height * scale))
      contentSize = imageView.frame.size
    }
    centerImage()
  }

  func viewForZooming(in scrollView: UIScrollView) -> UIView? {
    imageView
  }

  func scrollViewDidZoom(_ scrollView: UIScrollView) {
    centerImage()
  }

  func scrollViewDidScroll(_ scrollView: UIScrollView) {
    onPull(pullDistance)
  }

  func scrollViewWillEndDragging(
    _ scrollView: UIScrollView,
    withVelocity velocity: CGPoint,
    targetContentOffset: UnsafeMutablePointer<CGPoint>
  ) {
    let pull = pullDistance
    if pull > 90 || (pull > 20 && velocity.y < -1.2) {
      onDismiss()
    }
  }

  private var pullDistance: CGFloat {
    guard zoomScale <= minimumZoomScale else { return 0 }
    return max(0, -(contentOffset.y + contentInset.top))
  }

  private func centerImage() {
    let horizontal = max(0, (bounds.width - contentSize.width) / 2)
    let vertical = max(0, (bounds.height - contentSize.height) / 2)
    let inset = UIEdgeInsets(top: vertical, left: horizontal, bottom: vertical, right: horizontal)
    if contentInset != inset { contentInset = inset }
  }

  @objc private func toggleZoom(_ gesture: UITapGestureRecognizer) {
    let animated = !UIAccessibility.isReduceMotionEnabled
    if zoomScale > minimumZoomScale {
      setZoomScale(minimumZoomScale, animated: animated)
      return
    }
    let point = gesture.location(in: imageView)
    let scale: CGFloat = 2.5
    let size = CGSize(width: bounds.width / scale, height: bounds.height / scale)
    zoom(
      to: CGRect(
        origin: CGPoint(x: point.x - size.width / 2, y: point.y - size.height / 2), size: size),
      animated: animated)
  }

  private static func sameAspect(_ first: CGSize, _ second: CGSize) -> Bool {
    guard first.height > 0, second.height > 0 else { return false }
    return abs(first.width / first.height - second.width / second.height) < 0.01
  }
}
