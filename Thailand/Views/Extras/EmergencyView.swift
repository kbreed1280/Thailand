import SwiftUI

/// Emergency numbers for the trip's country, the US Embassy, nearest hospital and your hotel address
/// in the local language.
struct EmergencyView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @AppStorage(PoliteParticle.storageKey) private var particle: PoliteParticle = .khrap
    let trip: Trip?

    @State private var hotelThai = ""
    @State private var showContent: ShowModeContent?

    private struct Contact: Identifiable {
        let name: String
        let detail: String
        let number: String
        let systemImage: String
        var id: String { number }
    }

    private var country: String { trip?.country ?? "TH" }
    private var isThailand: Bool { country == "TH" }

    private var contacts: [Contact] {
        if isThailand {
            return [
                Contact(name: "Tourist Police", detail: "English-speaking, 24 hours", number: "1155", systemImage: "shield.lefthalf.filled"),
                Contact(name: "Ambulance & Medical", detail: "Emergency medical service", number: "1669", systemImage: "cross.case.fill"),
                Contact(name: "Police", detail: "General emergencies", number: "191", systemImage: "light.beacon.max.fill"),
                Contact(name: "Fire", detail: "Fire and rescue", number: "199", systemImage: "flame.fill"),
                Contact(name: "US Embassy Bangkok", detail: "95 Wireless Rd · American Citizen Services", number: "+6622054000", systemImage: "building.columns.fill")
            ]
        }
        let n = Destinations.emergency(forCountry: country)
        var list: [Contact] = []
        if let tourist = n.tourist {
            list.append(Contact(name: "Tourist Police", detail: "Help for visitors", number: tourist, systemImage: "shield.lefthalf.filled"))
        }
        if n.police == n.ambulance && n.police == n.fire {
            list.append(Contact(name: "Emergency", detail: "Police, ambulance and fire", number: n.police, systemImage: "light.beacon.max.fill"))
        } else {
            list.append(Contact(name: "Ambulance & Medical", detail: "Emergency medical service", number: n.ambulance, systemImage: "cross.case.fill"))
            list.append(Contact(name: "Police", detail: "General emergencies", number: n.police, systemImage: "light.beacon.max.fill"))
            if n.fire != n.ambulance {
                list.append(Contact(name: "Fire", detail: "Fire and rescue", number: n.fire, systemImage: "flame.fill"))
            }
        }
        return list
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(contacts) { contact in
                        Button {
                            ExternalApps.call(contact.number)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: contact.systemImage)
                                    .font(.title2)
                                    .foregroundStyle(.white)
                                    .frame(width: 46, height: 46)
                                    .background(Color.red.gradient, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(contact.name).font(.headline).foregroundStyle(.primary)
                                    Text(contact.detail).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text(contact.number == "+6622054000" ? "+66 2 205 4000" : contact.number)
                                    .font(.title3.bold().monospacedDigit())
                                    .foregroundStyle(.red)
                            }
                            .padding(.vertical, 4)
                        }
                        .accessibilityLabel("Call \(contact.name), \(contact.number)")
                    }
                } header: {
                    Text("Tap to call")
                } footer: {
                    if isThailand {
                        Text("Numbers work from any Thai or roaming phone. The Tourist Police (1155) is usually the best first call for visitors.")
                    } else {
                        Text("Emergency numbers for \(trip?.countryName ?? "this country"). 112 also works from most mobile phones worldwide.")
                    }
                }

                Section("Nearest hospital") {
                    Button {
                        if let url = URL(string: "https://maps.apple.com/?q=hospital") { UIApplication.shared.open(url) }
                    } label: {
                        Label("Find hospitals near me", systemImage: "cross.fill")
                    }
                    if !isThailand {
                        Button {
                            if let url = URL(string: "https://maps.apple.com/?q=US%20Embassy") { UIApplication.shared.open(url) }
                        } label: {
                            Label("Find the US Embassy", systemImage: "building.columns.fill")
                        }
                    }
                    if isThailand {
                        Button {
                            let phrase = Phrasebook.emergency.first { $0.english == "Where is the hospital?" }
                            showContent = ShowModeContent(
                                thai: phrase?.thai(with: particle) ?? "โรงพยาบาลอยู่ที่ไหน",
                                english: "Where is the hospital?",
                                romanized: phrase?.romanized(with: particle)
                            )
                        } label: {
                            Label("Show \"Where is the hospital?\" in Thai", systemImage: "rectangle.expand.vertical")
                        }
                    }
                }

                if let trip {
                    Section {
                        TextField(isThailand ? "Hotel name and address in Thai" : "Hotel name and address in the local language", text: $hotelThai, axis: .vertical)
                            .lineLimit(2...5)
                            .font(.title3)
                        Button {
                            showContent = ShowModeContent(
                                thai: isThailand ? "ช่วยพาไปที่นี่\(particle.thai)\n\(hotelThai)" : hotelThai,
                                english: "Please take me here: our hotel",
                                romanized: nil
                            )
                        } label: {
                            Label("Show to Driver", systemImage: "car.fill")
                        }
                        .disabled(hotelThai.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    } header: {
                        Text("Our hotel")
                    } footer: {
                        Text("Copy the \(isThailand ? "Thai" : "local-language") address from your booking or ask the front desk to type it. Shared with everyone on \(trip.displayName).")
                    }
                    .onAppear { hotelThai = trip.hotelAddressThai ?? "" }
                    .onChange(of: hotelThai) { _, newValue in
                        trip.hotelAddressThai = newValue
                        ItineraryStore(context: context).save()
                    }
                }
            }
            .navigationTitle("Emergency")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .fullScreenCover(item: $showContent) { ShowModeView(content: $0) }
        }
    }
}

#Preview {
    EmergencyView(trip: nil)
}
