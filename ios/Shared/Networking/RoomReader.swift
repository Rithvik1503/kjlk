import Foundation

/// One fetch of "what is the room like right now", for the places that need it without a store.
///
/// The widget and the Siri intents both want the same thing: current values, resolved per
/// metric, from credentials in the keychain, with nothing kept afterwards. Neither has a
/// running app around it, so neither can borrow `AuraStore`.
enum RoomReader {
    /// Never throws. A failure comes back as a snapshot carrying a `notice`, because every
    /// caller has to render something either way.
    static func current() async -> RoomSnapshot {
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

            if readings.isEmpty {
                // Nothing in two hours — fall back to whatever the monitor last sent, so the
                // room shows as it was rather than going blank.
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
