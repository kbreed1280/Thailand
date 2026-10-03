import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import VisionKit
import CoreData

/// Face ID–locked travel documents (passport, visa, insurance, flights, hotels).
/// Kept only on this iPhone; any single document can be copied to the shared Bookings.
struct DocumentVaultView: View {
    var trip: Trip?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.managedObjectContext) private var context
    @StateObject private var vault = DocumentVault.shared

    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var pickerPresented = false
    @State private var showingCamera = false
    @State private var showingScanner = false
    @State private var showingFileImporter = false
    @State private var previewURL: URL?
    @State private var pending: [PendingDocument] = []
    @State private var editing: VaultDocument?
    @State private var search = ""
    @State private var sharedMessage: String?

    struct PendingDocument: Identifiable {
        let id = UUID()
        var data: Data
        var kind: VaultDocument.Kind
        var suggestedTitle: String
        var pageCount: Int?
    }

    var body: some View {
        NavigationStack {
            Group {
                if vault.isUnlocked {
                    unlockedList
                } else {
                    lockedState
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
                    ToolbarItem(placement: .primaryAction) { addMenu }
                }
            }
            .photosPicker(isPresented: $pickerPresented, selection: $pickerItems, maxSelectionCount: 10, matching: .images)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                Task {
                    for item in items {
                        if let data = try? await item.loadTransferable(type: Data.self) {
                            pending.append(PendingDocument(data: data, kind: .image, suggestedTitle: ""))
                        }
                    }
                    pickerItems = []
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in pending.append(PendingDocument(data: data, kind: .image, suggestedTitle: "")) }
                    .ignoresSafeArea()
            }
            .fullScreenCover(isPresented: $showingScanner) {
                DocumentScanner { pdf, pages in
                    pending.append(PendingDocument(data: pdf, kind: .pdf, suggestedTitle: "", pageCount: pages))
                }
                .ignoresSafeArea()
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image], allowsMultipleSelection: true) { result in
                guard case .success(let urls) = result else { return }
                for url in urls {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
                    pending.append(PendingDocument(data: data, kind: isPDF ? .pdf : .image, suggestedTitle: url.deletingPathExtension().lastPathComponent))
                }
            }
            .sheet(item: Binding(get: { pending.first }, set: { if $0 == nil, !pending.isEmpty { pending.removeFirst() } })) { item in
                DocumentDetailsForm(
                    title: item.suggestedTitle,
                    category: .other,
                    expiresAt: nil,
                    heading: pending.count > 1 ? "New Document (\(pending.count) to go)" : "New Document"
                ) { title, category, expiry in
                    vault.add(data: item.data, title: title, kind: item.kind, category: category, expiresAt: expiry, pageCount: item.pageCount)
                }
            }
            .sheet(item: $editing) { document in
                DocumentDetailsForm(title: document.title, category: document.resolvedCategory, expiresAt: document.expiresAt, heading: "Edit Document") { title, category, expiry in
                    var updated = document
                    updated.title = title
                    updated.category = category
                    updated.expiresAt = expiry
                    vault.update(updated)
                }
            }
            .quickLookPreview($previewURL)
            .alert("Copied to Bookings", isPresented: Binding(get: { sharedMessage != nil }, set: { if !$0 { sharedMessage = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(sharedMessage ?? "")
            }
            .onChange(of: scenePhase) { _, phase in
                // Lock again as soon as the app leaves the screen.
                if phase != .active { vault.lock() }
            }
        }
    }

    // MARK: Locked

    private var lockedState: some View {
        EmptyStateView(
            systemImage: "lock.doc.fill",
            title: "Travel Documents",
            message: "Passport, visa, insurance, flight and hotel confirmations. Stored only on this iPhone, encrypted, opened with Face ID, and available offline."
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
            let alerts = vault.expiryAlerts(tripStart: trip?.startDate)
            if !alerts.isEmpty {
                Label("\(alerts.count) document\(alerts.count == 1 ? "" : "s") need attention", systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.coral)
            }
        }
        .task { if !vault.isUnlocked { await vault.unlock() } }
    }

    private var addMenu: some View {
        Menu {
            if VNDocumentCameraViewController.isSupported {
                Button("Scan Document", systemImage: "doc.viewfinder") { showingScanner = true }
            }
            if UIImagePickerController.isSourceTypeAvailable(.camera) {
                Button("Take Photo", systemImage: "camera") { showingCamera = true }
            }
            Button("Choose Photos", systemImage: "photo.on.rectangle") { pickerPresented = true }
            Button("Import Files (PDF or image)", systemImage: "folder") { showingFileImporter = true }
        } label: {
            Image(systemName: "plus.circle.fill").font(.title2)
        }
        .accessibilityLabel("Add document")
    }

    // MARK: Unlocked

    private var filtered: [VaultDocument] {
        vault.documents.filter { search.isEmpty || $0.title.localizedCaseInsensitiveContains(search) || $0.resolvedCategory.title.localizedCaseInsensitiveContains(search) }
    }

    private var unlockedList: some View {
        List {
            let alerts = vault.expiryAlerts(tripStart: trip?.startDate)
            if !alerts.isEmpty {
                Section {
                    ForEach(alerts, id: \.0.id) { document, warning in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(document.title).font(.subheadline.weight(.semibold))
                                Text(Self.warningText(warning)).font(.caption)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.coral)
                        }
                    }
                }
            }

            if vault.documents.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Add what you'd need at a border, hotel desk or hospital, so it's here even with no signal:")
                        Text("• Passport photo page and visa\n• Travel insurance policy and emergency number\n• Flight and hotel confirmations\n• Driving licence / International Driving Permit")
                            .foregroundStyle(.secondary)
                        Text("Tap ＋ → Scan Document for a clean, multi-page PDF.")
                            .font(.footnote.weight(.semibold))
                    }
                    .font(.subheadline)
                    .padding(.vertical, 4)
                }
            }

            ForEach(VaultDocument.Category.allCases) { category in
                let docs = filtered.filter { $0.resolvedCategory == category }
                if !docs.isEmpty {
                    Section {
                        ForEach(docs) { row($0) }
                    } header: {
                        Label(category.title, systemImage: category.systemImage)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search documents")
    }

    private func row(_ document: VaultDocument) -> some View {
        Button {
            previewURL = vault.url(for: document)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: document.resolvedCategory.systemImage)
                    .font(.title3)
                    .foregroundStyle(Theme.lagoon)
                    .frame(width: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(document.title).font(.headline).foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(document.kind == .pdf ? "PDF\(document.pageCount.map { " · \($0) page\($0 == 1 ? "" : "s")" } ?? "")" : "Photo")
                        if let expires = document.expiresAt {
                            Text("· Expires \(expires.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(document.expiryWarning(tripStart: trip?.startDate) == nil ? .secondary : Theme.coral)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
        }
        .contextMenu {
            Button("Edit Details", systemImage: "pencil") { editing = document }
            if trip != nil {
                Button("Copy to Shared Bookings", systemImage: "person.2.fill") { copyToBookings(document) }
            }
            Button("Delete", systemImage: "trash", role: .destructive) { vault.delete(document) }
        }
        .swipeActions {
            Button(role: .destructive) { vault.delete(document) } label: { Label("Delete", systemImage: "trash") }
            Button { editing = document } label: { Label("Edit", systemImage: "pencil") }.tint(Theme.lagoon)
        }
    }

    static func warningText(_ warning: VaultDocument.ExpiryWarning) -> String {
        switch warning {
        case .expired: "Expired"
        case .passportUnderSixMonths(let date): "Expires \(date.formatted(date: .abbreviated, time: .omitted)). Thailand requires 6 months' validity on arrival."
        case .soon(let date): "Expires soon (\(date.formatted(date: .abbreviated, time: .omitted)))"
        }
    }

    /// Puts a copy in the trip's Bookings, which syncs to your travel partner.
    private func copyToBookings(_ document: VaultDocument) {
        guard let trip, let data = vault.data(for: document) else { return }
        let copy = TripDocument(context: context)
        copy.placeInSameStore(as: trip)
        copy.uuid = UUID()
        copy.title = document.title
        copy.kind = document.kind == .pdf ? .pdf : .image
        copy.fileData = data
        copy.fileExtension = document.kind == .pdf ? "pdf" : "jpg"
        copy.urlString = ""
        copy.text = ""
        copy.addedBy = AppSettings.displayName
        copy.createdAt = .now
        copy.updatedAt = .now
        copy.trip = trip
        try? context.save()
        sharedMessage = "“\(document.title)” is now in Bookings, so everyone on the trip can see it. The original stays in your locked vault."
    }
}

// MARK: - Title / category / expiry form

private struct DocumentDetailsForm: View {
    @Environment(\.dismiss) private var dismiss
    @State var title: String
    @State var category: VaultDocument.Category
    @State var expiresAt: Date?
    let heading: String
    var onSave: (String, VaultDocument.Category, Date?) -> Void

    @State private var hasExpiry = false
    @State private var expiryDraft = Calendar.current.date(byAdding: .year, value: 1, to: .now) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Title, e.g. Passport – Alex", text: $title)
                    Picker("Type", selection: $category) {
                        ForEach(VaultDocument.Category.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                    }
                }
                Section {
                    Toggle("Has an expiry date", isOn: $hasExpiry)
                    if hasExpiry {
                        DatePicker("Expires", selection: $expiryDraft, displayedComponents: .date)
                    }
                } footer: {
                    if category == .passport {
                        Text("Thailand requires your passport to be valid for at least 6 months after you arrive. The app warns you if it isn't.")
                    }
                }
            }
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(title.isEmpty ? category.title : title, category, hasExpiry ? expiryDraft : nil)
                        dismiss()
                    }
                }
            }
            .onAppear {
                if let expiresAt {
                    hasExpiry = true
                    expiryDraft = expiresAt
                }
            }
            .onChange(of: category) { _, new in
                if expiresAt == nil { hasExpiry = new.hasExpiry }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Document scanner (VisionKit) → PDF

struct DocumentScanner: UIViewControllerRepresentable {
    var onScan: (Data, Int) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let controller = VNDocumentCameraViewController()
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let parent: DocumentScanner
        init(_ parent: DocumentScanner) { self.parent = parent }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            let pages = (0..<scan.pageCount).map { scan.imageOfPage(at: $0) }
            if let pdf = Self.pdf(from: pages) { parent.onScan(pdf, pages.count) }
            parent.dismiss()
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) { parent.dismiss() }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) { parent.dismiss() }

        /// One page per scanned image, scaled to A4 width.
        static func pdf(from images: [UIImage]) -> Data? {
            guard !images.isEmpty else { return nil }
            let width: CGFloat = 595
            let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: width, height: 842))
            return renderer.pdfData { context in
                for image in images {
                    let height = width * image.size.height / max(image.size.width, 1)
                    let bounds = CGRect(x: 0, y: 0, width: width, height: height)
                    context.beginPage(withBounds: bounds, pageInfo: [:])
                    image.draw(in: bounds)
                }
            }
        }
    }
}
