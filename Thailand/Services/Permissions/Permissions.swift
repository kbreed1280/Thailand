import SwiftUI
import UIKit

enum PermissionKind: String, Identifiable {
    case location, camera, microphone, speech, photos, calendar, motion

    var id: String { rawValue }

    var title: String {
        switch self {
        case .location: "Location Is Off"
        case .camera: "Camera Access Needed"
        case .microphone: "Microphone Access Needed"
        case .speech: "Speech Recognition Needed"
        case .photos: "Photo Access Needed"
        case .calendar: "Calendar Access Needed"
        case .motion: "Motion & Fitness Is Off"
        }
    }

    var message: String {
        switch self {
        case .location: "Turn on Location (While Using the App) for Thailand Trip in Settings to see where you are and what's nearby."
        case .camera: "Allow camera access in Settings to take photos and scan menus and signs."
        case .microphone: "Allow microphone access in Settings to use voice translation."
        case .speech: "Allow Speech Recognition in Settings so the app can turn what you say into text."
        case .photos: "Allow photo access in Settings to add photos from your library."
        case .calendar: "Allow calendar access in Settings to see your events next to your plans."
        case .motion: "Turn on Motion & Fitness for Thailand Trip in Settings to count your steps and distance walked."
        }
    }

    var systemImage: String {
        switch self {
        case .location: "location.slash.fill"
        case .camera: "camera.fill"
        case .microphone: "mic.slash.fill"
        case .speech: "waveform.slash"
        case .photos: "photo.on.rectangle"
        case .calendar: "calendar.badge.exclamationmark"
        case .motion: "figure.walk"
        }
    }
}

enum PermissionCenter {
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

/// Full-area explanation shown when a feature's permission was denied.
struct PermissionDeniedView: View {
    let kind: PermissionKind

    var body: some View {
        EmptyStateView(systemImage: kind.systemImage, title: kind.title, message: kind.message) {
            Button("Open Settings") { PermissionCenter.openSettings() }
                .buttonStyle(.primary)
        }
    }
}

extension View {
    /// Alert with an "Open Settings" button for a permission that was just denied.
    func permissionAlert(_ kind: Binding<PermissionKind?>) -> some View {
        alert(
            kind.wrappedValue?.title ?? "",
            isPresented: Binding(get: { kind.wrappedValue != nil }, set: { if !$0 { kind.wrappedValue = nil } }),
            presenting: kind.wrappedValue
        ) { _ in
            Button("Open Settings") { PermissionCenter.openSettings() }
            Button("Not Now", role: .cancel) {}
        } message: { kind in
            Text(kind.message)
        }
    }
}
