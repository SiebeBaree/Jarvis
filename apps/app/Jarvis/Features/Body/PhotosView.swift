import DesignSystem
import JarvisAPI
import Observation
import PhotosUI
import SwiftUI

// MARK: - Store

@Observable
@MainActor
final class PhotosStore {
    private(set) var photos: LoadState<[PhotoDTO]> = .idle
    var mutationError: String?
    /// True once an upload failed because the server has no Blob token.
    private(set) var blobNotConfigured = false

    private var model: AppModel?

    func configure(_ model: AppModel) {
        if self.model == nil { self.model = model }
    }

    func load() async {
        guard let model else { return }
        if photos.value == nil { photos = .loading }
        do {
            let response = try await model.api.photos(from: "2000-01-01", to: DayKeyMath.todayKey())
            photos = .loaded(response.photos.sorted { $0.dayKey > $1.dayKey })
        } catch {
            model.handle(error)
            if photos.value == nil {
                photos = .failed(TodayStore.message(for: error))
            } else {
                mutationError = TodayStore.message(for: error)
            }
        }
    }

    func upload(data: Data, angle: String, dayKey: DayKey) async {
        guard let model else { return }
        do {
            _ = try await model.api.uploadPhoto(
                data: data,
                contentType: "image/jpeg",
                angle: angle,
                dayKey: dayKey,
            )
            mutationError = nil
            await load()
        } catch APIClientError.api(let code, _, _) where code == "blob_not_configured" {
            blobNotConfigured = true
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }

    func delete(_ photo: PhotoDTO) async {
        guard let model else { return }
        do {
            _ = try await model.api.deletePhoto(id: photo.id)
            mutationError = nil
            await load()
        } catch {
            model.handle(error)
            mutationError = TodayStore.message(for: error)
        }
    }
}

// MARK: - Photos timeline

struct PhotosView: View {
    @Environment(AppModel.self) private var model

    @State private var store = PhotosStore()
    @State private var pickerItem: PhotosPickerItem?
    @State private var pendingUpload: PendingUpload?
    @State private var viewerPhoto: PhotoDTO?
    @State private var deleteCandidate: PhotoDTO?
    @State private var showCompare = false
    @State private var importFailed = false

    /// Downscaled JPEG waiting for its angle + date.
    struct PendingUpload: Identifiable {
        let id = UUID()
        let data: Data
    }

    private struct MonthGroup: Identifiable {
        let id: String // "yyyy-MM"
        let title: String
        let photos: [PhotoDTO]
    }

    var body: some View {
        Group {
            switch store.photos {
            case .loaded(let photos):
                if photos.isEmpty {
                    emptyState
                } else {
                    timeline(photos)
                }
            case .failed(let message):
                VStack(spacing: Space.lg) {
                    Text(message)
                        .font(.bodyJ)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await store.load() }
                    }
                    .buttonStyle(.jarvisSecondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(PageMargin.standard)
            default:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Label("Add photos", systemImage: "plus")
                }
                .accessibilityLabel("Add photos")
            }
            ToolbarItem(placement: .secondaryAction) {
                Button("Compare") { showCompare = true }
                    .disabled((store.photos.value?.count ?? 0) < 2)
            }
        }
        .onChange(of: pickerItem) {
            guard let pickerItem else { return }
            Task { await importPicked(pickerItem) }
        }
        .sheet(item: $pendingUpload) { pending in
            PhotoUploadSheet(imageData: pending.data) { angle, dayKey in
                await store.upload(data: pending.data, angle: angle, dayKey: dayKey)
            }
        }
        .sheet(item: $viewerPhoto) { photo in
            PhotoViewerSheet(photo: photo)
        }
        .sheet(isPresented: $showCompare) {
            PhotoCompareSheet(photos: store.photos.value ?? [])
        }
        .confirmationDialog(
            "Delete this photo?",
            isPresented: Binding(
                get: { deleteCandidate != nil },
                set: { if !$0 { deleteCandidate = nil } },
            ),
            titleVisibility: .visible,
        ) {
            Button("Delete photo", role: .destructive) {
                if let photo = deleteCandidate {
                    Task { await store.delete(photo) }
                }
                deleteCandidate = nil
            }
            Button("Cancel", role: .cancel) { deleteCandidate = nil }
        }
        .alert("Couldn't import that image", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        }
        .task {
            store.configure(model)
            await store.load()
        }
    }

