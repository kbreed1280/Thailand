import SwiftUI

/// Before you fly: your passport's validity for this trip and the arrival forms the destination
/// asks for, each linking to the official site.
struct EntryRequirementsView: View {
    @ObservedObject var trip: Trip
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var vault = DocumentVault.shared
    @State private var showingTDAC = false

    private var passportExpiry: Date? {
        vault.documents.filter { $0.resolvedCategory == .passport }.compactMap(\.expiresAt).max()
    }

    private var forms: [EntryRequirements.Form] { EntryRequirements.forms(forCountry: trip.country) }

    var body: some View {
        NavigationStack {
            List {
                Section("Passport") { passportRow }

                Section {
                    if forms.isEmpty {
                        Label("No online arrival form we know of for \(trip.countryName). Check the official page below before you fly.",
                              systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(forms) { form in
                        Link(destination: form.url) {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(form.name).font(.headline).foregroundStyle(.primary)
                                    Spacer()
                                    Image(systemName: "arrow.up.right.square").foregroundStyle(Theme.lagoon)
                                }
                                Text(form.detail).font(.subheadline).foregroundStyle(.secondary)
                                Text(form.url.host() ?? "").font(.caption).foregroundStyle(Theme.lagoon)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                    if trip.isThailand {
                        Button("Arrival card reminders", systemImage: "bell.badge") { showingTDAC = true }
                    }
                } header: {
                    Text("Forms for \(trip.countryName)")
                } footer: {
                    Text("Only use official sites. Look-alike sites charge fees for free forms.")
                }

                Section {
                    Link(destination: EntryRequirements.stateDepartment) {
                        Label("Visa rules for U.S. citizens (State Department)", systemImage: "building.columns")
                    }
                } header: {
                    Text("Visa")
                } footer: {
                    Text("Visa rules depend on your passport. Entry rules change often. Last reviewed \(EntryRequirements.reviewed); confirm with the official site and your airline before you fly.")
                }
            }
            .navigationTitle("Entry Requirements")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .sheet(isPresented: $showingTDAC) { TDACView(trip: trip) }
        }
    }

    @ViewBuilder private var passportRow: some View {
        switch EntryRequirements.passportStatus(expires: passportExpiry, tripEnd: trip.endDate) {
        case .unknown:
            Label("Add your passport in Documents with its expiry date and we'll check it against this trip.", systemImage: "person.text.rectangle")
                .foregroundStyle(.secondary)
        case .expiresDuringTrip(let date):
            Label("Your passport expires \(date.formatted(date: .abbreviated, time: .omitted)), before this trip ends. Renew it before you go.",
                  systemImage: "exclamationmark.octagon.fill")
                .foregroundStyle(.red)
        case .underSixMonths(let date):
            Label("Expires \(date.formatted(date: .abbreviated, time: .omitted)), less than 6 months after this trip. Many countries require 6 months' validity, so check \(trip.countryName)'s rule.",
                  systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        case .ok(let date):
            Label("Valid until \(date.formatted(date: .abbreviated, time: .omitted)), more than 6 months after this trip.", systemImage: "checkmark.seal.fill")
                .foregroundStyle(.green)
        }
    }
}
