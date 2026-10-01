import Foundation

/// Keychain items the app writes and the widget reads.
///
/// They live in one place because two processes agree on them: the app is the only writer,
/// the widget extension only ever reads. Everything here is in the shared access group.
enum SharedKeys {
    /// `SupabaseConfig` — project URL and anon key.
    static let config = "supabase.config"
    /// `SupabaseSession` — the tokens. Refreshed by whichever process needs it first.
    static let session = "supabase.session"
    /// The monitor the user picked in Settings, or absent for "whichever reported last".
    static let selectedDevice = "widget.selectedDevice"
}