    private func importPicked(_ item: PhotosPickerItem) async {
        defer { pickerItem = nil }
        guard let raw = try? await item.loadTransferable(type: Data.self),
              let jpeg = ImageDownscaler.jpegData(from: raw)
        else {
            importFailed = true
            return
        }
        pendingUpload = PendingUpload(data: jpeg)
    }

    // MARK: - Timeline

    private func timeline(_ photos: [PhotoDTO]) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if store.blobNotConfigured {
                    blobNotice
                }
                if let error = store.mutationError {
                    Text(error)
                        .font(.subheadJ)
                        .foregroundStyle(Color.warning)
                }
                ForEach(monthGroups(photos)) { group in
                    VStack(alignment: .leading, spacing: Space.sm) {
                        SectionHeader(group.title)
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 88, maximum: 120), spacing: Space.sm)],
                            spacing: Space.sm,
                        ) {
                            ForEach(group.photos) { photo in
                                thumbnail(photo)
                            }
                        }
                    }
                }
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: 760)
            .frame(maxWidth: .infinity)
        }
        .refreshable { await store.load() }
    }

    private func monthGroups(_ photos: [PhotoDTO]) -> [MonthGroup] {
        let grouped = Dictionary(grouping: photos) { String($0.dayKey.prefix(7)) }
        return grouped.keys.sorted(by: >).map { key in
            MonthGroup(
                id: key,
                title: monthTitle(key),
                photos: (grouped[key] ?? []).sorted { $0.dayKey > $1.dayKey },
            )
        }
    }

    private func monthTitle(_ month: String) -> String {
        guard let date = DayKeyMath.date(from: "\(month)-01") else { return month }
        return date.formatted(.dateTime.month(.wide).year())
    }

    private func thumbnail(_ photo: PhotoDTO) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            AsyncImage(url: URL(string: photo.url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Image(systemName: "photo")
                        .foregroundStyle(Color.textTertiary)
                default:
                    Color.bgSubtle
                }
            }
            .frame(width: 88, height: 88)
            .clipShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
            .overlay(alignment: .bottomLeading) {
                TagChip(photo.angle)
                    .padding(3)
            }
            .contentShape(Rectangle())
            .onTapGesture { viewerPhoto = photo }
            .contextMenu {
                Button("View") { viewerPhoto = photo }
                Button("Delete", role: .destructive) { deleteCandidate = photo }
            }

            Text(HabitDisplay.shortLabel(for: photo.dayKey))
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)
        }
    }

    private var blobNotice: some View {
        Text("Photo storage isn't configured yet — add the Vercel Blob token.")
            .font(.subheadJ)
            .foregroundStyle(Color.textSecondary)
            .padding(Space.md)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.bgSubtle, in: RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
    }

    private var emptyState: some View {
        ScrollView {
            VStack(spacing: Space.md) {
                if store.blobNotConfigured {
                    blobNotice
                }
                Text("Your first photo is the baseline — future you will thank you.")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text("Add a photo")
                }
                .buttonStyle(.jarvisPrimary)
                .padding(.top, Space.xs)
            }
            .padding(PageMargin.standard)
            .frame(maxWidth: .infinity)
            .padding(.top, Space.xxxl)
        }
    }
}

// MARK: - Upload sheet (angle + date)

private struct PhotoUploadSheet: View {
    let imageData: Data
    let onUpload: (String, DayKey) async -> Void

    @Environment(\.dismiss) private var dismiss

    /// Recently used angle labels, comma-separated, newest first.
    @AppStorage("bodyPhotoRecentAngles") private var recentAnglesRaw = "front,side,back"

    @State private var angle = "front"
    @State private var date: Date = .now
    @State private var isUploading = false

    private var recentAngles: [String] {
        recentAnglesRaw.split(separator: ",").map(String.init).filter { !$0.isEmpty }
    }

