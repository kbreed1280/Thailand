import SwiftUI
import EventKit

/// Calendar options: show your calendar in the itinerary, and copy timed items into a calendar.
struct CalendarSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var calendar = CalendarSyncService.shared
    @ObservedObject var trip: Trip
    @State private var synced = false

    var body: some View {
        NavigationStack {
            Group {
                if calendar.isDenied {
                    PermissionDeniedView(kind: .calendar)
                } else if !calendar.hasAccess {
                    EmptyStateView(
                        systemImage: "calendar",
                        title: "Use Your Calendar",
                        message: "See your calendar events next to each day's plan, and add timed plans to your calendar so they show on your watch and lock screen."
                    ) {
                        Button("Allow Calendar Access") {
                            Task { _ = await calendar.requestAccess() }
                        }
                        .buttonStyle(.primary)
                    }
                } else {
                    settingsForm
                }
            }
            .background(Theme.background)
            .navigationTitle("Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private var settingsForm: some View {
        let _ = calendar.changeTick
        return Form {
            Section {
                Toggle("Show calendar events in the itinerary", isOn: Binding(
                    get: { calendar.showEvents },
                    set: { calendar.showEvents = $0 }
                ))
            } footer: {
                Text("Events appear as grey rows on each day. Long-press one to add it to the trip.")
            }

            if calendar.showEvents {
                Section("Calendars to show") {
                    ForEach(calendar.calendars, id: \.calendarIdentifier) { item in
                        let shown = calendar.shownCalendarIDs.isEmpty || calendar.shownCalendarIDs.contains(item.calendarIdentifier)
                        Button {
                            var ids = calendar.shownCalendarIDs.isEmpty
                                ? Set(calendar.calendars.map(\.calendarIdentifier))
                                : calendar.shownCalendarIDs
                            if shown { ids.remove(item.calendarIdentifier) } else { ids.insert(item.calendarIdentifier) }
                            calendar.shownCalendarIDs = ids
                        } label: {
                            HStack {
                                Circle().fill(Color(cgColor: item.cgColor)).frame(width: 12, height: 12)
                                Text(item.title).foregroundStyle(.primary)
                                Spacer()
                                if shown { Image(systemName: "checkmark").foregroundStyle(Theme.mango) }
                            }
                        }
                    }
                }
            }

            Section {
                Toggle("Add itinerary items to my calendar", isOn: Binding(
                    get: { calendar.addItemsToCalendar },
                    set: { calendar.addItemsToCalendar = $0 }
                ))
                if calendar.addItemsToCalendar {
                    Picker("Calendar", selection: Binding(
                        get: { calendar.targetCalendarID ?? calendar.store.defaultCalendarForNewEvents?.calendarIdentifier ?? "" },
                        set: { calendar.targetCalendarID = $0 }
                    )) {
                        ForEach(calendar.writableCalendars, id: \.calendarIdentifier) { item in
                            Text(item.title).tag(item.calendarIdentifier)
                        }
                    }
                    Button(synced ? "Calendar updated ✓" : "Add All Timed Plans Now") {
                        calendar.syncAll(trip)
                        synced = true
                    }
                }
            } footer: {
                Text("Places with a time are added, updated when you change them, and removed when you delete them. This only affects your own calendar, not your travel partner's.")
            }
        }
    }
}
