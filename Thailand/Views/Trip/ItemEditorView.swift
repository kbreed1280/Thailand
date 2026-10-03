import SwiftUI
import PhotosUI
import CoreData
import CoreLocation

/// Add (`item == nil`) or edit a place/activity/meal/hotel/transport item.
struct ItemEditorView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss

    let item: Item?
    @ObservedObject var trip: Trip
    let initialDay: Day?

    @State private var title = ""
    @State private var category: ItemCategory = .place
    @State private var status: ItemStatus = .wantToGo
    @State private var dayID: NSManagedObjectID?
    @State private var hasTime = false
    @State private var time = Calendar.current.date(bySettingHour: 10, minute: 0, second: 0, of: .now) ?? .now
    @State private var address = ""
    @State private var coordinate: CLLocationCoordinate2D?
    @State private var link = ""
    @State private var cost: Double?
    @State private var notes = ""
    @State private var durationMinutes = 60
    @State private var travelMode: TravelMode = .walking

    @State private var existingPhotos: [ItemPhoto] = []
    @State private var removedPhotoIDs: Set<NSManagedObjectID> = []
    @State private var newPhotos: [Data] = []
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var showingCamera = false
    @State private var showingPlaceSearch = false
    @State private var isLocating = false
    @State private var didLoad = false

    private var store: ItineraryStore { ItineraryStore(context: context) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Wat Pho)", text: $title)
                        .font(.headline)
                    Picker("Type", selection: $category) {
                        ForEach(ItemCategory.allCases) { option in
                            Label(option.title, systemImage: option.systemImage).tag(option)
                        }
                    }
                    Picker("Status", selection: $status) {
                        ForEach(ItemStatus.allCases) { option in
                            Text(option.title).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Section("When") {
                    Picker("Day", selection: $dayID) {
                        Label("Wish List (not scheduled)", systemImage: "star").tag(NSManagedObjectID?.none)
                        ForEach(trip.sortedDays) { day in
                            Text(day.heading).tag(Optional(day.objectID))
                        }
                    }
                    Toggle("Set a time", isOn: $hasTime.animation())
                    if hasTime {
                        DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    }
                    Picker("How long", selection: $durationMinutes) {
                        ForEach([15, 30, 45, 60, 90, 120, 180, 240, 360], id: \.self) { minutes in
                            Text(ScheduleMath.durationText(seconds: TimeInterval(minutes * 60))).tag(minutes)
                        }
                    }
                    Picker("Getting there", selection: $travelMode) {
                        ForEach(TravelMode.allCases) { mode in
                            Label(mode.title, systemImage: mode.systemImage).tag(mode)
                        }
                    }
                }

                Section {
                    Button {
                        showingPlaceSearch = true
                    } label: {
                        Label("Search Apple Maps", systemImage: "magnifyingglass")
                    }
                    Button(action: useCurrentLocation) {
                        HStack {
                            Label("Use My Location", systemImage: "location.fill")
                            Spacer()
                            if isLocating { ProgressView() }
                        }
                    }
                    TextField("Address", text: $address, axis: .vertical)
                        .lineLimit(1...3)
                    if let coordinate {
                        HStack {
                            Label(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude), systemImage: "mappin")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Clear", role: .destructive) { self.coordinate = nil }
                                .font(.caption)
                        }
                    }
                } header: {
                    Text("Where")
                } footer: {
                    Text("A pinned location puts the place on the day map and enables walking directions.")
                }

                Section("Details") {
                    HStack {
                        Text("฿")
                            .foregroundStyle(.secondary)
                        TextField("Cost in baht (optional)", value: $cost, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    TextField("Link (booking, website, menu…)", text: $link)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Notes", text: $notes, axis: .vertical)
                        .lineLimit(3...8)
                }

                Section("Photos") {
                    photoStrip
                    PhotosPicker(selection: $pickerItems, maxSelectionCount: 10, matching: .images) {
                        Label("Add from Library", systemImage: "photo.on.rectangle")
                    }
                    if UIImagePickerController.isSourceTypeAvailable(.camera) {
                        Button {
                            showingCamera = true
                        } label: {
                            Label("Take Photo", systemImage: "camera")
                        }
                    }
                }
            }
            .navigationTitle(item == nil ? "Add to Trip" : "Edit")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .bold()
                        .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
            .onChange(of: pickerItems) { _, items in
                guard !items.isEmpty else { return }
                pickerItems = []
                Task { await loadPicked(items) }
            }
            .sheet(isPresented: $showingPlaceSearch) {
                PlaceSearchSheet { result in
                    if title.trimmingCharacters(in: .whitespaces).isEmpty { title = result.name }
                    address = result.address
                    coordinate = result.coordinate
                    if link.isEmpty, let url = result.url { link = url.absoluteString }
                }
            }
            .fullScreenCover(isPresented: $showingCamera) {
                CameraPicker { data in
                    newPhotos.append(ImageProcessing.preparedForStorage(data))
                }
                .ignoresSafeArea()
            }
        }
    }

    // MARK: Photos

    @ViewBuilder
    private var photoStrip: some View {
        let visible = existingPhotos.filter { !removedPhotoIDs.contains($0.objectID) }
        if visible.isEmpty && newPhotos.isEmpty {
            Text("No photos yet")
                .foregroundStyle(.secondary)
        } else {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(visible) { photo in
                        thumbnail(photo.thumbnail) { removedPhotoIDs.insert(photo.objectID) }
                    }
                    ForEach(Array(newPhotos.enumerated()), id: \.offset) { index, data in
                        thumbnail(UIImage(data: data)) { newPhotos.remove(at: index) }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func thumbnail(_ image: UIImage?, onRemove: @escaping () -> Void) -> some View {
        ZStack(alignment: .topTrailing) {
            Group {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Color.gray.opacity(0.2)
                }
            }
            .frame(width: 76, height: 76)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .black.opacity(0.6))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .offset(x: 6, y: -6)
            .accessibilityLabel("Remove photo")
        }
    }

    private func loadPicked(_ items: [PhotosPickerItem]) async {
        for picked in items {
            if let data = try? await picked.loadTransferable(type: Data.self) {
                newPhotos.append(ImageProcessing.preparedForStorage(data))
            }
        }
    }

    // MARK: Location

    private func useCurrentLocation() {
        isLocating = true
        Task {
            defer { isLocating = false }
            guard let location = await LocationService.shared.currentLocation() else { return }
            coordinate = location.coordinate
            if address.isEmpty {
                address = "Pinned at my location"
            }
        }
    }

    // MARK: Load / save

    private func load() {
        guard !didLoad else { return }
        didLoad = true
        dayID = initialDay?.objectID
        guard let item else { return }
        title = item.title ?? ""
        category = item.category
        status = item.status
        if let itemTime = item.time {
            hasTime = true
            time = itemTime
        }
        address = item.address ?? ""
        coordinate = item.coordinate
        link = item.link ?? ""
        cost = item.costTHB > 0 ? item.costTHB : nil
        notes = item.notes ?? ""
        durationMinutes = Int(item.durationMinutes > 0 ? item.durationMinutes : 60)
        travelMode = item.travelMode
        existingPhotos = item.sortedPhotos
    }

    private func save() {
        let day = trip.sortedDays.first { $0.objectID == dayID }
        let target: Item
        if let item {
            target = item
            if item.day != day || (day == nil && item.wishTrip == nil) {
                store.move(item, toDay: day, in: trip, before: nil)
            }
        } else {
            target = store.addItem(title: title, category: category, to: day, in: trip)
        }

        target.title = title.trimmingCharacters(in: .whitespaces)
        target.category = category
        target.status = status
        target.address = address.trimmingCharacters(in: .whitespacesAndNewlines)
        target.coordinate = coordinate
        target.link = link.trimmingCharacters(in: .whitespaces)
        target.costTHB = max(cost ?? 0, 0)
        target.notes = notes
        target.durationMinutes = Int64(durationMinutes)
        target.travelMode = travelMode
        target.time = hasTime ? combined(time, onto: day?.date) : nil

        for photo in existingPhotos where removedPhotoIDs.contains(photo.objectID) {
            context.delete(photo)
        }
        for data in newPhotos {
            let photo = ItemPhoto(context: context)
            photo.placeInSameStore(as: trip)
            photo.uuid = UUID()
            photo.imageData = data
            photo.thumbnailData = ImageProcessing.thumbnail(from: data)
            photo.createdAt = .now
            photo.item = target
        }

        target.markEdited()
        store.save()
        dismiss()
    }

    /// Keeps the chosen hour/minute but moves it onto the day's date.
    private func combined(_ time: Date, onto day: Date?) -> Date {
        guard let day else { return time }
        let calendar = Calendar.current
        let parts = calendar.dateComponents([.hour, .minute], from: time)
        return calendar.date(bySettingHour: parts.hour ?? 0, minute: parts.minute ?? 0, second: 0, of: day) ?? time
    }
}

