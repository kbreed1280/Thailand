import SwiftUI
import PhotosUI
import QuickLook
import UniformTypeIdentifiers
import CoreData

/// Shared bookings for a trip (confirmations, tickets, links, notes) with Smart Import.
struct BookingsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip

    @State private var showingImporter = false
    @State private var showingFileImporter = false
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingPhotos = false
    @State private var showingLink = false
    @State private var showingNote = false
    @State private var linkText = ""
    @State private var noteTitle = ""
    @State private var noteText = ""
    @State private var previewURL: URL?
    @State private var refreshTick = 0
    @State private var savedMessage: String?

    var body: some View {
        let _ = refreshTick
        NavigationStack {
            List {
                Section {
                    Button {
                        showingImporter = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "wand.and.stars")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Theme.sunsetGradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Smart Import").font(.headline).foregroundStyle(.primary)
                                Text("Scan a confirmation screenshot, PDF or email text and turn it into plans.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Bookings") {
                    if trip.sortedDocuments.isEmpty {
                        Text("Flights, hotels, tours and tickets you add here are shared with everyone on the trip.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(trip.sortedDocuments) { document in
                        DocumentRow(document: document, trip: trip, onPreview: { open(document) }, onSaved: { savedMessage = $0 })
                    }
                    .onDelete { offsets in
                        let documents = trip.sortedDocuments
                        offsets.map { documents[$0] }.forEach { document in
                            document.trip = nil
                            context.delete(document)
                        }
                        save()
                    }
                }
            }
            .navigationTitle("Bookings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button("PDF or Image from Files", systemImage: "doc") { showingFileImporter = true }
                        Button("Photo or Screenshot", systemImage: "photo") { showingPhotos = true }
                        Button("Link", systemImage: "link") {
                            linkText = UIPasteboard.general.url?.absoluteString ?? ""
                            showingLink = true
                        }
                        Button("Note", systemImage: "note.text") { showingNote = true }
                    } label: {
                        Image(systemName: "plus.circle.fill").font(.title2)
                    }
                    .accessibilityLabel("Add booking")
                }
            }
            .fileImporter(isPresented: $showingFileImporter, allowedContentTypes: [.pdf, .image]) { result in
                guard case .success(let url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
                Task {
                    await addFile(data, kind: isPDF ? .pdf : .image, ext: url.pathExtension.lowercased(), title: url.deletingPathExtension().lastPathComponent)
                }
            }
            .photosPicker(isPresented: $showingPhotos, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await addFile(ImageProcessing.preparedForStorage(data), kind: .image, ext: "jpg", title: nil)
                    }
                    pickerItem = nil
                }
            }
            .alert("Add Link", isPresented: $showingLink) {
                TextField("https://…", text: $linkText)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                Button("Add") { addLink() }
                Button("Cancel", role: .cancel) {}
            }
            .alert("Add Note", isPresented: $showingNote) {
                TextField("Title", text: $noteTitle)
                TextField("Confirmation number, details…", text: $noteText)
                Button("Add") { addNote() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $showingImporter) {
                SmartImportView(trip: trip)
            }
            .quickLookPreview($previewURL)
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                refreshTick &+= 1
            }
            .savedToast($savedMessage)
        }
    }

    // MARK: Adding

    private func addFile(_ data: Data, kind: DocumentKind, ext: String, title: String?) async {
        let text: String
        if kind == .pdf {
            text = await TextExtractor.text(fromPDF: data)
        } else if let image = UIImage(data: data) {
            text = await TextExtractor.text(from: image)
        } else {
            text = ""
        }
        insert(
            title: title ?? DocumentInsights.suggestedTitle(from: text),
            kind: kind,
            data: data,
            ext: ext,
            url: nil,
            text: text
        )
    }

    private func addLink() {
        let trimmed = linkText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let url = trimmed.hasPrefix("http") ? trimmed : "https://\(trimmed)"
        insert(title: URL(string: url)?.host ?? "Link", kind: .link, data: nil, ext: nil, url: url, text: url)
        linkText = ""
    }

    private func addNote() {
        insert(title: noteTitle.isEmpty ? DocumentInsights.suggestedTitle(from: noteText) : noteTitle, kind: .note, data: nil, ext: nil, url: nil, text: noteText)
        noteTitle = ""
        noteText = ""
    }

    private func insert(title: String, kind: DocumentKind, data: Data?, ext: String?, url: String?, text: String) {
        let document = TripDocument(context: context)
        document.placeInSameStore(as: trip)
        document.uuid = UUID()
        document.title = title.isEmpty ? "Booking" : title
        document.kind = kind
        document.fileData = data
        document.fileExtension = ext ?? ""
        document.urlString = url ?? ""
        document.text = text
        document.addedBy = AppSettings.displayName
        document.createdAt = .now
        document.updatedAt = .now
        document.trip = trip
        save()
    }

    private func open(_ document: TripDocument) {
        if let url = document.url, document.kind == .link {
            UIApplication.shared.open(url)
        } else {
            previewURL = document.temporaryFileURL()
        }
    }

    private func save() {
        ItineraryStore(context: context).save()
        refreshTick &+= 1
    }
}

