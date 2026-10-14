import SwiftUI
import UIKit
import SwiftData
import FormaKit

/// Short first-run setup. Every step after the goal is optional and can be
/// changed later in Settings.
struct OnboardingView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(HealthService.self) private var health
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    enum Step: Int, CaseIterable {
        case welcome, goal, body, nutrition, steps, training, health
    }

    @State private var step: Step = .welcome
    @State private var movingForward = true

    @State private var goal: GoalDirection?
    @State private var unit: WeightUnit = .kilograms
    @State private var weightText = ""
    @State private var targetWeightText = ""
    @State private var caloriesText = ""
    @State private var proteinText = ""
    @State private var stepTarget = 8000.0
    @State private var trainingDays: Set<Int> = []
    @State private var connectingHealth = false

    var body: some View {
        VStack(spacing: 0) {
            if step != .welcome {
                progressBar
                    .padding(.horizontal, Theme.Spacing.xl)
                    .padding(.top, Theme.Spacing.m)
            }

            ZStack {
                stepContent
                    .id(step)
                    .transition(stepTransition)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)

            footer
                .padding(.horizontal, Theme.Spacing.xl)
                .padding(.bottom, Theme.Spacing.l)
        }
        .background(Theme.Palette.background)
        .onAppear { unit = settings.unit }
        .scrollDismissesKeyboard(.interactively)
    }

    private var stepTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: movingForward ? 24 : -24)),
            removal: .opacity.combined(with: .offset(x: movingForward ? -24 : 24))
        )
    }

    private var progressBar: some View {
        let total = Step.allCases.count - 1
        return HStack(spacing: 4) {
            ForEach(1...total, id: \.self) { index in
                Capsule()
                    .fill(index <= step.rawValue ? Theme.Palette.accent : Theme.Palette.fill)
                    .frame(height: 4)
            }
        }
        .motion(Motion.standard, value: step)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Step \(step.rawValue) of \(total)")
    }

    // MARK: Steps

    @ViewBuilder
    private var stepContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                switch step {
                case .welcome: welcome
                case .goal: goalStep
                case .body: bodyStep
                case .nutrition: nutritionStep
                case .steps: stepsStep
                case .training: trainingStep
                case .health: healthStep
                }
            }
            .padding(.horizontal, Theme.Spacing.xl)
            .padding(.top, Theme.Spacing.xl)
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            Spacer(minLength: 40)
            Image(systemName: "figure.strengthtraining.traditional")
                .font(.system(size: 52, weight: .semibold))
                .foregroundStyle(Theme.Palette.accent)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                Text("Welcome to Forma")
                    .font(.largeTitle.weight(.bold))
                Text("Training, food, weight and daily movement in one place — quick to log, and clear about what's changing over time.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: Theme.Spacing.l) {
                feature("bolt", "Fast logging", "Sets, meals and weigh-ins in a few taps.")
                feature("chart.line.uptrend.xyaxis", "Honest progress", "Trends that smooth out daily noise, without inventing data.")
                feature("lock", "Private by default", "No account. Your data stays on this iPhone.")
            }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: Theme.Spacing.m) {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .foregroundStyle(Theme.Palette.accent)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private var goalStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            stepTitle("What's your main goal?", "This shapes how progress is described. You can change it any time.")
            ForEach(GoalDirection.allCases) { option in
                Button {
                    Haptics.selection()
                    Motion.perform(Motion.quick) { goal = option }
                } label: {
                    HStack(spacing: Theme.Spacing.m) {
                        Image(systemName: option.symbol)
                            .font(.headline)
                            .frame(width: 36, height: 36)
                            .background(Circle().fill(goal == option ? Color.white.opacity(0.2) : Theme.Palette.accent.opacity(0.12)))
                        VStack(alignment: .leading, spacing: 2) {
                            Text(option.name).font(.headline)
                            Text(goalDescription(option))
                                .font(.subheadline)
                                .opacity(0.8)
                        }
                        Spacer()
                        if goal == option {
                            Image(systemName: "checkmark.circle.fill").font(.title3)
                        }
                    }
                    .foregroundStyle(goal == option ? Color.white : Color.primary)
                    .padding(Theme.Spacing.l)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous)
                            .fill(goal == option ? Theme.Palette.accent : Theme.Palette.surface)
                    )
                }
                .buttonStyle(PressableStyle())
                .accessibilityAddTraits(goal == option ? .isSelected : [])
            }
        }
    }

    private func goalDescription(_ goal: GoalDirection) -> String {
        switch goal {
        case .lose: return "Bring body weight down gradually"
        case .maintain: return "Stay within a comfortable range"
        case .gain: return "Build up, often alongside strength training"
        }
    }

    private var bodyStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            stepTitle("Units and weight", "Your current weight is optional, and it's only used for your trend.")
            Picker("Units", selection: $unit) {
                ForEach(WeightUnit.allCases) { Text($0.name).tag($0) }
            }
            .pickerStyle(.segmented)
            inputRow("Current weight", text: $weightText, unit: unit.symbol)
            if goal == .lose || goal == .gain {
                inputRow("Target weight", text: $targetWeightText, unit: unit.symbol)
            }
        }
    }

    private var nutritionStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            stepTitle("Nutrition targets", "Optional. Use numbers you've chosen yourself or with a professional. Forma doesn't prescribe targets.")
            inputRow("Calories", text: $caloriesText, unit: "kcal")
            inputRow("Protein", text: $proteinText, unit: "g")
            if let kg = NumberParsing.decimal(from: weightText).map(unit.toKilograms) {
                let suggestion = (kg * 1.6).rounded()
                Button {
                    proteinText = Format.grams(suggestion)
                    Haptics.selection()
                } label: {
                    Text("Use \(Format.grams(suggestion)) g protein (1.6 g per kg body weight)")
                        .font(.footnote.weight(.medium))
                }
                .buttonStyle(.borderless)
            }
            FootnoteText(text: "You can track carbs and fat too — turn them on in Nutrition targets later.")
        }
    }

    private var stepsStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            stepTitle("Daily steps", "Pick a target that fits your days. There's no single right number.")
            VStack(spacing: Theme.Spacing.m) {
                Text(Format.steps(Int(stepTarget)))
                    .font(.metric(.largeTitle))
                    .numericStyle()
                    .contentTransition(.numericText(value: stepTarget))
                    .frame(maxWidth: .infinity)
                Slider(value: $stepTarget, in: 2000...25000, step: 500)
                    .tint(Metric.steps.color)
                    .accessibilityValue("\(Format.steps(Int(stepTarget))) steps")
            }
            .padding(Theme.Spacing.l)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
    }

    private var trainingStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            stepTitle("Training days", "Optional. Planned days appear on Today and in your weekly review. Training on other days still counts.")
            WeekdayPicker(selection: $trainingDays, tint: Metric.training.color)
            Text(trainingDays.isEmpty ? "No days planned" : "\(trainingDays.count) day\(trainingDays.count == 1 ? "" : "s") a week")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var healthStep: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.l) {
            stepTitle("Apple Health", healthIntro)
            if health.status != .unavailable {
                VStack(alignment: .leading, spacing: Theme.Spacing.m) {
                    feature("scalemass", "Weigh-ins from your scale", "Import body weight recorded by smart scales and other apps.")
                    feature("figure.walk", "Steps from iPhone and Watch", "Daily totals, merged by Health so nothing is counted twice.")
                    feature("hand.raised", "You stay in control", "Forma only asks for what it uses. Change access any time in the Health app.")
                }
                if health.status == .connected {
                    Label("Connected", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .foregroundStyle(Metric.steps.color)
                }
            }
        }
    }

    private var healthIntro: String {
        health.status == .unavailable
            ? "Apple Health isn't available on this device. Forma works fully with manual entry."
            : "Optional. Connect to bring in steps and weigh-ins automatically."
    }

    private func stepTitle(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.s) {
            Text(title)
                .font(.largeTitle.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            Text(subtitle)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func inputRow(_ title: String, text: Binding<String>, unit: String) -> some View {
        HStack {
            Text(title).font(.body.weight(.medium))
            Spacer()
            TextField("—", text: text)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.title3.weight(.semibold))
                .numericStyle()
                .frame(maxWidth: 120)
                .accessibilityLabel(title)
            Text(unit)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .leading)
        }
        .padding(Theme.Spacing.l)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
    }

    // MARK: Footer

    @ViewBuilder
    private var footer: some View {
        VStack(spacing: Theme.Spacing.s) {
            switch step {
            case .welcome:
                Button("Get Started") { advance() }
                    .buttonStyle(PrimaryButtonStyle())
            case .goal:
                Button("Continue") { advance() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(goal == nil)
                Button("Skip for now") {
                    goal = nil
                    advance()
                }
                .buttonStyle(.borderless)
                .frame(minHeight: Theme.target)
            case .health:
                if health.status == .notConnected {
                    Button {
                        connectingHealth = true
                        Task {
                            await health.connect()
                            connectingHealth = false
                            finish()
                        }
                    } label: {
                        if connectingHealth { ProgressView().tint(.white) } else { Text("Connect Apple Health") }
                    }
                    .buttonStyle(PrimaryButtonStyle(tint: .pink))
                    Button("Not Now") { finish() }
                        .buttonStyle(.borderless)
                        .frame(minHeight: Theme.target)
                } else {
                    Button("Start Using Forma") { finish() }
                        .buttonStyle(PrimaryButtonStyle())
                }
            default:
                Button("Continue") { advance() }
                    .buttonStyle(PrimaryButtonStyle())
                HStack {
                    Button("Back") { goBack() }
                    Spacer()
                    Button("Skip") { advance() }
                }
                .buttonStyle(.borderless)
                .frame(minHeight: Theme.target)
            }
        }
    }

    private func advance() {
        guard let next = Step(rawValue: step.rawValue + 1) else { return }
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        movingForward = true
        Motion.perform(Motion.standard) { step = next }
    }

    private func goBack() {
        guard let previous = Step(rawValue: step.rawValue - 1) else { return }
        movingForward = false
        Motion.perform(Motion.standard) { step = previous }
    }

    /// Saves everything collected and enters the app.
    private func finish() {
        let today = DayKey.today()
        if let value = NumberParsing.decimal(from: weightText) {
            let kg = unit.toKilograms(value)
            if HealthImportDeduplicator.plausibleRange.contains(kg) {
                context.insert(WeightEntry(kilograms: kg, measuredAt: Date()))
            }
        }
        if let calories = NumberParsing.decimal(from: caloriesText), calories > 0 {
            TargetStore.set(.calories, to: calories, effectiveFrom: today, in: context)
        }
        if let protein = NumberParsing.decimal(from: proteinText), protein > 0 {
            TargetStore.set(.protein, to: protein, effectiveFrom: today, in: context)
        }
        TargetStore.set(.steps, to: stepTarget, effectiveFrom: today, in: context)
        try? context.save()

        let targetKg = NumberParsing.decimal(from: targetWeightText).map(unit.toKilograms)
        settings.update { values in
            values.weightUnit = unit
            values.goal = BodyGoal(direction: goal, targetKg: (goal == .lose || goal == .gain) ? targetKg : nil)
            values.trainingDays = trainingDays
            values.onboardingCompleted = true
        }
        Haptics.success()
        Task {
            await health.refreshSteps(force: true)
            await health.importWeights(into: context)
        }
    }
}
