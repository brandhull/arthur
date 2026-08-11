import SwiftUI
import ArthurKit

/// Read-only popup for a single Baserow search result — label:value for
/// every field that actually has a value, skipping empty ones (Brandon's
/// choice), in the same field order Baserow itself returns from
/// `listFields`.
struct BaserowRowDetailView: View {
    let row: BaserowRow
    let fields: [BaserowField]
    let scheme: ColorScheme
    @Environment(\.dismiss) private var dismiss

    private var populatedFields: [(field: BaserowField, value: String)] {
        fields.compactMap { field in
            guard let value = SearchBaserowView.displayString(row.fields[field.name]), !value.isEmpty else {
                return nil
            }
            return (field, value)
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(populatedFields, id: \.field.id) { entry in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.field.name)
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Theme.secondaryText(scheme))
                            Text(entry.value)
                                .font(.system(size: 16))
                        }
                    }
                }
                .padding(20)
            }
            .foregroundStyle(Theme.primary(scheme))
            .background(Theme.background(scheme))
            .navigationTitle("Record")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .preferredColorScheme(scheme)
        #if os(macOS)
        .frame(minWidth: 420, idealWidth: 480, minHeight: 320, idealHeight: 480)
        #endif
    }
}
