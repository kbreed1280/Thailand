import SwiftUI
import MapKit

/// How maps look across the app: detailed standard, satellite or hybrid, all with realistic 3D terrain and
/// buildings (tilt with two fingers). One setting, remembered, shared by every map.
enum MapLook: String, CaseIterable, Identifiable {
    case standard, satellite, hybrid

    static let storageKey = "mapLook"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .standard: "Detailed"
        case .satellite: "Satellite"
        case .hybrid: "Hybrid"
        }
    }

    var systemImage: String {
        switch self {
        case .standard: "map"
        case .satellite: "globe.americas.fill"
        case .hybrid: "square.2.layers.3d"
        }
    }

    /// SwiftUI `Map` style.
    var style: MapStyle {
        switch self {
        case .standard: .standard(elevation: .realistic, emphasis: .automatic, pointsOfInterest: .all, showsTraffic: false)
        case .satellite: .imagery(elevation: .realistic)
        case .hybrid: .hybrid(elevation: .realistic, pointsOfInterest: .all, showsTraffic: false)
        }
    }

    /// UIKit `MKMapView` configuration (the Spots map).
    var configuration: MKMapConfiguration {
        switch self {
        case .standard: MKStandardMapConfiguration(elevationStyle: .realistic, emphasisStyle: .default)
        case .satellite: MKImageryMapConfiguration(elevationStyle: .realistic)
        case .hybrid: MKHybridMapConfiguration(elevationStyle: .realistic)
        }
    }
}

extension View {
    /// Applies the saved map look; with `showsPicker`, adds a small layers button in the corner.
    func mapLook(showsPicker: Bool = true, alignment: Alignment = .topLeading) -> some View {
        modifier(MapLookModifier(showsPicker: showsPicker, alignment: alignment))
    }
}

private struct MapLookModifier: ViewModifier {
    let showsPicker: Bool
    let alignment: Alignment
    @AppStorage(MapLook.storageKey) private var lookRaw = MapLook.standard.rawValue

    func body(content: Content) -> some View {
        let look = MapLook(rawValue: lookRaw) ?? .standard
        content
            .mapStyle(look.style)
            .overlay(alignment: alignment) {
                if showsPicker { MapLookButton().padding(10) }
            }
    }
}

/// Layers button: pick Detailed / Satellite / Hybrid.
struct MapLookButton: View {
    @AppStorage(MapLook.storageKey) private var lookRaw = MapLook.standard.rawValue

    var body: some View {
        let look = MapLook(rawValue: lookRaw) ?? .standard
        Menu {
            Picker("Map style", selection: $lookRaw) {
                ForEach(MapLook.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option.rawValue)
                }
            }
        } label: {
            Image(systemName: look.systemImage)
                .font(.system(size: 17, weight: .semibold))
                .frame(width: 44, height: 44)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .shadow(color: .black.opacity(0.15), radius: 3, y: 1)
        }
        .accessibilityLabel("Map style: \(look.title)")
    }
}
