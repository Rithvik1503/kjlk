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

    var body: some View {
        NavigationStack {
            ZStack {
                AuraBackground(tint: store.tint)

                ScrollView {
                    VStack(spacing: 16) {
                        CO2Card(
                            value: store.headlineCO2,
                            verdict: verdict,
                            tint: store.tint,
                            footnote: footnote,
                            footnoteDirection: footnoteDirection
                        )

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
            .navigationTitle("Home")
            .toolbar { toolbarContent }
        }
        .task(id: store.selectedDate) { await store.loadSelectedDay() }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(store)
        }
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
            in: ...Date(),
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

    private var verdict: String {
        store.band?.label ?? "No reading"
    }

    /// Today gets the last hour's change; a past day gets its peak instead, since "the last
    /// hour" is meaningless once the day is over.
    private var footnote: String? {
        guard !store.readings.isEmpty else {
            return store.isLoading ? nil : "Nothing recorded"
        }

        if store.isViewingToday {
            if let change = store.hourlyChange, abs(change) >= 10 {
                return "\(MetricKind.co2.format(abs(change))) ppm in the last hour"
            }
            if let recordedAt = store.current?.recordedAt {
                return "Updated \(recordedAt.formatted(.relative(presentation: .numeric)))"
            }
            return nil
        }

        guard let peak = store.peakCO2 else { return nil }
        return "Peak \(MetricKind.co2.format(peak)) ppm"
    }

    private var footnoteDirection: CO2Card.ChangeDirection? {
        guard store.isViewingToday, let change = store.hourlyChange, abs(change) >= 10 else {
            return nil
        }
        return change > 0 ? .up : .down
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
