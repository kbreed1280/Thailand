import SwiftUI

/// The name shown as "added by" on things you add. Once trip sharing is on, your iCloud name is used.
struct ProfileSheet: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage(AppSettings.displayNameKey) private var displayName = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Your first name", text: $displayName)
                        .textContentType(.givenName)
                        .font(.title3)
                } footer: {
                    Text("Shown next to places, expenses and packing items you add, so your travel partner knows who added what.")
                }
            }
            .navigationTitle("Your Name")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium])
    }
}
