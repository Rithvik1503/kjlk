import Foundation
import WidgetKit

struct RoomEntry: TimelineEntry {
    let date: Date
    let snapshot: RoomSnapshot
}

/// Fetches the room's current state straight from Supabase, through `RoomReader` — the same
/// path the Siri intents take.
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
            completion(RoomEntry(date: Date(), snapshot: await RoomReader.current()))
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RoomEntry>) -> Void) {
        Task {
            let now = Date()
            let entry = RoomEntry(date: now, snapshot: await RoomReader.current())
            completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshInterval))))
        }
    }
}
