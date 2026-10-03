import PhotosUI
import SwiftUI

/// Thailand Digital Arrival Card: when to submit, links to THIM / the official site,
/// reminders, and a place to keep the confirmation QR code.
struct TDACView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var flights = FlightStore.shared
    @ObservedObject private var vault = DocumentVault.shared

    @AppStorage private var submitted: Bool
    @AppStorage private var remindersOn: Bool
    @State private var qrItem: PhotosPickerItem?
    @State private var savedMessage: String?

    init(trip: Trip) {
        self.trip = trip
        let key = trip.uuid?.uuidString ?? "default"
        _submitted = AppStorage(wrappedValue: false, "tdacSubmitted-\(key)")
        _remindersOn = AppStorage(wrappedValue: false, "tdacReminders-\(key)")
    }

    private var window: TDACReminder.Window? {
        TDACReminder.window(tripStart: trip.startDate, flights: flights.flights)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    statusHeader
                }

                Section {
                    Button { TDACReminder.openTHIM() } label: {
                        Label("Open THIM (Thai Immigration app)", systemImage: "arrow.up.forward.app.fill")
                    }
                    Link(destination: TDACReminder.officialWebsite) {
                        Label("Official TDAC website", systemImage: "safari")
                    }
                } header: {
                    Text("Submit your arrival card")
                } footer: {
                    Text("Each traveler submits their own card. It's free. Ignore sites that charge a fee. You'll need your passport, flight number, and where you're staying the first night.")
                }

                Section {
                    Toggle("Remind us when it opens", isOn: $remindersOn)
                        .disabled(submitted || window?.status() == .passed)
                    Toggle("I've submitted my TDAC", isOn: $submitted)
                } footer: {
                    Text("Reminders go off on this iPhone at 9 AM the day the window opens, and the day before you land.")
                }

                Section {
                    PhotosPicker(selection: $qrItem, matching: .images) {
                        Label("Save TDAC QR code to Documents", systemImage: "qrcode.viewfinder")
                    }
                    if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    }
                } header: {
                    Text("After you submit")
                } footer: {
                    Text("Screenshot the confirmation/QR code from THIM or the email, then save it here. It goes into your Face ID-locked Documents vault under Visa & Entry, so it's ready at immigration even with no signal.")
                }
            }
            .navigationTitle("Arrival Card (TDAC)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .onChange(of: remindersOn) { _, on in Task { await updateReminders(on: on) } }
            .onChange(of: submitted) { _, done in
                if done { remindersOn = false; TDACReminder.cancel() }
            }
            .onChange(of: qrItem) { _, item in
                guard let item else { return }
                Task { await saveQR(item) }
            }
        }
    }

    @ViewBuilder private var statusHeader: some View {
        VStack(alignment: .leading, spacing: 8) {
            if submitted {
                Label("Submitted. You're all set.", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(.green)
            } else if let window {
                switch window.status() {
                case .notYet:
                    Label("Opens \(window.opens.formatted(.dateTime.weekday(.wide).month().day()))", systemImage: "calendar.badge.clock")
                        .font(.headline).foregroundStyle(Theme.mango)
                    Text("\(Self.daysText(until: window.opens)) You can submit from 3 days before you land.")
                case .open:
                    Label("Open now. Submit it today", systemImage: "exclamationmark.circle.fill")
                        .font(.headline).foregroundStyle(Theme.coral)
                    Text("You land \(window.arrival.formatted(.dateTime.weekday(.wide).month().day())).")
                case .passed:
                    Label("Your arrival date has passed", systemImage: "clock.badge.checkmark")
                        .font(.headline).foregroundStyle(.secondary)
                }
                Text("Based on \(window.source) (arrival \(window.arrival.formatted(date: .abbreviated, time: .omitted))).")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Label("Set your trip dates or add your flight", systemImage: "calendar")
                    .font(.headline)
                Text("The arrival card window opens 3 days before you land.").font(.subheadline)
            }
        }
        .padding(.vertical, 4)
    }

    static func daysText(until date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: .now),
                                                   to: Calendar.current.startOfDay(for: date)).day ?? 0
        return days <= 0 ? "Today." : days == 1 ? "Tomorrow." : "In \(days) days."
    }

    private func updateReminders(on: Bool) async {
        if on, let window {
            await TDACReminder.schedule(for: window)
        } else {
            TDACReminder.cancel()
        }
    }

    private func saveQR(_ item: PhotosPickerItem) async {
        defer { qrItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data), let jpeg = image.jpegData(compressionQuality: 0.9) else { return }
        if !vault.isUnlocked { await vault.unlock() }
        guard vault.isUnlocked else { return }
        let name = AppSettings.displayName
        vault.add(data: jpeg, title: "Thailand Arrival Card (TDAC)\(name.isEmpty ? "" : " · \(name)")", kind: .image, category: .visa)
        savedMessage = "Saved to Documents › Visa & Entry"
        submitted = true
    }
}
