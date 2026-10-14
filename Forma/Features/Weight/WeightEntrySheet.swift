import SwiftUI
import SwiftData
import FormaKit

/// Fast weigh-in entry. Opens with the number field focused; date and time
/// default to now and can be backdated.
struct WeightEntrySheet: View {
    let entry: WeightEntry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Query(sort: \WeightEntry.measuredAt, order: .reverse) private var entries: [WeightEntry]

    @State private var text = ""
    @State private var measuredAt = Date()
    @State private var note = ""
    @State private var showDeleteConfirmation = false
    @State private var attemptedSave = false
    @FocusState private var valueFocused: Bool

    private var unit: WeightUnit { settings.unit }

    private var parsedValue: Double? {
        NumberParsing.decimal(from: text)
    }

    private var validationMessage: String? {
        guard let value = parsedValue else {
            return text.isEmpty ? nil : "Enter a number, like \(unit == .kilograms ? "72.4" : "160.2")."
        }
        let kg = unit.toKilograms(value)
        if !HealthImportDeduplicator.plausibleRange.contains(kg) {
            return "That looks outside the usual range. Check the value and unit."
        }
        return nil
    }

    private var canSave: Bool { parsedValue != nil && validationMessage == nil }

    private var previous: WeightEntry? {
        entries.first { $0.id != entry?.id && $0.measuredAt <= measuredAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.s) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            TextField(unit == .kilograms ? "0.0" : "0.0", text: $text)
                                .keyboardType(.decimalPad)
                                .font(.metric(.largeTitle))
                                .multilineTextAlignment(.trailing)
                                .focused($valueFocused)
                                .fixedSize()
                                .frame(minWidth: 120, alignment: .trailing)
                                .accessibilityLabel("Weight in \(unit.name.lowercased())")
                            Text(unit.symbol)
                                .font(.title2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        if let previous {
                            Text("Previous: \(Format.weight(previous.kilograms, unit: unit)) · \(Format.relative(previous.measuredAt))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, Theme.Spacing.s)
                    if let validationMessage, attemptedSave || parsedValue != nil {
                        Label(validationMessage, systemImage: "exclamationmark.circle")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }

                Section {
                    DatePicker("Measured", selection: $measuredAt, in: ...Date(), displayedComponents: [.date, .hourAndMinute])
                    TextField("Note (optional)", text: $note, axis: .vertical)
                        .lineLimit(1...3)
                } footer: {
                    if let entry, entry.isImported {
                        Text("Imported from \(entry.healthSourceName ?? "Apple Health"). Changes here stay in Forma and don't modify Apple Health.")
                    } else if settings.values.health.saveWeight && health.status == .connected {
                        Text("This weigh-in will also be saved to Apple Health.")
                    }
                }

                if entry != nil {
                    Section {
                        Button("Delete Weigh-in", role: .destructive) {
                            showDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(entry == nil ? "Log Weight" : "Edit Weigh-in")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .fontWeight(.semibold)
                        .disabled(parsedValue == nil)
                }
            }
            .confirmationDialog("Delete this weigh-in?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { deleteEntry() }
            } message: {
                if entry?.writtenHealthSampleUUID != nil {
                    Text("The copy Forma saved to Apple Health will be removed too.")
                }
            }
            .onAppear(perform: load)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func load() {
        if let entry {
            text = Format.weightValue(entry.kilograms, unit: unit, fractionDigits: 2)
            measuredAt = entry.measuredAt
            note = entry.note
        } else {
            measuredAt = Date()
            valueFocused = true
        }
    }

    private func save() {
        attemptedSave = true
        guard canSave, let value = parsedValue else {
            Haptics.warning()
            return
        }
        let kg = unit.toKilograms(value)
        let target: WeightEntry
        if let entry {
            entry.kilograms = kg
            entry.measuredAt = measuredAt
            entry.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            entry.updatedAt = Date()
            target = entry
        } else {
            target = WeightEntry(kilograms: kg, measuredAt: measuredAt, note: note.trimmingCharacters(in: .whitespacesAndNewlines))
            context.insert(target)
        }
        try? context.save()
        Haptics.success()
        dismiss()
        Task {
            await health.syncWeight(target)
            try? context.save()
        }
    }

    private func deleteEntry() {
        guard let entry else { return }
        Task {
            await health.deleteWrittenWeight(entry)
            context.delete(entry)
            try? context.save()
        }
        dismiss()
    }
}