/// Search Apple Maps and pick a result.
struct PlaceSearchSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onPick: (PlaceResult) -> Void

    @State private var query = ""
    @State private var results: [PlaceResult] = []
    @State private var isSearching = false

    var body: some View {
        NavigationStack {
            List(results) { result in
                Button {
                    onPick(result)
                    dismiss()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.name).font(.headline).foregroundStyle(.primary)
                        if !result.address.isEmpty {
                            Text(result.address).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .overlay {
                if isSearching {
                    ProgressView()
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "Search for a Place",
                        systemImage: "magnifyingglass",
                        description: Text("Try a name like \"Wat Arun\", a street, or \"coffee near Nimman\".")
                    )
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Temple, restaurant, address…")
            .onSubmit(of: .search) { Task { await search() } }
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(450))
                guard !Task.isCancelled else { return }
                await search()
            }
            .navigationTitle("Find a Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func search() async {
        guard query.count >= 2 else {
            results = []
            return
        }
        isSearching = true
        results = await PlaceLookup.search(query)
        isSearching = false
    }
}

/// Wraps `UIImagePickerController` for taking a single photo.
struct CameraPicker: UIViewControllerRepresentable {
    @Environment(\.dismiss) private var dismiss
    let onCapture: (Data) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.85) {
                parent.onCapture(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