    private var trimmedAngle: String {
        angle.trimmingCharacters(in: .whitespaces).lowercased()
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    imagePreview
                        .listRowInsets(EdgeInsets())
                }
                Section("Angle") {
                    TextField("Angle (e.g. front)", text: $angle)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Space.sm) {
                            ForEach(recentAngles, id: \.self) { recent in
                                Button {
                                    angle = recent
                                } label: {
                                    Text(recent)
                                        .font(.captionJ)
                                        .foregroundStyle(recent == trimmedAngle ? Color.accentPrimary : Color.textSecondary)
                                        .padding(.horizontal, Space.sm)
                                        .padding(.vertical, 4)
                                        .background(
                                            recent == trimmedAngle ? Color.accentSubtle : Color.bgSubtle,
                                            in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous),
                                        )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                Section {
                    DatePicker("Date", selection: $date, in: ...Date.now, displayedComponents: .date)
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Add photo")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Upload") { upload() }
                        .disabled(trimmedAngle.isEmpty || isUploading)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    @ViewBuilder
    private var imagePreview: some View {
        #if canImport(UIKit)
        if let image = UIImage(data: imageData) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
        }
        #elseif canImport(AppKit)
        if let image = NSImage(data: imageData) {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 220)
                .frame(maxWidth: .infinity)
        }
        #endif
    }

    private func upload() {
        isUploading = true
        let chosen = trimmedAngle
        var recents = recentAngles.filter { $0 != chosen }
        recents.insert(chosen, at: 0)
        recentAnglesRaw = recents.prefix(6).joined(separator: ",")
        let dayKey = DayKeyMath.dayFormatter.string(from: date)
        Task {
            await onUpload(chosen, dayKey)
            dismiss()
        }
    }
}

// MARK: - Full-screen viewer

private struct PhotoViewerSheet: View {
    let photo: PhotoDTO

    @Environment(\.dismiss) private var dismiss
    @State private var zoom: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                AsyncImage(url: URL(string: photo.url)) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFit()
                            .scaleEffect(min(max(zoom * pinch, 1), 6))
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .gesture(
                                MagnifyGesture()
                                    .updating($pinch) { value, state, _ in
                                        state = value.magnification
                                    }
                                    .onEnded { value in
                                        zoom = min(max(zoom * value.magnification, 1), 6)
                                    },
                            )
                            .onTapGesture(count: 2) {
                                withAnimation(.easeOut(duration: 0.25)) { zoom = 1 }
                            }
                    case .failure:
                        Text("Couldn't load the photo")
                            .font(.subheadJ)
                            .foregroundStyle(Color.textSecondary)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    default:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            .background(Color.bgCanvas)
            .navigationTitle("\(photo.angle) · \(HabitDisplay.shortLabel(for: photo.dayKey))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 600)
        #endif
    }
}

// MARK: - Compare sheet

/// Two same-angle photos side by side with a draggable center divider
/// (split fraction clips the leading image over the trailing one).
private struct PhotoCompareSheet: View {
    let photos: [PhotoDTO]

    @Environment(\.dismiss) private var dismiss

    @State private var angle: String = ""
    @State private var leftId: String?
    @State private var rightId: String?
    @State private var split: CGFloat = 0.5

    private var angles: [String] {
        var seen: Set<String> = []
        return photos.compactMap { seen.insert($0.angle).inserted ? $0.angle : nil }
    }

    /// Photos of the selected angle, oldest first.
    private var candidates: [PhotoDTO] {
        photos.filter { $0.angle == angle }.sorted { $0.dayKey < $1.dayKey }
    }

    private var left: PhotoDTO? {
        candidates.first { $0.id == leftId } ?? candidates.first
    }

