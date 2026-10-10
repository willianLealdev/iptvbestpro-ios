import SwiftUI
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif

@main
struct IPTVBestProApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var app = AppState.shared
    @StateObject private var player = PlayerCenter.shared
    @Environment(\.scenePhase) private var phase

    init() { DeviceInfo.setup() }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(app)
                .environmentObject(player)
                .preferredColorScheme(.dark)
                .onAppear {
                    AudioSessionSetup.activate()
                    if app.route == .splash { app.boot() }
                    Purchases.shared.start()
                }
        }
        .onChange(of: phase) { p in
            // voltou para o app: confere a licença (no máximo 1x por minuto)
            if p == .active { Task { await app.licenseCheck(force: false) } }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        #if canImport(OneSignalFramework)
        // Notificações (iPhone e iPad): o mesmo OneSignal do app Android; o aparelho é identificado pelo ID do painel
        OneSignal.initialize(Config.oneSignalID, withLaunchOptions: launchOptions)
        OneSignal.login(DeviceID.value)
        NotificationCenter.default.addObserver(forName: .bpAskNotifications, object: nil, queue: .main) { _ in
            OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false)
        }
        #endif
        return true
    }

    #if os(iOS)
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        OrientationLock.mask
    }
    #endif
}

/// O player em tela cheia (vale para qualquer tela do app)
@MainActor
final class PlayerCenter: ObservableObject {
    static let shared = PlayerCenter()
    @Published var request: PlayRequest?
    @Published var multiscreen = false

    func play(_ r: PlayRequest) { request = r }
}

#if os(iOS)
enum OrientationLock {
    static var mask: UIInterfaceOrientationMask = .all
}
#endif
