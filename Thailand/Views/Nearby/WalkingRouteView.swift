import SwiftUI
import MapKit

/// In-app walking directions tracker: route on the map, the next turn, remaining distance and
/// arrival time, updated as you walk. One tap hands the same walk to Google Maps or Apple Maps.
struct WalkingRouteView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var location = LocationService.shared
    @StateObject private var navigator: WalkingNavigator
    @State private var position: MapCameraPosition = .userLocation(followsHeading: true, fallback: .automatic)
    @State private var showingSteps = false
    @State private var keepAwake = true

    init(destinationName: String, coordinate: CLLocationCoordinate2D) {
        _navigator = StateObject(wrappedValue: WalkingNavigator(destination: coordinate, destinationName: destinationName))
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Map(position: $position) {
                    MapPolyline(coordinates: navigator.routeCoordinates)
                        .stroke(Theme.lagoon, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    Marker(navigator.destinationName, systemImage: "flag.checkered", coordinate: navigator.destination)
                        .tint(Theme.mango)
                    UserAnnotation()
                }
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                }

                instructionBanner
                    .padding()
            }
            .safeAreaInset(edge: .bottom) { bottomPanel }
            .navigationTitle("Walk to \(navigator.destinationName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("End") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingSteps = true
                    } label: {
                        Label("Steps", systemImage: "list.bullet")
                    }
                    .disabled(navigator.steps.isEmpty)
                }
            }
            .sheet(isPresented: $showingSteps) { stepsList }
            .task {
                location.startUpdating(withHeading: true)
                if let current = await location.currentLocation() {
                    await navigator.calculate(from: current)
                }
            }
            .onChange(of: location.lastLocation) { _, newLocation in
                if let newLocation { navigator.update(with: newLocation) }
            }
            .onChange(of: keepAwake, initial: true) { _, awake in
                UIApplication.shared.isIdleTimerDisabled = awake
            }
            .onDisappear {
                location.stopUpdating()
                UIApplication.shared.isIdleTimerDisabled = false
            }
            .sensoryFeedback(.success, trigger: navigator.phase == .arrived)
            .sensoryFeedback(.impact(weight: .light), trigger: navigator.currentStepIndex)
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private var instructionBanner: some View {
        Group {
            if location.isDenied {
                Label("Turn on Location to track your walk.", systemImage: "location.slash.fill")
            } else {
                switch navigator.phase {
                case .idle, .routing:
                    HStack { ProgressView().tint(.white); Text("Finding a walking route…") }
                case .navigating:
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: navigator.isOffRoute ? "arrow.triangle.2.circlepath" : "arrow.turn.up.right")
                            .font(.title)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(navigator.isOffRoute ? "Off route — finding a new way…" : navigator.currentInstruction)
                                .font(.headline)
                            if navigator.metersToNextStep > 0, !navigator.isOffRoute {
                                Text("in \(DistanceText.distance(navigator.metersToNextStep))")
                                    .font(.subheadline)
                                    .opacity(0.9)
                            }
                        }
                    }
                case .arrived:
                    Label("You've arrived at \(navigator.destinationName)!", systemImage: "checkmark.seal.fill")
                case .failed(let message):
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                }
            }
        }
        .font(.headline)
        .foregroundStyle(.white)
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            navigator.phase == .arrived ? AnyShapeStyle(Color.green) : AnyShapeStyle(Theme.lagoonGradient),
            in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
        )
        .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        .accessibilityElement(children: .combine)
    }

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            if navigator.phase == .navigating {
                HStack {
                    metric(value: DistanceText.distance(navigator.remainingMeters), label: "left")
                    Divider().frame(height: 36)
                    metric(value: "\(max(1, Int((navigator.remainingSeconds / 60).rounded()))) min", label: "walking")
                    Divider().frame(height: 36)
                    metric(value: navigator.arrivalTime.formatted(date: .omitted, time: .shortened), label: "arrival")
                }
            }
            HStack(spacing: 10) {
                Button {
                    ExternalApps.openGoogleMaps(stops: [navigator.destination])
                } label: {
                    Label("Google Maps", systemImage: "map.fill")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color(hex: "#4285F4"))

                Button {
                    ExternalApps.openAppleMaps(to: navigator.destination, name: navigator.destinationName)
                } label: {
                    Label("Apple Maps", systemImage: "apple.logo")
                        .frame(maxWidth: .infinity, minHeight: 48)
                }
                .buttonStyle(.bordered)
                .tint(Theme.lagoon)
            }
            .font(.subheadline.weight(.semibold))
            Toggle("Keep screen on while walking", isOn: $keepAwake)
                .font(.caption)
                .tint(Theme.lagoon)
        }
        .padding()
        .background(.regularMaterial)
    }

    private func metric(value: String, label: String) -> some View {
        VStack(spacing: 2) {
            Text(value).font(.title3.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var stepsList: some View {
        NavigationStack {
            List(Array(navigator.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 12) {
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .frame(width: 24, height: 24)
                        .background(index == navigator.currentStepIndex ? Theme.mango : Color.gray, in: Circle())
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.instructions)
                        Text(DistanceText.distance(step.distance)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Directions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showingSteps = false } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

/// Which destination the walking tracker should open for.
struct WalkTarget: Identifiable {
    let id = UUID()
    let name: String
    let coordinate: CLLocationCoordinate2D
}

#Preview {
    WalkingRouteView(destinationName: "Wat Pho", coordinate: CLLocationCoordinate2D(latitude: 13.7465, longitude: 100.4927))
}
