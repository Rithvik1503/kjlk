import Foundation
import UIKit
import UserNotifications

/// Registers this installation with APNs and tells Supabase where to reach it.
///
/// This is what makes alerts arrive with the app closed. The local notifier beside it still
/// runs — it is faster while the app is open, and it works with no server involvement — but
/// it can only fire while the app is alive. The scheduled job behind this one does not care.
@MainActor
final class PushRegistrar: NSObject, ObservableObject {
    /// The token APNs last handed us, hex-encoded the way Apple's servers expect it.
    @Published private(set) var token: String?
    @Published private(set) var lastError: String?

    private let client: SupabaseClient
    /// Set while there is no session to attach a token to, so registration can be retried
    /// the moment one appears.
    private var pendingToken: String?

    init(client: SupabaseClient) {
        self.client = client
    }

    /// Asks iOS for a token. Safe to call repeatedly — iOS answers from cache after the first.
    func start() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func didRegister(deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        token = hex
        Task { await upload(hex) }
    }

    func didFail(_ error: any Error) {
        // Expected in the Simulator on older iOS, and whenever the device is offline at launch.
        lastError = error.localizedDescription
    }

    /// Called once the user signs in, for a token that arrived before there was an account.
    func retryPendingUpload() async {
        guard let pendingToken else { return }
        await upload(pendingToken)
    }

    private func upload(_ hex: String) async {
        do {
            try await client.registerPushDevice(token: hex, environment: Self.environment)
            pendingToken = nil
            lastError = nil
        } catch SupabaseError.notSignedIn {
            // The token outlives the session; hold it and try again after sign-in.
            pendingToken = hex
        } catch {
            pendingToken = hex
            lastError = error.localizedDescription
        }
    }

    func forget() async {
        guard let token else { return }
        try? await client.removePushDevice(token: token)
    }

    /// Which APNs host can reach this build.
    ///
    /// A token issued to a development build is only valid against Apple's sandbox, and one
    /// from TestFlight or the App Store only against production. Sending to the wrong host
    /// gets the token rejected as invalid, which is why the server stores this alongside it.
    private static var environment: String {
        #if DEBUG
        "sandbox"
        #else
        "production"
        #endif
    }
}

/// The one thing that still needs UIKit: APNs hands tokens to the app delegate, and SwiftUI
/// has no equivalent.
final class AuraAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    /// Set by `AuraApp` as soon as the store exists.
    weak var registrar: PushRegistrar?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in registrar?.didRegister(deviceToken: deviceToken) }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: any Error
    ) {
        Task { @MainActor in registrar?.didFail(error) }
    }

    /// Shows a push that lands while Aura is open rather than swallowing it — the app may well
    /// be sitting on yesterday, or on Trends, when the alert is about right now.
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
