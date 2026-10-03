import SwiftUI

/// Curated ideas per city; one tap adds an idea to the wish list.
struct StarterIdeasView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var trip: Trip
    @State private var city: StarterCity = .bangkok
    @State private var refreshTick = 0

    private var existingTitles: Set<String> {
        Set(trip.allItems.compactMap { $0.title?.lowercased() })
    }

    var body: some View {
        let _ = refreshTick
        NavigationStack {
            List {
                Section {
                    Picker("City", selection: $city) {
                        ForEach(StarterCity.allCases) { city in
                            Text(city.rawValue).tag(city)
                        }
                    }
                    .pickerStyle(.menu)
                } footer: {
                    Text("Added ideas land on your Wish List. Drag them onto a day when you're ready.")
                }

                Section(city.rawValue) {
                    ForEach(city.ideas) { idea in
                        IdeaRow(idea: idea, isAdded: existingTitles.contains(idea.title.lowercased())) {
                            add(idea)
                        }
                    }
                }

                Section {
                    Button {
                        city.ideas
                            .filter { !existingTitles.contains($0.title.lowercased()) }
                            .forEach(add)
                    } label: {
                        Label("Add all \(city.rawValue) ideas", systemImage: "plus.square.on.square")
                    }
                    .disabled(city.ideas.allSatisfy { existingTitles.contains($0.title.lowercased()) })
                }
            }
            .navigationTitle("Starter Ideas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func add(_ idea: StarterIdea) {
        let store = ItineraryStore(context: context)
        store.addItem(
            title: idea.title,
            category: idea.category,
            to: nil,
            in: trip,
            address: idea.address,
            coordinate: idea.coordinate,
            notes: idea.blurb
        )
        store.save()
        refreshTick &+= 1
    }
}

private struct IdeaRow: View {
    let idea: StarterIdea
    let isAdded: Bool
    let onAdd: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            CategoryBadge(category: idea.category, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(idea.title).font(.subheadline.weight(.semibold))
                Text(idea.blurb).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark.circle.fill" : "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(isAdded ? .green : Theme.mango)
                    .frame(minWidth: 44, minHeight: 44)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .accessibilityLabel(isAdded ? "\(idea.title) added" : "Add \(idea.title) to wish list")
        }
        .padding(.vertical, 2)
    }
}
