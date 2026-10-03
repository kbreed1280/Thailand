import SwiftUI
import CoreData

/// Trip tab: picks the current trip and shows its itinerary (or the first-run screen).
struct TripTabView: View {
    @Environment(\.managedObjectContext) private var context
    @FetchRequest(sortDescriptors: [NSSortDescriptor(key: "createdAt", ascending: false)])
    private var trips: FetchedResults<Trip>

    @AppStorage(AppSettings.selectedTripKey) private var selectedTripID = ""
    @State private var showingNewTrip = false
    @State private var isJoiningShare = false

    private var currentTrip: Trip? {
        trips.first { $0.uuid?.uuidString == selectedTripID } ?? trips.first
    }

    var body: some View {
        NavigationStack {
            Group {
                if let trip = currentTrip {
                    TripItineraryView(trip: trip, allTrips: Array(trips), selectedTripID: $selectedTripID)
                        .id(trip.objectID)
                } else {
                    EmptyStateView(
                        systemImage: "sun.horizon.fill",
                        title: "Plan Your Thailand Trip",
                        message: "Create a trip with your travel dates. Every day gets its own plan, and the wish list holds places you haven't scheduled yet."
                    ) {
                        Button {
                            showingNewTrip = true
                        } label: {
                            Label("Plan a Trip", systemImage: "plus")
                        }
                        .buttonStyle(.primary)

                        Button {
                            let trip = SampleTrip.create(in: context)
                            selectedTripID = trip.uuid?.uuidString ?? ""
                        } label: {
                            Label("Try the Demo Trip", systemImage: "sparkles")
                        }
                        .buttonStyle(.secondary)
                    }
                    .background(Theme.background)
                    .navigationTitle("Trip")
                }
            }
            .navigationDestination(for: Item.self) { item in
                ItemDetailView(item: item)
            }
            .sheet(isPresented: $showingNewTrip) {
                TripFormView(trip: nil) { trip in
                    selectedTripID = trip.uuid?.uuidString ?? ""
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isJoiningShare {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("Joining the shared trip. This can take a minute.")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 8)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .didAcceptTripShare)) { _ in
                selectJoinedTripIfReady()
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange, object: context)) { _ in
                selectJoinedTripIfReady()
            }
            .onAppear { selectJoinedTripIfReady() }
        }
    }

    /// After accepting an invitation, switch to that trip as soon as it has synced down.
    private func selectJoinedTripIfReady() {
        guard let pending = UserDefaults.standard.string(forKey: TripSharing.pendingShareKey) else {
            isJoiningShare = false
            return
        }
        isJoiningShare = true
        let persistence = PersistenceController.shared
        for trip in trips where persistence.isSharedWithMe(trip) {
            if persistence.share(for: trip)?.recordID.recordName == pending {
                selectedTripID = trip.uuid?.uuidString ?? ""
                UserDefaults.standard.removeObject(forKey: TripSharing.pendingShareKey)
                isJoiningShare = false
                return
            }
        }
    }
}

#Preview {
    TripTabView()
        .environment(\.managedObjectContext, PersistenceController.preview.viewContext)
}
