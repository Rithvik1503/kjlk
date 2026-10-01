import SwiftUI

/// A month grid with a dot under every day that has readings.
///
/// Rolled by hand rather than using `DatePicker`: the system picker can't show which days
/// have data, and it brings its own styling that fights the rest of the app. The logic that
/// matters — week start, month length, locale — all comes from `Calendar`, so it stays
/// correct in locales where the week starts on Monday or Saturday.
struct CalendarMonthView: View {
    @Binding var selectedDate: Date
    @Binding var visibleMonth: Date

    let daysWithData: Set<Date>
    var isLoading: Bool = false
    var onMonthChange: (Date) -> Void

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    var body: some View {
        VStack(spacing: 14) {
            monthHeader
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(Array(gridDays.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack {
            monthButton(symbol: "chevron.left", offset: -1)
                .accessibilityLabel("Previous month")

            Spacer(minLength: 8)

            VStack(spacing: 2) {
                Text(visibleMonth, format: .dateTime.month(.wide).year())
                    .font(.auraDisplay(17, weight: .semibold))
                    .foregroundStyle(Color.auraPrimaryText)
                    .contentTransition(.numericText())

                if isLoading {
                    Text("Loading…")
                        .font(.auraCaption)
                        .foregroundStyle(Color.auraTertiaryText)
                }
            }

            Spacer(minLength: 8)

            monthButton(symbol: "chevron.right", offset: 1)
                .accessibilityLabel("Next month")
                .disabled(isAtCurrentMonth)
                .opacity(isAtCurrentMonth ? 0.3 : 1)
        }
    }

    private func monthButton(symbol: String, offset: Int) -> some View {
        Button {
            guard let next = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else { return }
            Haptics.light()
            withAnimation(Motion.snappy) { visibleMonth = next }
            onMonthChange(next)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Color.auraSecondaryText)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Color.auraSurfaceRaised))
        }
        .buttonStyle(.plain)
    }

    private var isAtCurrentMonth: Bool {
        calendar.isDate(visibleMonth, equalTo: Date(), toGranularity: .month)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 4) {
            ForEach(Array(orderedWeekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.auraCaption)
                    .foregroundStyle(Color.auraTertiaryText)
                    .frame(maxWidth: .infinity)
            }
        }
        .accessibilityHidden(true)
    }

    /// `veryShortStandaloneWeekdaySymbols` starts at Sunday; rotate it to the locale's first day.
    private var orderedWeekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let offset = calendar.firstWeekday - 1
        guard offset > 0, offset < symbols.count else { return symbols }
        return Array(symbols[offset...] + symbols[..<offset])
    }

    // MARK: - Grid

    /// The month's days, padded at the front so the first lands in the right weekday column.
    private var gridDays: [Date?] {
        guard
            let interval = calendar.dateInterval(of: .month, for: visibleMonth),
            let dayCount = calendar.range(of: .day, in: .month, for: visibleMonth)?.count
        else { return [] }

        let firstWeekday = calendar.component(.weekday, from: interval.start)
        let leadingBlanks = (firstWeekday - calendar.firstWeekday + 7) % 7

        let days: [Date?] = (0..<dayCount).map {
            calendar.date(byAdding: .day, value: $0, to: interval.start)
        }
        return Array(repeating: nil, count: leadingBlanks) + days
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selectedDate)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > Date()
        let hasData = daysWithData.contains(calendar.startOfDay(for: day))

        return Button {
            guard !isFuture else { return }
            Haptics.selection()
            withAnimation(Motion.snappy) { selectedDate = day }
        } label: {
            VStack(spacing: 4) {
                Text(day, format: .dateTime.day())
                    .font(.auraNumeral(15, weight: isSelected || isToday ? .bold : .medium))
                    .foregroundStyle(dayColor(isSelected: isSelected, isToday: isToday, isFuture: isFuture))

                Circle()
                    .fill(hasData ? Color.auraCyan : Color.clear)
                    .frame(width: 4, height: 4)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 42)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(isSelected ? Color.auraPrimaryText : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(
                        isToday && !isSelected ? Color.auraCyan.opacity(0.5) : Color.clear,
                        lineWidth: 1
                    )
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isFuture)
        .accessibilityLabel(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
        .accessibilityValue(hasData ? "Has readings" : "No readings")
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func dayColor(isSelected: Bool, isToday: Bool, isFuture: Bool) -> Color {
        if isSelected { return .auraVoid }
        if isFuture { return .auraTertiaryText.opacity(0.4) }
        if isToday { return .auraCyan }
        return .auraPrimaryText
    }
}

#Preview("Calendar") {
    @Previewable @State var selected = Date()
    @Previewable @State var month = Date()

    let calendar = Calendar.current
    let withData = Set((1...20).compactMap {
        calendar.date(byAdding: .day, value: -$0, to: calendar.startOfDay(for: Date()))
    })

    ZStack {
        Color.auraBase.ignoresSafeArea()

        GlassCard {
            CalendarMonthView(
                selectedDate: $selected,
                visibleMonth: $month,
                daysWithData: withData,
                onMonthChange: { _ in }
            )
        }
        .padding()
    }
}
