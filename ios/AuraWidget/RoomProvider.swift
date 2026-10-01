import Foundation
import WidgetKit

struct RoomEntry: TimelineEntry {
    let date: Date
    let snapshot: RoomSnapshot
}

/// Fetches the room's current state straight from Supabase.
///
/// The widget holds nothing of its own: credentials come from the shared keychain the app
/// writes, and the numbers come down the wire each time the system asks for a timeline. That
/// keeps the promise the app makes — no readings are written to the phone.
struct RoomProvider: TimelineProvider {
    /// WidgetKit budgets an extension to a few dozen refreshes a day, so asking every quarter
    /// of an hour is about as often as is worth asking for.
    private static let refreshInterval: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> RoomEntry {
        RoomEntry(date: Date(), snapshot: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (RoomEntry) -> Void) {
        // The gallery renders before the user has picked anything; show the sample there
        // rather than an error or an empty frame.
        guard !context.isPreview else {
            return completion(RoomEntry(date: Date(), snapshot: .preview))
        }
        Task {
            completion(RoomEntry(date: Date(), snapshot: await load()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoomEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = RoomEntry(date: now, snapshot: await load())
            let next = now.addingTimeInterval(Self.refreshInterval)
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    private func load() async -> RoomSnapshot {
        let client = SupabaseClient()
        await client.restore()

        guard await client.isConfigured else {
            return RoomSnapshot(notice: "Open Aura to connect your project.")
        }
        guard await client.isSignedIn else {
            return RoomSnapshot(notice: "Open Aura to sign in.")
        }

        let deviceID = Keychain.string(for: SharedKeys.selectedDevice)
        let now = Date()

        do {
            // A window rather than the single newest row: one sensor dropping out of one
            // sample shouldn't take its figure down with it.
            let readings = try await client.readings(
                from: now.addingTimeInterval(-2 * 60 * 60),
                to: now,
                deviceID: deviceID,
                limit: 240
            )

            guard !readings.isEmpty else {
                // Nothing in two hours — fall back to whatever the monitor last sent, so the
                // widget shows the room as it was rather than going blank.
                guard let last = try await client.latestReading(deviceID: deviceID) else {
                    return RoomSnapshot(notice: "No readings yet.")
                }
                return .resolved(from: [last])
            }
            return .resolved(from: readings)
        } catch SupabaseError.notSignedIn {
            return RoomSnapshot(notice: "Open Aura to sign in again.")
        } catch {
            return RoomSnapshot(notice: "Couldn't reach Supabase.")
        }
    }
}
