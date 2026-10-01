import SwiftUI

/// The whole app, more or less: one card, for one day.
///
/// The settings button, the day stepper and the date picker all live in the navigation bar
/// rather than in a hand-rolled header, so they get the system's own treatment — which on
/// iOS 26 means Liquid Glass, for free and without a single version check.
struct NowView: View {
    @EnvironmentObject private var store: AuraStore

    @State private var showingSettings = false
    @State private var showingDatePicker = false
    @State private var chartMetric: MetricKind?

    var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground(tint: store.tint)

                ScrollView {
                    VStack(spacing: 14) {
                        ThermalCard(
                            temperature: store.value(for: .temperature),
                            dayAverage: store.dayAverage(of: .temperature)
                        )

                        atmosphereSection

                        footer

                        if let message = store.errorMessage {
                            errorRow(message)
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 8)
                }
                .scrollIndicators(.hidden)
                .refreshable { await store.loadSelectedDay() }
            }
            .navigationTitle(store.currentZone ?? "Home")
            .toolbar { toolbarContent }
        }
        .task(id: store.selectedDate) { await store.loadSelectedDay() }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(item: $chartMetric) { metric in
            MetricChartSheet(
                metric: metric,
                readings: store.readings,
                day: store.selectedDate,
                range: store.scale(for: metric)
            )
        }
    }

    private var atmosphereSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Atmosphere")
                .font(.headline)
                .foregroundStyle(Color.auraPrimaryText)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityAddTraits(.isHeader)

            VStack(spacing: 14) {
                ForEach([MetricKind.co2, .humidity, .light]) { metric in
                    MetricCard(
                        metric: metric,
                        value: store.value(for: metric),
                        range: store.scale(for: metric),
                        change: store.hourlyChange(for: metric),
                        isAverage: !store.isViewingToday
                    ) {
                        chartMetric = metric
                    }
                }
            }
        }
        .padding(.top, 6)
    }

    /// Freshness, kept to the bottom of the page — useful to check, not worth leading with.
    @ViewBuilder
    private var footer: some View {
        if let recordedAt = store.lastReadingAt {
            Text(footerText(for: recordedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .padding(.top, 6)
                .accessibilityLabel("Last updated \(recordedAt.formatted(.relative(presentation: .numeric)))")
        }
    }

    private func footerText(for date: Date) -> String {
        // On a past day a relative stamp would read "3 days ago", which says nothing about
        // the day being shown. The clock time does.
        guard store.isViewingToday else {
            return "Last reading at \(date.formatted(.dateTime.hour().minute()))"
        }
        return "Last updated \(date.formatted(.relative(presentation: .numeric)))"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                store.step(days: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!store.canGoBack(from: store.selectedDate))
            .accessibilityLabel("Previous day")

            Button {
                showingDatePicker = true
            } label: {
                Text(dateLabel)
                    .font(.subheadline.weight(.medium))
                    .monospacedDigit()
            }
            .accessibilityLabel("Choose a date")
            .accessibilityValue(store.selectedDate.formatted(date: .complete, time: .omitted))
            .popover(isPresented: $showingDatePicker) {
                datePicker
            }

            Button {
                store.step(days: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!store.canGoForward)
            .accessibilityLabel("Next day")
        }
    }

    private var datePicker: some View {
        DatePicker(
            "Date",
            selection: $store.selectedDate,
            in: store.earliestSelectableDate...Date(),
            displayedComponents: .date
        )
        .datePickerStyle(.graphical)
        .labelsHidden()
        .frame(width: 320, height: 340)
        .padding(.horizontal, 8)
        // Without this a popover becomes a sheet on iPhone, which is not what a date
        // button attached to a toolbar wants.
        .presentationCompactAdaptation(.popover)
    }

    // MARK: - Copy

    private var dateLabel: String {
        store.selectedDate.formatted(.dateTime.day().month(.abbreviated))
    }

    private func errorRow(_ message: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)

            Text(message)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 4)

            Button("Dismiss") { store.dismissError() }
                .font(.footnote)
                .buttonStyle(.plain)
                .foregroundStyle(.tint)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.auraCard)
        )
    }
}

#Preview("Now") {
    NowView()
        .environmentObject(AuraStore.preview())
        .preferredColorScheme(.dark)
}
