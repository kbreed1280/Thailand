import SwiftUI
import MapKit

// MARK: - Food guide

/// Offline "Must-try Thai food" guide with spice and allergen filters.
struct FoodGuideView: View {
    @State private var maxSpice = 3
    @State private var avoid: Set<Allergen> = []
    @State private var search = ""

    private var dishes: [Dish] {
        FoodGuide.dishes.filter { dish in
            dish.spice <= maxSpice
                && avoid.isDisjoint(with: dish.allergens)
                && (search.isEmpty
                    || dish.name.localizedCaseInsensitiveContains(search)
                    || dish.description.localizedCaseInsensitiveContains(search)
                    || dish.thai.contains(search))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Max spice", selection: $maxSpice) {
                    Text("Any").tag(3)
                    Text("Medium").tag(2)
                    Text("Mild").tag(1)
                    Text("None").tag(0)
                }
                .pickerStyle(.segmented)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Avoid:").font(.subheadline).foregroundStyle(.secondary)
                        ForEach(Allergen.allCases) { allergen in
                            let on = avoid.contains(allergen)
                            Button {
                                if on { avoid.remove(allergen) } else { avoid.insert(allergen) }
                            } label: {
                                Text(allergen.rawValue)
                                    .font(.caption.weight(.semibold))
                                    .padding(.horizontal, 10)
                                    .frame(minHeight: 32)
                                    .foregroundStyle(on ? .white : Theme.coral)
                                    .background(on ? Theme.coral : Theme.coral.opacity(0.12), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityValue(on ? "Avoiding" : "Not avoiding")
                        }
                    }
                }
            } footer: {
                Text("Allergens are typical for each dish but recipes vary — always show the vendor your allergy.")
            }

            Section("\(dishes.count) dishes") {
                ForEach(dishes) { dish in
                    NavigationLink {
                        DishDetailView(dish: dish)
                    } label: {
                        DishRow(dish: dish)
                    }
                }
            }
        }
        .searchable(text: $search, prompt: "Search dishes")
        .navigationTitle("Must-Try Thai Food")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct SpiceMeter: View {
    let level: Int

    var body: some View {
        HStack(spacing: 1) {
            if level == 0 {
                Text("Not spicy").font(.caption2.weight(.semibold)).foregroundStyle(.green)
            } else {
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "flame.fill")
                        .font(.caption2)
                        .foregroundStyle(index < level ? Theme.coral : Color.gray.opacity(0.3))
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(level == 0 ? "Not spicy" : "Spice level \(level) of 3")
    }
}

private struct DishRow: View {
    let dish: Dish

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: dish.symbol)
                .font(.title3)
                .foregroundStyle(Theme.mango)
                .frame(width: 42, height: 42)
                .background(Theme.mango.opacity(0.14), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(dish.name).font(.headline)
                    SpiceMeter(level: dish.spice)
                }
                Text("\(dish.thai) · \(dish.pronunciation)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct DishDetailView: View {
    let dish: Dish
    @StateObject private var speaker = Speaker.shared
    @AppStorage(PoliteParticle.storageKey) private var particle: PoliteParticle = .khrap
    @State private var notSpicy = false
    @State private var avoid: Set<Allergen> = []
    @State private var showContent: ShowModeContent?

    /// e.g. "ผัดไทย ไม่ใส่ถั่วลิสง ไม่เผ็ด ครับ"
    private var vendorThai: String {
        var parts = [dish.thai]
        if notSpicy { parts.append("ไม่เผ็ด") }
        parts += avoid.sorted { $0.rawValue < $1.rawValue }.compactMap(\.thaiNoRequest)
        return parts.joined(separator: " ") + particle.thai
    }

    private var vendorEnglish: String {
        var parts = [dish.name]
        if notSpicy { parts.append("not spicy") }
        parts += avoid.filter { $0.thaiNoRequest != nil }.map { "no \($0.rawValue.lowercased())" }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(dish.thai).font(.system(size: 44, weight: .bold))
                    Text(dish.pronunciation).font(.title3).italic().foregroundStyle(.secondary)
                    SpiceMeter(level: dish.spice)
                    Text(dish.description).font(.body)
                }
                .card()

                if !dish.allergens.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Usually contains", systemImage: "exclamationmark.triangle.fill")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(Theme.coral)
                        FlowChips(items: dish.allergens.map(\.rawValue), tint: Theme.coral)
                    }
                    .card()
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Order it your way").font(.headline)
                    Toggle("Not spicy", isOn: $notSpicy)
                    ForEach(Allergen.allCases.filter { $0.thaiNoRequest != nil }) { allergen in
                        Toggle("No \(allergen.rawValue.lowercased())", isOn: Binding(
                            get: { avoid.contains(allergen) },
                            set: { if $0 { avoid.insert(allergen) } else { avoid.remove(allergen) } }
                        ))
                    }
                    Text(vendorThai).font(.title3.weight(.semibold))
                    HStack(spacing: 10) {
                        Button {
                            showContent = ShowModeContent(thai: vendorThai, english: vendorEnglish, romanized: ThaiText.romanize(vendorThai))
                        } label: {
                            Label("Show to the Vendor", systemImage: "rectangle.expand.vertical")
                        }
                        .buttonStyle(.primary)
                        Button {
                            speaker.speak(vendorThai, languageCode: "th", slow: true)
                        } label: {
                            Image(systemName: "speaker.wave.2.fill")
                                .font(.title3)
                                .frame(width: 52, height: 52)
                                .background(Theme.lagoon.opacity(0.14), in: Circle())
                                .foregroundStyle(Theme.lagoon)
                        }
                        .accessibilityLabel("Speak in Thai")
                    }
                }
                .tint(Theme.mango)
                .card()
            }
            .padding()
        }
        .background(Theme.background)
        .navigationTitle(dish.name)
        .navigationBarTitleDisplayMode(.inline)
        .fullScreenCover(item: $showContent) { ShowModeView(content: $0) }
    }
}