/// One booking with its detected insights as tappable chips.
struct DocumentRow: View {
    @Environment(\.managedObjectContext) private var context
    @ObservedObject var document: TripDocument
    @ObservedObject var trip: Trip
    let onPreview: () -> Void
    var onSaved: ((String) -> Void)? = nil

    private var insights: DocumentInsights { DocumentInsights.analyze(document.text ?? "") }

    var body: some View {
        let insights = insights
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onPreview) {
                HStack(spacing: 12) {
                    Image(systemName: document.kind.systemImage)
                        .font(.title3)
                        .foregroundStyle(Theme.lagoon)
                        .frame(width: 32)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(document.displayTitle).font(.headline).foregroundStyle(.primary).lineLimit(2)
                        Text([document.addedBy ?? "", document.createdAt?.formatted(date: .abbreviated, time: .omitted) ?? ""]
                            .filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if document.fileData != nil {
                        ShareLink(item: document.temporaryFileURL() ?? URL(fileURLWithPath: "/")) {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                    }
                }
            }
            .buttonStyle(.plain)

            if !insights.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(insights.dates.prefix(4), id: \.self) { detected in
                            Menu {
                                if let day = trip.day(for: detected.date) {
                                    Button("Add to \(day.heading)", systemImage: "calendar.badge.plus") {
                                        addItem(on: day, at: detected)
                                    }
                                } else {
                                    Button("Add to Wish List", systemImage: "star") { addItem(on: nil, at: detected) }
                                }
                            } label: {
                                chip(detected.hasTime
                                     ? detected.date.formatted(.dateTime.month(.abbreviated).day().hour().minute())
                                     : detected.date.formatted(.dateTime.month(.abbreviated).day()),
                                     systemImage: "calendar", tint: Theme.mango)
                            }
                        }
                        ForEach(insights.amounts.prefix(3), id: \.self) { amount in
                            Menu {
                                Button("Add as Expense", systemImage: "bahtsign.circle") { addExpense(amount) }
                            } label: {
                                chip(CurrencyMath.format(amount.value, amount.currency), systemImage: "banknote", tint: .green)
                            }
                        }
                        ForEach(insights.phones.prefix(2), id: \.self) { phone in
                            Button {
                                ExternalApps.call(phone)
                            } label: {
                                chip(phone, systemImage: "phone.fill", tint: .blue)
                            }
                        }
                        ForEach(insights.addresses.prefix(2), id: \.self) { address in
                            Button {
                                var components = URLComponents(string: "https://maps.apple.com/")
                                components?.queryItems = [URLQueryItem(name: "q", value: address)]
                                if let url = components?.url { UIApplication.shared.open(url) }
                            } label: {
                                chip(address, systemImage: "mappin", tint: Theme.coral)
                            }
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 4)
    }

    private func chip(_ text: String, systemImage: String, tint: Color) -> some View {
        Label(text, systemImage: systemImage)
            .font(.caption.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, 10)
            .frame(minHeight: 32)
            .foregroundStyle(tint)
            .background(tint.opacity(0.13), in: Capsule())
    }

    private func addItem(on day: Day?, at detected: DocumentInsights.DetectedDate) {
        let store = ItineraryStore(context: context)
        let insights = insights
        let item = store.addItem(
            title: document.displayTitle,
            category: insights.category,
            to: day,
            in: trip,
            address: insights.addresses.first ?? "",
            notes: "From booking: \(document.displayTitle)"
        )
        if detected.hasTime { item.time = detected.date }
        item.link = document.urlString ?? ""
        store.save()
        onSaved?("Added to \(day?.heading ?? "Wish List")")
    }

    private func addExpense(_ amount: DocumentInsights.Amount) {
        let expense = Expense(context: context)
        expense.placeInSameStore(as: trip)
        expense.uuid = UUID()
        expense.title = document.displayTitle
        expense.amountTHB = amount.currency == .thb
            ? amount.value
            : CurrencyMath.convert(amount.value, from: .usd, thbPerUSD: ExchangeRateStore.shared.thbPerUSD)
        expense.paidBy = AppSettings.displayName
        expense.split = .equal
        expense.category = { () -> ExpenseCategory in
            switch insights.category {
            case .hotel: .lodging
            case .transport: .transport
            case .meal: .food
            case .activity: .activities
            case .place: .other
            }
        }()
        expense.date = .now
        expense.addedBy = AppSettings.displayName
        expense.trip = trip
        ItineraryStore(context: context).save()
        onSaved?("Expense added")
    }
}
