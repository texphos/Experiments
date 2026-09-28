import SwiftUI
import HearthdayCore

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var showingPro = false
    @State private var editingFormula: Formula?
    @State private var confirmingReset = false

    private func binding<T>(_ keyPath: WritableKeyPath<UserSettings, T>) -> Binding<T> {
        Binding(get: { model.state.settings[keyPath: keyPath] }, set: { v in model.update { $0.settings[keyPath: keyPath] = v } })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                WeekRibbon(availability: model.state.settings.availability).card()
                                BusyBlockList(availability: binding(\.availability))
                            }
                            .padding()
                        }
                        .background(Palette.flour.ignoresSafeArea())
                        .navigationTitle("Busy times")
                    } label: {
                        LabeledContent("Busy times", value: "\(model.state.settings.availability.blocks.count)")
                    }
                } footer: {
                    Text("Hands-on steps are never scheduled inside these.")
                }

                Section("Kitchen and starter") {
                    TemperatureStepper(celsius: binding(\.kitchenTempC), fahrenheit: model.state.settings.usesFahrenheit)
                    Toggle("Show °F", isOn: binding(\.usesFahrenheit))
                    Toggle("Starter usually needs a feed", isOn: binding(\.starterUsuallyNeedsFeed))
                    Picker("Usual feed ratio", selection: binding(\.preferredFeedRatio)) {
                        ForEach(FeedRatio.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }

                Section {
                    Toggle("Adjust starter amount", isOn: binding(\.allowInoculationAdjustment))
                    Toggle("Adjust feed ratio", isOn: binding(\.allowFeedRatioAdjustment))
                } header: {
                    Text("Let Hearthday adjust")
                } footer: {
                    Text("Less starter slows the dough; a leaner feed slows the starter. Both help a bake fit around a work day.")
                }

                Section("Formulas") {
                    ForEach(model.state.formulas) { f in
                        Button { editingFormula = f } label: {
                            VStack(alignment: .leading) {
                                Text(f.name).foregroundStyle(Palette.rye)
                                Text("\(Int(f.flourGrams)) g · \(Int(f.hydrationPercent))% water · \(Int(f.starterPercent))% starter")
                                    .font(.footnote).foregroundStyle(Palette.ash)
                            }
                        }
                    }
                    Button {
                        if model.state.canAddFormula {
                            editingFormula = Formula(name: "", flourGrams: 500, hydrationPercent: 70, starterPercent: 20, saltPercent: 2)
                        } else {
                            showingPro = true
                        }
                    } label: {
                        Label(model.state.canAddFormula ? "Add formula" : "Add formula (Pro)", systemImage: "plus")
                    }
                }

                Section("Hearthday Pro") {
                    Button {
                        showingPro = true
                    } label: {
                        HStack {
                            Text(model.state.isPro ? "Pro is on. Thank you." : "What Pro adds")
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Palette.ash).accessibilityHidden(true)
                        }
                    }
                    .accessibilityIdentifier("settings.pro")
                }

                Section {
                    Text("No account, no analytics, no tracking. Your schedule and bakes are stored only on this iPhone and in your device backups.")
                        .font(.footnote).foregroundStyle(Palette.ash)
                    Button("Erase all Hearthday data", role: .destructive) { confirmingReset = true }
                } header: {
                    Text("Privacy")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Palette.flour.ignoresSafeArea())
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPro) { ProView() }
            .sheet(item: $editingFormula) { f in
                FormulaEditor(formula: f, isNew: !model.state.formulas.contains { $0.id == f.id })
            }
            .confirmationDialog("Erase everything?", isPresented: $confirmingReset, titleVisibility: .visible) {
                Button("Erase all data", role: .destructive) { model.resetEverything() }
            } message: {
                Text("This removes your busy times, formulas, journal and calibration from this iPhone. A Pro purchase stays with your Apple Account and can be restored.")
            }
        }
    }
}

private struct FormulaEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State var formula: Formula
    var isNew: Bool

    /// A blank name becomes "My loaf" on save.
    private var blockingProblems: [InputProblem] { formula.problems.filter { $0 != .formulaNameEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $formula.name)
                Stepper("Flour \(Int(formula.flourGrams)) g", value: $formula.flourGrams, in: Limits.flourGrams, step: 50)
                Stepper("Water \(Int(formula.hydrationPercent))%", value: $formula.hydrationPercent, in: Limits.hydrationPercent, step: 1)
                Stepper("Starter \(Int(formula.starterPercent))%", value: $formula.starterPercent, in: Limits.starterPercent, step: 1)
                Stepper("Salt \(String(format: "%.1f", formula.saltPercent))%", value: $formula.saltPercent, in: Limits.saltPercent, step: 0.1)
                ForEach(blockingProblems, id: \.code) { problem in
                    Label(problem.message, systemImage: "exclamationmark.circle").foregroundStyle(Palette.warning)
                }
                if !isNew && model.state.formulas.count > 1 {
                    Button("Delete formula", role: .destructive) {
                        model.update { $0.formulas.removeAll { $0.id == formula.id } }
                        dismiss()
                    }
                }
            }
            .navigationTitle(isNew ? "New formula" : "Edit formula")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var f = formula
                        if f.name.trimmingCharacters(in: .whitespaces).isEmpty { f.name = "My loaf" }
                        model.update { s in
                            if let i = s.formulas.firstIndex(where: { $0.id == f.id }) { s.formulas[i] = f } else { s.formulas.append(f) }
                        }
                        dismiss()
                    }
                    .disabled(!blockingProblems.isEmpty)
                }
            }
        }
    }
}
