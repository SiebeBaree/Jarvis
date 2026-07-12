import DesignSystem
import JarvisAPI
import PhotosUI
import SwiftUI

/// The weekly check-in flow: one page per due area — pick a photo, upload,
/// next. Ends with a short "J.A.R.V.I.S. will comment shortly" screen.
struct CheckinFlowView: View {
    @Environment(\.dismiss) private var dismiss

    let store: ImproveStore

    /// Areas due when the flow opened (a stable list — uploads change due
    /// state mid-flow and must not reshuffle the pages).
    @State private var queue: [ImprovementAreaDTO] = []
    @State private var index = 0
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedData: Data?
    @State private var uploadError: String?
    @State private var isUploading = false
    @State private var finished = false

    private var current: ImprovementAreaDTO? {
        queue.indices.contains(index) ? queue[index] : nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if !finished, let area = current {
                    areaPage(area)
                } else {
                    doneScreen
                }
            }
            .background(Color.bgCanvas)
            .navigationTitle("Weekly check-in")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear {
            if queue.isEmpty { queue = store.dueAreas }
            if queue.isEmpty { finished = true }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task {
                pickedData = try? await item.loadTransferable(type: Data.self)
                uploadError = pickedData == nil ? "That image could not be read." : nil
            }
        }
        #if os(macOS)
        .frame(minWidth: 520, minHeight: 640)
        #endif
    }

    // MARK: - Area page

    private func areaPage(_ area: ImprovementAreaDTO) -> some View {
        VStack(spacing: Space.lg) {
            Text("\(index + 1) of \(queue.count)")
                .font(.captionJ)
                .foregroundStyle(Color.textTertiary)

            VStack(spacing: Space.xs) {
                Text("\(area.emoji ?? "🎯") \(area.name)")
                    .font(.title2J)
                    .foregroundStyle(Color.textPrimary)
                if let better = area.betterLooksLike, !better.isEmpty {
                    Text(better)
                        .font(.subheadJ)
                        .foregroundStyle(Color.textSecondary)
                        .multilineTextAlignment(.center)
                }
            }

            preview

            if let uploadError {
                Text(uploadError)
                    .font(.subheadJ)
                    .foregroundStyle(Color.danger)
            }

            Spacer(minLength: 0)

            VStack(spacing: Space.sm) {
                PhotosPicker(selection: $pickerItem, matching: .images) {
                    Text(pickedData == nil ? "Choose photo" : "Choose a different photo")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.jarvisSecondary)

                Button {
                    upload(area)
                } label: {
                    if isUploading {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("Save check-in").frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.jarvisPrimary)
                .disabled(pickedData == nil || isUploading)

                Button("Skip this area") { advance() }
                    .buttonStyle(.jarvisGhost)
                    .disabled(isUploading)
            }
            .frame(maxWidth: 420)
        }
        .padding(PageMargin.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private var preview: some View {
        if let data = pickedData, let image = platformImage(from: data) {
            image
                .resizable()
                .scaledToFill()
                .frame(maxWidth: 420)
                .frame(height: 300)
                .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
        } else {
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(Color.bgSubtle)
                .frame(maxWidth: 420)
                .frame(height: 300)
                .overlay(
                    VStack(spacing: Space.sm) {
                        Image(systemName: "camera")
                            .font(.system(size: 28, weight: .light))
                            .foregroundStyle(Color.textTertiary)
                        Text("Same angle and light as last week works best")
                            .font(.captionJ)
                            .foregroundStyle(Color.textTertiary)
                    },
                )
        }
    }

    private func platformImage(from data: Data) -> Image? {
        #if os(macOS)
        NSImage(data: data).map(Image.init(nsImage:))
        #else
        UIImage(data: data).map(Image.init(uiImage:))
        #endif
    }

    // MARK: - Actions

    private func upload(_ area: ImprovementAreaDTO) {
        guard let data = pickedData else { return }
        isUploading = true
        uploadError = nil
        Task {
            let ok = await store.uploadCheckin(areaId: area.id, imageData: data)
            isUploading = false
            if ok {
                advance()
            } else {
                uploadError = store.mutationError ?? "Upload failed — try again."
            }
        }
    }

    private func advance() {
        pickedData = nil
        uploadError = nil
        if index + 1 < queue.count {
            index += 1
        } else {
            finished = true
        }
    }

    // MARK: - Done

    private var doneScreen: some View {
        VStack(spacing: Space.xl) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Color.success)
            Text("Check-in done")
                .font(.title2J)
                .foregroundStyle(Color.textPrimary)
            Text("J.A.R.V.I.S. is comparing this week's photos with previous weeks. Its comments appear on each area in Improve shortly.")
                .font(.bodyJ)
                .foregroundStyle(Color.textSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button("Done") { dismiss() }
                .buttonStyle(.jarvisPrimary)
        }
        .padding(PageMargin.standard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
