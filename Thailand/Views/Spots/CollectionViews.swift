import CoreData
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Lists tab: collections (trip / city / theme) + tip-video folders

struct SpotListsTab: View {
    @ObservedObject var trip: Trip
    let refreshTick: Int
    let folders: [String]
    let sources: [SpotSource]
    @Environment(\.managedObjectContext) private var context
    @State private var creating = false

    private var collections: [SpotCollection] { _ = refreshTick; return trip.sortedCollections }

    var body: some View {
        List {
            Section {
                ForEach(collections) { c in
                    NavigationLink { CollectionDetailView(collection: c) } label: { CollectionRow(collection: c) }
                }
                .onDelete { offsets in
                    offsets.map { collections[$0] }.forEach(context.delete)
                    ItineraryStore(context: context).save()
                }
                .onMove { source, destination in
                    var list = collections
                    list.move(fromOffsets: source, toOffset: destination)
                    for (i, c) in list.enumerated() { c.sortIndex = Int64(i) }
                    ItineraryStore(context: context).save()
                }
                Button("New list", systemImage: "plus") { creating = true }
            } header: {
                Text("Lists")
            } footer: {
                Text("Group spots by trip, city or theme (\"Best khao soi\", \"Rooftop bars\"). Share a list with anyone as a WanderHub file.")
            }

            ForEach(folders, id: \.self) { folder in
                let inFolder = sources.filter { $0.folder == folder }
                Section("📁 \(folder) · \(inFolder.count)") {
                    if inFolder.isEmpty {
                        Text("Empty. Drafts with no specific place can be filed here.").font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(inFolder) { source in SourceHeader(source: source) }
                }
            }
        }
        .sheet(isPresented: $creating) { CollectionEditor(trip: trip, collection: nil) }
    }
}

struct CollectionRow: View {
    @ObservedObject var collection: SpotCollection

    var body: some View {
        HStack(spacing: 12) {
            Text(collection.emoji ?? "📍")
                .font(.title2)
                .frame(width: 44, height: 44)
                .background(Theme.mango.opacity(0.15), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(collection.displayName).font(.body.weight(.semibold))
                Text("\(collection.kind.title) · \(collection.spots.count) spot\(collection.spots.count == 1 ? "" : "s")")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Create / edit a list

struct CollectionEditor: View {
    let trip: Trip
    let collection: SpotCollection?
    var onCreate: ((SpotCollection) -> Void)?
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var emoji = "📍"
    @State private var kind: CollectionKind = .theme
    @State private var notes = ""

    private static let emojis = ["📍", "🍜", "☕️", "🍸", "🌃", "🛕", "🏝️", "🛍️", "💆", "🌶️", "🥭", "🐘", "🎒", "⭐️", "❤️", "📸"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name (e.g. Best khao soi)", text: $name).font(.title3)
                    Picker("Type", selection: $kind) {
                        ForEach(CollectionKind.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                }
                Section("Icon") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 8), spacing: 10) {
                        ForEach(Self.emojis, id: \.self) { e in
                            Text(e).font(.title2)
                                .frame(width: 36, height: 36)
                                .background(e == emoji ? Theme.mango.opacity(0.3) : .clear, in: Circle())
                                .onTapGesture { emoji = e }
                        }
                    }
                }
                Section("Notes") {
                    TextField("What's this list for?", text: $notes, axis: .vertical).lineLimit(2...5)
                }
            }
            .navigationTitle(collection == nil ? "New List" : "Edit List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(collection == nil ? "Create" : "Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                guard let collection else { return }
                name = collection.name ?? ""
                emoji = collection.emoji ?? "📍"
                kind = collection.kind
                notes = collection.notes ?? ""
            }
        }
        .presentationDetents([.large])
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let c = collection ?? CollectionStore.create(name: trimmed, emoji: emoji, kind: kind, in: trip, context: context)
        c.name = trimmed
        c.emoji = emoji
        c.kind = kind
        c.notes = notes
        c.updatedAt = .now
        ItineraryStore(context: context).save()
        if collection == nil { onCreate?(c) }
        dismiss()
    }
}

// MARK: - A list: reorder, per-spot notes, share

struct CollectionDetailView: View {
    @ObservedObject var collection: SpotCollection
    @Environment(\.managedObjectContext) private var context
    @State private var editing = false
    @State private var refreshTick = 0

    private var entries: [CollectionEntry] { _ = refreshTick; return collection.sortedEntries }

    var body: some View {
        List {
            if let notes = collection.notes, !notes.isEmpty {
                Section { Text(notes).font(.callout).foregroundStyle(.secondary) }
            }
            Section {
                ForEach(entries) { entry in
                    if let spot = entry.spot {
                        VStack(alignment: .leading, spacing: 6) {
                            NavigationLink { SpotDetailView(spot: spot) } label: { SpotRow(spot: spot) }
                            EntryNoteField(entry: entry)
                        }
                    }
                }
                .onMove { CollectionStore.move(in: collection, from: $0, to: $1); save() }
                .onDelete { offsets in
                    offsets.map { entries[$0] }.forEach(context.delete)
                    save()
                }
            } footer: {
                if !entries.isEmpty { Text("Add your own note to each spot. Notes are included when you share the list.") }
            }
        }
        .overlay {
            if entries.isEmpty {
                ContentUnavailableView("Empty list", systemImage: "list.star",
                                       description: Text("Open any saved spot and tap Add to List."))
            }
        }
        .navigationTitle("\(collection.emoji ?? "") \(collection.displayName)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if !entries.isEmpty {
                    ShareLink(item: SharedCollection(collection, sharedBy: AppSettings.displayName),
                              preview: SharePreview("\(collection.displayName): \(entries.count) spots on WanderHub")) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                Button("Edit", systemImage: "pencil") { editing = true }
                EditButton()
            }
        }
        .sheet(isPresented: $editing) {
            if let trip = collection.trip { CollectionEditor(trip: trip, collection: collection) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
            refreshTick &+= 1
        }
    }

