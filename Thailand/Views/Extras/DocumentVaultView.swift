import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers

/// Face ID–locked travel documents (passport, flights, hotel bookings). Never synced.
struct DocumentVaultView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var vault = DocumentVault.shared

    @State private var pickerItem: PhotosPickerItem?
    @State private var showingCamera = false
    @State private var showingFileImporter = false
    @State private var previewURL: URL?
    @State private var pendingData: (data: Data, kind: VaultDocument.Kind)?
    @State private var newTitle = ""
    @State private var renaming: VaultDocument?

    var body: some View {
        NavigationStack {
            Group {
                if vault.isUnlocked {
                    unlockedList
                } else {
                    EmptyStateView(
                        systemImage: "lock.doc.fill",
                        title: "Travel Documents",
                        message: "Passport, visa, flight and hotel confirmations — stored only on this iPhone, encrypted, and opened with Face ID. Never synced or shared."
                    ) {
                        Button {
                            Task { await vault.unlock() }
                        } label: {
                            Label("Unlock with Face ID", systemImage: "faceid")
                        }
                        .buttonStyle(.primary)
                        if let error = vault.lastError {
                            Text(error).font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
            }
            .background(Theme.background)
            .navigationTitle("Documents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        vault.lock()
                        dismiss()
                    }
                }
                if vault.isUnlocked {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                                Button("Take Photo", systemImage: "camera") { showingCamera = true }
                            }
                            Button("Choose Photo", systemImage: "photo") { pickerItemPresented = true }
                            Button("Import PDF or Image", systemImage: "doc") { showingFileImporter = true }
                        } label: {
                            Image(systemName: "plus.circle.fill").font(.title2)
                        }
                        .accessibilityLabel("Add document")
                    }
                }
            }
            .photosPicker(isPresented: $pickerItemPresented, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        askForTitle(data, kind: .image)
                    }
                    pickerItem = nil
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in askForTitle(data, kind: .image) }
                    .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image]) { result in
                guard case .success(let url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                if let data = try? Data(contentsOf: url) {
                    let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
                    newTitle = url.deletingPathExtension().lastPathComponent
                    pendingData = (data, isPDF ? .pdf : .image)
                }
            }
            .alert("Name this document", isPresented: Binding(get: { pendingData != nil }, set: { if !$0 { pendingData = nil } })) {
                TextField("e.g. Passport – Alex", text: $newTitle)
                Button("Save") {
                    if let pendingData {
                        vault.add(data: pendingData.data, title: newTitle.isEmpty ? "Document" : newTitle, kind: pendingData.kind)
                    }
                    pendingData = nil
                    newTitle = ""
                }
                Button("Cancel", role: .cancel) { pendingData = nil }
            }
            .alert("Rename", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("Title", text: $newTitle)
                Button("Save") {
                    if let renaming { vault.rename(renaming, to: newTitle) }
                    renaming = nil
                }
                Button("Cancel", role: .cancel) { renaming = nil }
            }
            .quickLookPreview($previewURL)
            .onChange(of: scenePhase) { _, phase in
                // Lock again as soon as the app leaves the screen.
                if phase != .active { vault.lock() }
            }
        }
    }

    @State private var pickerItemPresented = false

    private var unlockedList: some View {
        List {
            if vault.documents.isEmpty {
                Text("Add photos of your passport, visa, flights and hotel bookings so you have them offline.")
                    .foregroundStyle(.secondary)
            }
            ForEach(vault.documents) { document in
                Button {
                    previewURL = vault.url(for: document)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: document.kind == .pdf ? "doc.richtext.fill" : "photo.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.lagoon)
                            .frame(width: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(document.title).font(.headline).foregroundStyle(.primary)
                            Text(document.createdAt.formatted(date: .abbreviated, time: .omitted))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") {
                        newTitle = document.title
                        renaming = document
                    }
                    Button("Delete", systemImage: "trash", role: .destructive) { vault.delete(document) }
                }
                .swipeActions {
                    Button(role: .destructive) {
                        vault.delete(document)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
    }

    private func askForTitle(_ data: Data, kind: VaultDocument.Kind) {
        newTitle = ""
        pendingData = (data, kind)
    }
}

#Preview {
    DocumentVaultView()
}
