import SwiftUI

/// History: every sensor over a week, a month, or six months.
///
/// The window picker drives every row at once, and stepping the header moves a whole window
/// at a time rather than a day — the point of this screen is the shape, not a single reading.
struct TrendsView: View {
    @EnvironmentObject private var store: AuraStore
    /// Owned by `AuraStore`, so it survives tab switches and shares the one client.
    @ObservedObject var trends: TrendsStore

    @State private var showingSettings = false
    @State private var showingDatePicker = false

    private var anchor: Date { store.selectedDate }

    var body: some View {
        NavigationStack {
            ZStack {
                // The same backdrop Home carries, on the same tint, so switching tabs doesn't
                // change the room's colour underfoot.
                AuraBackground(tint: store.tint)

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        RangeTogglePill(selection: $trends.window)
                            .padding(.horizontal, 16)
                            .padding(.top, 4)

                        Text("ATMOSPHERE")
                            .font(.auraMono(13))
                            .tracking(3)
                            .foregroundStyle(Color.auraPrimaryText)
                            .padding(.horizontal, 16)
                            .padding(.top, 26)
                            .padding(.bottom, 14)
                            .accessibilityAddTraits(.isHeader)

                        content
                            .padding(.horizontal, 16)
                            .padding(.bottom, 32)
                    }
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Trends")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
        }
        .task(id: reloadKey) { await trends.load(endingAt: anchor) }
        .sheet(isPresented: $showingSettings) {
            SettingsView().environmentObject(store)
        }
    }

    /// Reloads when either the window or the anchor changes.
    private var reloadKey: String {
        "\(trends.window.rawValue)-\(anchor.timeIntervalSince1970.rounded())"
    }

    @ViewBuilder
    private var content: some View {
        if trends.needsMigration {
            notice(
                title: "Trends needs one more migration",
                detail: "Run supabase/migrations/0003_metric_buckets.sql in the SQL editor. It aggregates history in Postgres — six months of readings is a quarter of a million rows."
            )
        } else if let message = trends.errorMessage {
            notice(title: "Couldn't load history", detail: message)
        } else {
            VStack(spacing: 10) {
                ForEach(MetricKind.trendOrder) { metric in
                    TrendRow(
                        metric: metric,
                        window: trends.window,
                        slots: trends.slots(endingAt: anchor).map {
                            (date: $0.date, value: $0.bucket?.value(for: metric))
                        },
                        windowAverage: trends.average(for: metric, endingAt: anchor),
                        observedMax: trends.observedMax(for: metric)
                    )
                }
            }
        }
    }

    private func notice(title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.auraPrimaryText)

            Text(detail)
                .font(.footnote)
                .foregroundStyle(Color.auraMutedText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.auraCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
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
                store.selectedDate = trends.step(-1, from: anchor)
            } label: {
                Image(systemName: "chevron.left")
            }
            .disabled(!store.canGoBack(from: anchor))
            .accessibilityLabel("Previous \(trends.window.title.lowercased())")

            Button {
                showingDatePicker = true
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .semibold))
                    Text(trends.rangeLabel(endingAt: anchor))
                        .font(.auraMono(11))
                        .tracking(0.8)
                }
            }
            .accessibilityLabel("Choose a date")
            .accessibilityValue(trends.rangeLabel(endingAt: anchor))
            .popover(isPresented: $showingDatePicker) {
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
                .presentationCompactAdaptation(.popover)
            }

            Button {
                store.selectedDate = trends.step(1, from: anchor)
            } label: {
                Image(systemName: "chevron.right")
            }
            .disabled(!trends.canStepForward(from: anchor))
            .accessibilityLabel("Next \(trends.window.title.lowercased())")
        }
    }
}
