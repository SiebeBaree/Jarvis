import DesignSystem
import JarvisAPI
import PhotosUI
import SwiftUI

/// One improvement area: weekly photo timeline (newest first) with
/// J.A.R.V.I.S.'s commentary under each photo.
struct ImprovementAreaDetailView: View {
    @Environment(\.dismiss) private var dismiss

    let store: ImproveStore
    let areaId: String

    @State private var pickerItem: PhotosPickerItem?
    @State private var showEditor = false
    @State private var confirmingArchive = false
    @State private var fullscreenCheckin: AreaCheckinDTO?

    private var area: ImprovementAreaDTO? {
        store.response?.areas.first { $0.id == areaId }
    }

    private var timeline: [AreaCheckinDTO] {
        store.checkins[areaId] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.lg) {
                if let error = store.mutationError {
                    Text(error)
                        .font(.subheadJ)
                        .foregroundStyle(Color.danger)
                }
                if let area {
                    header(area)
                }
                if timeline.isEmpty {
                    emptyTimeline
                } else {
                    ForEach(timeline) { checkin in
                        checkinCard(checkin)
                    }
                }
            }
            .padding(PageMargin.standard)
            #if os(macOS)
            .frame(maxWidth: 640)
            .frame(maxWidth: .infinity)
            #endif
        }
        .background(Color.bgCanvas)
        .navigationTitle(area.map { "\($0.emoji ?? "") \($0.name)".trimmingCharacters(in: .whitespaces) } ?? "Area")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Edit area") { showEditor = true }
                    Button("Archive area", role: .destructive) { confirmingArchive = true }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Area options")
            }
        }
        .confirmationDialog(
            "Archive this area?",
            isPresented: $confirmingArchive,
            titleVisibility: .visible,
        ) {
            Button("Archive", role: .destructive) {
                Task {
                    await store.archiveArea(id: areaId)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Weekly check-ins stop; the photo history is kept.")
        }
        .sheet(isPresented: $showEditor) {
            AreaEditorView(store: store, editing: area)
        }
        .sheet(item: $fullscreenCheckin) { checkin in
            fullscreenPhoto(checkin)
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                if let data = try? await item.loadTransferable(type: Data.self) {
                    await store.uploadCheckin(areaId: areaId, imageData: data)
                    await store.loadCheckins(areaId: areaId)
                }
            }
        }
        .task {
            await store.loadCheckins(areaId: areaId)
        }
        .refreshable {
            await store.load()
            await store.loadCheckins(areaId: areaId)
        }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ area: ImprovementAreaDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.sm) {
            if let better = area.betterLooksLike, !better.isEmpty {
                Text("Better looks like: \(better)")
                    .font(.subheadJ)
                    .foregroundStyle(Color.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Group {
                if area.dueThisWeek {
                    checkinPicker(area).buttonStyle(.jarvisPrimary)
                } else {
                    checkinPicker(area).buttonStyle(.jarvisSecondary)
                }
            }
            .disabled(store.uploadingAreaIds.contains(areaId))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func checkinPicker(_ area: ImprovementAreaDTO) -> some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            HStack(spacing: Space.xs) {
                if store.uploadingAreaIds.contains(areaId) {
                    ProgressView().controlSize(.small)
                } else {
                    Image(systemName: "camera")
                        .font(.system(size: 12, weight: .medium))
                }
                Text(area.dueThisWeek ? "Check in this week" : "Replace this week's photo")
                    .font(.subheadJ)
            }
        }
    }

    // MARK: - Timeline

    private var emptyTimeline: some View {
        VStack(spacing: Space.sm) {
            Text("No check-ins yet")
                .font(.headlineJ)
                .foregroundStyle(Color.textPrimary)
            Text("Take the first photo — it becomes the baseline J.A.R.V.I.S. compares future weeks against.")
                .font(.subheadJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Space.xl)
    }

    private func checkinCard(_ checkin: AreaCheckinDTO) -> some View {
        VStack(alignment: .leading, spacing: Space.md) {
            HStack {
                Text("Week of \(HabitDisplay.shortLabel(for: checkin.weekKey))")
                    .font(.headlineJ)
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Text(HabitDisplay.shortLabel(for: checkin.dayKey))
                    .font(.captionJ)
                    .foregroundStyle(Color.textTertiary)
            }

            AsyncImage(url: URL(string: checkin.url)) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color.bgSubtle.overlay(
                        Image(systemName: "photo")
                            .foregroundStyle(Color.textTertiary),
                    )
                default:
                    Color.bgSubtle.overlay(ProgressView())
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 320)
            .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
            .contentShape(Rectangle())
            .onTapGesture { fullscreenCheckin = checkin }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .jarvisCard()
    }

    private func fullscreenPhoto(_ checkin: AreaCheckinDTO) -> some View {
        AsyncImage(url: URL(string: checkin.url)) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFit()
            default:
                ProgressView()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        #if os(macOS)
        .frame(minWidth: 600, minHeight: 700)
        #endif
    }
}
