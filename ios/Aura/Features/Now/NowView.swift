import SwiftUI

/// The whole app, more or less: one card, for one day.
///
/// The date stepper and the settings button live in the navigation bar rather than in a
/// hand-rolled header, so they get the system's own treatment — which on iOS 26 means Liquid
/// Glass, for free and without a single version check.
struct NowView: View {
    @EnvironmentObject private var store: AuraStore

    @State private var showingSettings = false
    @State private var showingInfo = false
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
                            footnoteDirection: footnoteDirection,
                            onInfo: { showingInfo = true }
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
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbarContent }
        }
        .task(id: store.selectedDate) { await store.loadSelectedDay() }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $showingInfo) {
            MetricInfoSheet(metric: .co2)
        }
        .sheet(isPresented: $showingDatePicker) {
            DayPickerSheet(selection: $store.selectedDate)
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button {
                store.step(days: -1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .accessibilityLabel("Previous day")
        }

        ToolbarItemGroup(placement: .topBarTrailing) {
            Button {
                store.step(days: 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!store.canGoForward)
            .accessibilityLabel("Next day")

            Button {
                showingDatePicker = true
            } label: {
                Image(systemName: "calendar")
            }
            .accessibilityLabel("Choose a date")

            Button {
                showingSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel("Settings")
        }
    }

    // MARK: - Copy

    private var navigationTitle: String {
        if store.isViewingToday { return "Today" }
        if Calendar.current.isDateInYesterday(store.selectedDate) { return "Yesterday" }
        return store.selectedDate.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
    }

    private var verdict: String {
        store.band?.label ?? "No reading"
    }

    /// Today gets the last hour's change; a past day gets its shape instead, since "the last
    /// hour" is meaningless once the day is over.
    private var footnote: String? {
        guard !store.readings.isEmpty else {
            return store.isLoading ? nil : "Nothing recorded on this day"
        }

        if store.isViewingToday {
            if let change = store.hourlyChange, abs(change) >= 10 {
                let amount = MetricKind.co2.format(abs(change))
                return "\(amount) ppm in the last hour"
            }
            if let recordedAt = store.current?.recordedAt {
                return "Updated \(recordedAt.formatted(.relative(presentation: .numeric)))"
            }
            return nil
        }

        guard let peak = store.peakCO2 else { return nil }
        let count = store.readings.count
        return "Peak \(MetricKind.co2.format(peak)) ppm · \(count) readings"
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
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.auraSurface)
        )
    }
}

/// A plain system date picker in a sheet. Nothing to customise — it already does the job.
struct DayPickerSheet: View {
    @Binding var selection: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "Date",
                selection: $selection,
                in: ...Date(),
                displayedComponents: .date
            )
            .datePickerStyle(.graphical)
            .padding(.horizontal)
            .navigationTitle("Choose a date")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Today") { selection = Date() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview("Now") {
    NowView()
        .environmentObject(AuraStore.preview())
        .preferredColorScheme(.dark)
}
