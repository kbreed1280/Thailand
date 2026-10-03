import SwiftUI
import PhotosUI
import UniformTypeIdentifiers
import CoreData
import CoreLocation

/// Turns a booking confirmation (screenshot, photo, PDF or pasted text) into itinerary items.
/// Everything is read on this iPhone; nothing is saved until you review it.
struct SmartImportView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip

    private enum Stage { case pick, reading, review }

    @State private var stage: Stage = .pick
    @State private var pickerItem: PhotosPickerItem?
    @State private var showingPhotos = false
    @State private var showingFiles = false
    @State private var showingCamera = false
    @State private var pastedText = ""

    // Source
    @State private var sourceData: Data?
    @State private var sourceKind: DocumentKind = .note
    @State private var sourceExtension = ""
    @State private var extractedText = ""

    // Review
    @State private var title = ""
    @State private var category: ItemCategory = .place
    @State private var address = ""
    @State private var useAddress = true
    @State private var phone = ""
    @State private var dates: [EditableDate] = []
    @State private var amounts: [EditableAmount] = []
    @State private var attachSource = true
    @State private var isSaving = false

    struct EditableDate: Identifiable {
        let id = UUID()
        var date: Date
        var hasTime: Bool
        var include: Bool
    }

    struct EditableAmount: Identifiable {
        let id = UUID()
        var amount: DocumentInsights.Amount
        var include: Bool
    }

    var body: some View {
        NavigationStack {
            Group {
                switch stage {
                case .pick: pickView
                case .reading: ProgressView("Reading on this iPhone…").frame(maxWidth: .infinity, maxHeight: .infinity)
                case .review: reviewForm
                }
            }
            .background(Theme.background)
            .navigationTitle("Smart Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                if stage == .review {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save", action: save)
                            .bold()
                            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || isSaving)
                    }
                }
            }
            .photosPicker(isPresented: $showingPhotos, selection: $pickerItem, matching: .images)
            .onChange(of: pickerItem) { _, item in
                guard let item else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self) {
                        await read(data: data, kind: .image, ext: "jpg")
                    }
                    pickerItem = nil
                }
            }
            .fileImporter(isPresented: $showingFiles, allowedContentTypes: [.pdf, .image]) { result in
                guard case .success(let url) = result else { return }
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                guard let data = try? Data(contentsOf: url) else { return }
                let isPDF = UTType(filenameExtension: url.pathExtension)?.conforms(to: .pdf) ?? false
                Task { await read(data: data, kind: isPDF ? .pdf : .image, ext: url.pathExtension.lowercased()) }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    Task { await read(data: ImageProcessing.preparedForStorage(data), kind: .image, ext: "jpg") }
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Pick

    private var pickView: some View {
        ScrollView {
            VStack(spacing: 14) {
                Text("Import a flight, hotel, tour or restaurant booking. The app finds the dates, times, address, phone number and price for you to check.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.top)

                sourceButton("Screenshot or Photo", systemImage: "photo.on.rectangle", action: { showingPhotos = true })
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    sourceButton("Take a Photo of a Printout", systemImage: "camera", action: { showingCamera = true })
                }
                sourceButton("PDF from Files or Mail", systemImage: "doc.richtext", action: { showingFiles = true })

                VStack(alignment: .leading, spacing: 8) {
                    Label("Or paste the email text", systemImage: "doc.on.clipboard").font(.headline)
                    TextEditor(text: $pastedText)
                        .frame(minHeight: 120)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Theme.insetBackground, in: RoundedRectangle(cornerRadius: Theme.smallCornerRadius))
                    HStack {
                        Button("Paste") { pastedText = UIPasteboard.general.string ?? pastedText }
                            .buttonStyle(.bordered)
                        Spacer()
                        Button("Read Text") { Task { await read(text: pastedText) } }
                            .buttonStyle(.borderedProminent)
                            .tint(Theme.mango)
                            .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                }
                .card()

                privacyNote
            }
            .padding()
        }
    }

    private func sourceButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
                .padding(.horizontal, 16)
                .foregroundStyle(Theme.lagoon)
                .background(Theme.cardBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }

    private var privacyNote: some View {
        Label("Everything is read on this iPhone. Nothing is uploaded.", systemImage: "lock.shield.fill")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    // MARK: Review

    private var reviewForm: some View {
        Form {
            Section {
                privacyNote
            }

            Section("What") {
                TextField("Name", text: $title)
                Picker("Type", selection: $category) {
                    ForEach(ItemCategory.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
            }

            Section {
                if dates.isEmpty {
                    Text("No dates found — it will go on the Wish List.").foregroundStyle(.secondary)
                }
                ForEach($dates) { $entry in
                    VStack(alignment: .leading) {
                        Toggle(isOn: $entry.include) {
                            Text(dayLabel(for: entry.date))
                                .font(.subheadline.weight(.semibold))
                        }
                        DatePicker(
                            "When",
                            selection: $entry.date,
                            displayedComponents: entry.hasTime ? [.date, .hourAndMinute] : [.date]
                        )
                        .disabled(!entry.include)
                        Toggle("Has a time", isOn: $entry.hasTime)
                            .font(.caption)
                            .disabled(!entry.include)
                    }
                }
            } header: {
                Text("When (one item per selected date)")
            }

            Section("Where & contact") {
                TextField("Address", text: $address, axis: .vertical)
                if !address.isEmpty {
                    Toggle("Find it on the map", isOn: $useAddress)
                }
                TextField("Phone", text: $phone)
                    .keyboardType(.phonePad)
            }

            if !amounts.isEmpty {
                Section {
                    ForEach($amounts) { $entry in
                        Toggle(isOn: $entry.include) {
                            Text("Add \(CurrencyMath.format(entry.amount.value, entry.amount.currency)) as an expense")
                        }
                    }
                } header: {
                    Text("Amounts")
                } footer: {
                    Text("Expenses are paid by \(AppSettings.displayName) and split 50/50. You can edit them later.")
                }
            }

            Section {
                Toggle("Attach the original to Bookings", isOn: $attachSource)
                DisclosureGroup("Text found") {
                    Text(extractedText.isEmpty ? "No text found." : extractedText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private func dayLabel(for date: Date) -> String {
        if let day = trip.day(for: date) {
            return day.heading
        }
        return "\(date.formatted(date: .abbreviated, time: .omitted)) — outside trip, goes to Wish List"
    }

    // MARK: Reading

    private func read(data: Data, kind: DocumentKind, ext: String) async {
        stage = .reading
        sourceData = data
        sourceKind = kind
        sourceExtension = ext
        let text: String
        if kind == .pdf {
            text = await TextExtractor.text(fromPDF: data)
        } else if let image = UIImage(data: data) {
            text = await TextExtractor.text(from: image)
        } else {
            text = ""
        }
        prepareReview(text)
    }

    private func read(text: String) async {
        stage = .reading
        sourceData = nil
        sourceKind = .note
        sourceExtension = ""
        prepareReview(text)
    }

    private func prepareReview(_ text: String) {
        extractedText = text
        let insights = DocumentInsights.analyze(text)
        title = insights.title
        category = insights.category
        address = insights.addresses.first ?? ""
        phone = insights.phones.first ?? ""
        dates = insights.dates.prefix(6).map {
            EditableDate(date: $0.date, hasTime: $0.hasTime, include: trip.day(for: $0.date) != nil)
        }
        // Default: include only the first in-trip date (e.g. hotel check-in, not check-out).
        if let firstIncluded = dates.firstIndex(where: \.include) {
            for index in dates.indices where index != firstIncluded { dates[index].include = false }
        }
        amounts = insights.amounts.prefix(4).enumerated().map { EditableAmount(amount: $0.element, include: $0.offset == 0) }
        stage = .review
    }

    // MARK: Saving

    private func save() {
        isSaving = true
        Task {
            defer { isSaving = false }
            let store = ItineraryStore(context: context)
            let trimmedTitle = title.trimmingCharacters(in: .whitespaces)

            var coordinate: CLLocationCoordinate2D?
            if useAddress, !address.isEmpty {
                coordinate = await PlaceLookup.search(address).first?.coordinate
            }

            var notes: [String] = []
            if !phone.isEmpty { notes.append("Phone: \(phone)") }
            notes.append("Imported from a booking")

            let selected = dates.filter(\.include)
            let targets: [EditableDate?] = selected.isEmpty ? [nil] : selected
            for target in targets {
                let day = target.flatMap { trip.day(for: $0.date) }
                let item = store.addItem(
                    title: trimmedTitle,
                    category: category,
                    to: day,
                    in: trip,
                    address: address,
                    coordinate: coordinate,
                    notes: notes.joined(separator: "\n")
                )
                if let target, target.hasTime { item.time = target.date }
                item.status = .booked
            }

            for entry in amounts where entry.include {
                let expense = Expense(context: context)
                expense.placeInSameStore(as: trip)
                expense.uuid = UUID()
                expense.title = trimmedTitle
                expense.amountTHB = entry.amount.currency == .thb
                    ? entry.amount.value
                    : CurrencyMath.convert(entry.amount.value, from: .usd, thbPerUSD: ExchangeRateStore.shared.thbPerUSD)
                expense.paidBy = AppSettings.displayName
                expense.split = .equal
                expense.category = category == .hotel ? .lodging : (category == .transport ? .transport : .activities)
                expense.date = selected.first?.date ?? .now
                expense.addedBy = AppSettings.displayName
                expense.trip = trip
            }

            if attachSource {
                let document = TripDocument(context: context)
                document.placeInSameStore(as: trip)
                document.uuid = UUID()
                document.title = trimmedTitle
                document.kind = sourceData == nil ? .note : sourceKind
                document.fileData = sourceData
                document.fileExtension = sourceExtension
                document.text = extractedText
                document.addedBy = AppSettings.displayName
                document.createdAt = .now
                document.updatedAt = .now
                document.trip = trip
            }

            store.save()
            dismiss()
        }
    }
}