    private var right: PhotoDTO? {
        candidates.first { $0.id == rightId } ?? candidates.last
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: Space.lg) {
                angleChips

                if candidates.count >= 2, let left, let right {
                    comparePane(left: left, right: right)
                    pickers
                    caption(left: left, right: right)
                } else {
                    Text("Add at least two \(angle.isEmpty ? "" : "\(angle) ")photos to compare")
                        .font(.subheadJ)
                        .foregroundStyle(Color.textTertiary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .padding(PageMargin.standard)
            .background(Color.bgCanvas)
            .navigationTitle("Compare")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if angle.isEmpty {
                    // Prefer the angle with the most photos.
                    angle = angles.max { count(of: $0) < count(of: $1) } ?? angles.first ?? ""
                }
            }
            .onChange(of: angle) {
                leftId = nil
                rightId = nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 640, minHeight: 620)
        #endif
    }

    private func count(of angle: String) -> Int {
        photos.count { $0.angle == angle }
    }

    private var angleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Space.sm) {
                ForEach(angles, id: \.self) { candidate in
                    Button {
                        angle = candidate
                    } label: {
                        Text(candidate)
                            .font(.captionJ)
                            .foregroundStyle(candidate == angle ? Color.accentPrimary : Color.textSecondary)
                            .padding(.horizontal, Space.sm)
                            .padding(.vertical, 4)
                            .background(
                                candidate == angle ? Color.accentSubtle : Color.bgSubtle,
                                in: RoundedRectangle(cornerRadius: Radius.chip, style: .continuous),
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func comparePane(left: PhotoDTO, right: PhotoDTO) -> some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .leading) {
                compareImage(right)
                    .frame(width: width, height: proxy.size.height)

                compareImage(left)
                    .frame(width: width, height: proxy.size.height)
                    .mask(alignment: .leading) {
                        Rectangle().frame(width: width * split)
                    }

                // Divider + drag handle
                Rectangle()
                    .fill(Color.bgSurface)
                    .frame(width: 2)
                    .overlay(
                        Circle()
                            .fill(Color.bgSurface)
                            .frame(width: 28, height: 28)
                            .overlay(
                                Image(systemName: "arrow.left.and.right")
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(Color.textSecondary),
                            )
                            .shadow(color: .black.opacity(0.15), radius: 4),
                    )
                    .offset(x: width * split - 1)
                    .gesture(
                        DragGesture()
                            .onChanged { gesture in
                                split = min(max(gesture.location.x / width, 0.08), 0.92)
                            },
                    )

                // Date labels
                VStack {
                    HStack {
                        dateBadge(left.dayKey)
                        Spacer()
                        dateBadge(right.dayKey)
                    }
                    Spacer()
                }
                .padding(Space.sm)
            }
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
        }
        .frame(maxHeight: .infinity)
    }

    private func compareImage(_ photo: PhotoDTO) -> some View {
        AsyncImage(url: URL(string: photo.url)) { phase in
            switch phase {
            case .success(let image):
                image
                    .resizable()
                    .scaledToFill()
            case .failure:
                Color.bgSubtle.overlay(
                    Image(systemName: "photo").foregroundStyle(Color.textTertiary),
                )
            default:
                Color.bgSubtle
            }
        }
        .clipped()
    }

    private func dateBadge(_ dayKey: DayKey) -> some View {
        Text(HabitDisplay.shortLabel(for: dayKey))
            .font(.captionJ)
            .foregroundStyle(Color.textPrimary)
            .padding(.horizontal, Space.sm)
            .padding(.vertical, 3)
            .background(Color.bgSurface.opacity(0.85), in: Capsule())
    }

    private var pickers: some View {
        HStack(spacing: Space.lg) {
            photoPicker("Before", selection: Binding(
                get: { left?.id },
                set: { leftId = $0 },
            ))
            photoPicker("After", selection: Binding(
                get: { right?.id },
                set: { rightId = $0 },
            ))
        }
    }

    private func photoPicker(_ label: String, selection: Binding<String?>) -> some View {
        Picker(label, selection: selection) {
            ForEach(candidates) { photo in
                Text(HabitDisplay.shortLabel(for: photo.dayKey))
                    .tag(Optional(photo.id))
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
    }

    private func caption(left: PhotoDTO, right: PhotoDTO) -> some View {
        let days = daysApart(left.dayKey, right.dayKey)
        return Text("\(days) day\(days == 1 ? "" : "s") apart")
            .font(.captionJ)
            .foregroundStyle(Color.textSecondary)
    }

    private func daysApart(_ from: DayKey, _ to: DayKey) -> Int {
        guard let fromDate = DayKeyMath.date(from: from),
              let toDate = DayKeyMath.date(from: to)
        else { return 0 }
        return abs(Calendar.current.dateComponents([.day], from: fromDate, to: toDate).day ?? 0)
    }
}