    private func save() { ItineraryStore(context: context).save() }
}

private struct EntryNoteField: View {
    @ObservedObject var entry: CollectionEntry
    @Environment(\.managedObjectContext) private var context
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("Add a note (what to order, when to go…)", text: $text, axis: .vertical)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1...4)
            .focused($focused)
            .onAppear { text = entry.note ?? "" }
            .onChange(of: focused) { _, isFocused in
                guard !isFocused, text != (entry.note ?? "") else { return }
                entry.note = text
                entry.collection?.updatedAt = .now
                ItineraryStore(context: context).save()
            }
    }
}

// MARK: - "Add to List" (spot detail)

struct AddToCollectionMenu: View {
    @ObservedObject var spot: Spot
    @Environment(\.managedObjectContext) private var context
    @State private var creating = false

    var body: some View {
        Menu {
            if let trip = spot.trip {
                ForEach(trip.sortedCollections) { c in
                    let inList = c.contains(spot)
                    Button {
                        if inList { CollectionStore.remove(spot, from: c, context: context) }
                        else { CollectionStore.add(spot, to: c, context: context) }
                        ItineraryStore(context: context).save()
                    } label: {
                        if inList { Label("\(c.emoji ?? "") \(c.displayName)", systemImage: "checkmark") }
                        else { Text("\(c.emoji ?? "") \(c.displayName)") }
                    }
                }
            }
            Divider()
            Button("New list…", systemImage: "plus") { creating = true }
        } label: {
            let count = spot.collections.count
            Label(count == 0 ? "Add to List" : "In \(count) list\(count == 1 ? "" : "s")", systemImage: "list.star")
        }
        .sheet(isPresented: $creating) {
            if let trip = spot.trip {
                CollectionEditor(trip: trip, collection: nil) { c in
                    CollectionStore.add(spot, to: c, context: context)
                    ItineraryStore(context: context).save()
                }
            }
        }
    }
}

// MARK: - Opening a shared .wanderhub file

struct IncomingCollection: Identifiable {
    let id = UUID()
    let collection: SharedCollection

    /// Reads a .wanderhub file opened from Messages, Mail, AirDrop or Files.
    static func load(from url: URL) -> IncomingCollection? {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url), let shared = try? SharedCollection.decode(data) else { return nil }
        return IncomingCollection(collection: shared)
    }
}

struct SharedCollectionImportView: View {
    let shared: SharedCollection
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)]) private var trips: FetchedResults<Trip>
    @AppStorage(AppSettings.selectedTripKey) private var selectedTripID = ""
    @State private var tripID: NSManagedObjectID?
    @State private var saved: Set<UUID> = []

    private var trip: Trip? {
        trips.first { $0.objectID == tripID } ?? trips.first { $0.uuid?.uuidString == selectedTripID } ?? trips.first
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(shared.emoji) \(shared.name)").font(.title2.weight(.bold))
                        Text("Shared by \(shared.sharedBy) · \(shared.spots.count) spots").font(.caption).foregroundStyle(.secondary)
                        if !shared.notes.isEmpty { Text(shared.notes).font(.callout).padding(.top, 4) }
                    }
                    if trips.count > 1 {
                        Picker("Save to trip", selection: Binding(get: { trip?.objectID }, set: { tripID = $0 })) {
                            ForEach(trips) { Text($0.name ?? "Trip").tag(Optional($0.objectID)) }
                        }
                    }
                }
                Section {
                    ForEach(shared.spots) { s in
                        HStack(alignment: .top, spacing: 12) {
                            let category = SpotCategory(rawValue: s.category) ?? .explore
                            Image(systemName: category.systemImage)
                                .foregroundStyle(.white)
                                .frame(width: 30, height: 30)
                                .background(category.color, in: Circle())
                            VStack(alignment: .leading, spacing: 2) {
                                Text(s.name).font(.body.weight(.semibold))
                                Text([s.city, s.address].filter { !$0.isEmpty }.first ?? "").font(.caption).foregroundStyle(.secondary)
                                if !s.note.isEmpty { Text("“\(s.note)”").font(.caption).italic() }
                                if let tip = s.tips.first(where: { !$0.whatToOrder.isEmpty }) {
                                    Text("Order: \(tip.whatToOrder)").font(.caption2).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            if saved.contains(s.id) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.title3)
                            } else {
                                Button { save(s) } label: { Image(systemName: "plus.circle").font(.title3) }
                                    .buttonStyle(.borderless)
                                    .disabled(trip == nil)
                            }
                        }
                    }
                } footer: {
                    Text("Spots you already have are merged, not duplicated.")
                }
            }
            .navigationTitle("Shared List")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save all") { saveAll() }.disabled(trip == nil || saved.count == shared.spots.count)
                }
            }
            .overlay {
                if trips.isEmpty {
                    ContentUnavailableView("No trip yet", systemImage: "suitcase",
                                           description: Text("Create a trip first, then open this list again."))
                }
            }
        }
    }

    private func save(_ s: SharedCollection.SharedSpot) {
        guard let trip else { return }
        CollectionImporter.save(s, into: nil, trip: trip, context: context)
        ItineraryStore(context: context).save()
        saved.insert(s.id)
    }

    private func saveAll() {
        guard let trip else { return }
        CollectionImporter.saveAll(shared, trip: trip, context: context)
        ItineraryStore(context: context).save()
        dismiss()
    }
}