/// Simple wrapping row of capsules.
struct FlowChips: View {
    let items: [String]
    var tint: Color = Theme.mango

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) { chips }
            VStack(alignment: .leading, spacing: 6) { chips }
        }
    }

    private var chips: some View {
        ForEach(items, id: \.self) { item in
            Text(item)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .foregroundStyle(tint)
                .background(tint.opacity(0.13), in: Capsule())
        }
    }
}

// MARK: - Stay guide

struct StayGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var onFindHotels: ((StayArea) -> Void)? = nil

    var body: some View {
        List {
            ForEach(StarterCity.allCases) { city in
                Section(city.rawValue) {
                    ForEach(StayGuide.areas.filter { $0.city == city }) { area in
                        HStack(alignment: .top, spacing: 12) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(area.name).font(.headline)
                                Text(area.goodFor).font(.subheadline).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let onFindHotels {
                                Button {
                                    onFindHotels(area)
                                    dismiss()
                                } label: {
                                    Image(systemName: "bed.double.circle.fill")
                                        .font(.title)
                                        .foregroundStyle(Theme.lagoon)
                                        .frame(minWidth: 44, minHeight: 44)
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Find hotels in \(area.name)")
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .navigationTitle("Where to Stay")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Etiquette & scams

struct EtiquetteGuideView: View {
    var body: some View {
        List {
            ForEach(EtiquetteGuide.sections) { section in
                Section(section.title) {
                    ForEach(section.tips) { tip in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: tip.systemImage)
                                .foregroundStyle(section.title == "Common scams" ? Theme.coral : Theme.lagoon)
                                .frame(width: 28)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(tip.title).font(.headline)
                                Text(tip.detail).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
        }
        .navigationTitle("Etiquette & Scams")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Food") {
    NavigationStack { FoodGuideView() }
}

#Preview("Stay") {
    NavigationStack { StayGuideView() }
}

#Preview("Etiquette") {
    NavigationStack { EtiquetteGuideView() }
}
