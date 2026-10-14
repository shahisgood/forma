import SwiftUI
import FormaKit

// MARK: - Surfaces

/// The primary content container. Flat, continuous corners, no border, so
/// cards read as one calm layer on the grouped background.
struct Card<Content: View>: View {
    var padding: CGFloat = Theme.Spacing.l
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.m) {
            content
        }
        .padding(padding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }
}

/// Title row used at the top of cards: metric icon, title, optional trailing content.
struct CardHeader<Trailing: View>: View {
    let title: String
    var symbol: String?
    var tint: Color = .secondary
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(spacing: Theme.Spacing.s) {
            if let symbol {
                Image(systemName: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                    .accessibilityHidden(true)
            }
            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: Theme.Spacing.s)
            trailing
        }
    }
}

extension CardHeader where Trailing == EmptyView {
    init(title: String, symbol: String? = nil, tint: Color = .secondary) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.trailing = EmptyView()
    }
}

/// Section title for scrolling screens.
struct SectionTitle: View {
    let title: String
    var subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title3.weight(.semibold))
                .accessibilityAddTraits(.isHeader)
            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.top, Theme.Spacing.s)
    }
}

// MARK: - Buttons

/// Filled, full-width primary action.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.accent
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: Theme.largeTarget)
            .padding(.horizontal, Theme.Spacing.l)
            .background(tint.opacity(isEnabled ? 1 : 0.35), in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Tinted secondary action.
struct SecondaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.accent
    var fullWidth = true

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(maxWidth: fullWidth ? .infinity : nil, minHeight: Theme.target)
            .padding(.horizontal, Theme.Spacing.l)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Subtle press feedback for tappable cards and rows.
struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.98

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? scale : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Round icon button used for steppers and quick actions.
struct CircleIconButtonStyle: ButtonStyle {
    var tint: Color = Theme.Palette.accent
    var size: CGFloat = Theme.target
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.semibold))
            .foregroundStyle(filled ? .white : tint)
            .frame(width: size, height: size)
            .background(Circle().fill(filled ? tint : tint.opacity(0.12)))
            .contentShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
    }
}

/// Compact quick-action tile (icon over label).
struct QuickActionButton: View {
    let title: String
    let symbol: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Spacing.s) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(height: 24)
                Text(title)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, minHeight: 72)
            .background(Theme.Palette.surface, in: RoundedRectangle(cornerRadius: Theme.Radius.inner, style: .continuous))
        }
        .buttonStyle(PressableStyle(scale: 0.96))
        .accessibilityLabel(title)
    }
}

// MARK: - Progress

/// Ring progress with a soft track. Values above 1 show a completed ring.
struct ProgressRing: View {
    var progress: Double
    var color: Color
    var lineWidth: CGFloat = 8

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.16), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .motion(Motion.progress, value: progress)
        .accessibilityHidden(true)
    }
}

/// Horizontal capsule progress bar. Overflow is shown with a marker rather than
/// a warning colour, so exceeding a target is not framed as failure.
struct CapsuleProgress: View {
    var progress: Double?
    var color: Color
    var height: CGFloat = 8

    var body: some View {
        GeometryReader { geo in
            let value = max(0, min(1, progress ?? 0))
            ZStack(alignment: .leading) {
                Capsule().fill(color.opacity(0.15))
                Capsule()
                    .fill(color)
                    .frame(width: max(value > 0 ? height : 0, geo.size.width * value))
            }
        }
        .frame(height: height)
        .motion(Motion.progress, value: progress)
        .accessibilityHidden(true)
    }
}

// MARK: - Values

/// A labelled numeric value.
struct StatValue: View {
    let value: String
    var unit: String?
    let label: String
    var tint: Color = .primary
    var size: Font = .metric(.title2)

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(size)
                    .foregroundStyle(tint)
                    .numericStyle()
                    .contentTransition(.numericText())
                if let unit {
                    Text(unit)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Small pill describing provenance or status. Always includes text, so meaning
/// never depends on colour alone.
struct TagBadge: View {
    let text: String
    var symbol: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 3) {
            if let symbol {
                Image(systemName: symbol).imageScale(.small)
            }
            Text(text)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Personal-record marker.
struct RecordBadge: View {
    var text = "PR"

    var body: some View {
        TagBadge(text: text, symbol: "trophy.fill", tint: Theme.Palette.record)
            .accessibilityLabel("Personal record")
    }
}

// MARK: - Empty states

/// Inviting starting point in place of empty zeros.
struct EmptyStateCard: View {
    let symbol: String
    let title: String
    let message: String
    var tint: Color = Theme.Palette.accent
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        Card {
            HStack(alignment: .top, spacing: Theme.Spacing.m) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                    .frame(width: 40, height: 40)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(SecondaryButtonStyle(tint: tint))
            }
        }
    }
}

/// Inline note used for honest caveats under charts and summaries.
struct FootnoteText: View {
    let text: String
    var symbol: String = "info.circle"

    var body: some View {
        Label {
            Text(text).fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: symbol)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Selection controls

/// Seven tappable day circles for choosing weekdays.
struct WeekdayPicker: View {
    @Binding var selection: Set<Int>
    var tint: Color = Theme.Palette.accent
    var allowsMultiple = true

    private var calendar: Calendar { .current }

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekdays.ordered(calendar: calendar), id: \.self) { weekday in
                let selected = selection.contains(weekday)
                Button {
                    Haptics.selection()
                    Motion.perform(Motion.quick) {
                        if allowsMultiple {
                            if selected { selection.remove(weekday) } else { selection.insert(weekday) }
                        } else {
                            selection = [weekday]
                        }
                    }
                } label: {
                    Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(selected ? .white : .primary)
                        .frame(maxWidth: .infinity, minHeight: 40)
                        .background(Circle().fill(selected ? tint : Theme.Palette.fill))
                }
                .buttonStyle(PressableStyle(scale: 0.92))
                .accessibilityLabel(calendar.weekdaySymbols[weekday - 1])
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// Segmented chart-range control.
struct RangePicker: View {
    @Binding var range: ChartRange
    var options: [ChartRange] = ChartRange.allCases

    var body: some View {
        Picker("Range", selection: $range) {
            ForEach(options) { option in
                Text(option.rawValue)
                    .accessibilityLabel(option.accessibilityName)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
    }
}
