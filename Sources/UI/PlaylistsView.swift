import SwiftUI

/// Listas do aparelho (as que a revenda adicionou no painel). O cliente escolhe qual usar.
struct PlaylistsView: View {
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    var standalone = false
    @State private var loading = false

    private var backAction: (() -> Void)? {
        if !standalone { return { dismiss() } }
        if app.login != nil { return { app.route = .home } }
        return nil
    }

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("playlist"), onBack: backAction)
            ScrollView {
                LazyVStack(spacing: UIScale.v(8, 10, 18)) {
                    if loading { Spinner().padding() }
                    ForEach(Array(app.playlists.enumerated()), id: \.offset) { _, p in
                        let on = app.playlist?.s("id") == p.s("id") && app.login != nil
                        Button {
                            Task { await app.enter(p, fromChooser: app.playlist?.s("id") != p.s("id")) }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "list.bullet.rectangle").font(.system(size: UIScale.body * 1.2))
                                Text(p.s("playlist_name").isEmpty ? p.s("user_name") : p.s("playlist_name"))
                                    .font(.system(size: UIScale.body, weight: .semibold)).lineLimit(1)
                                Spacer()
                                if on { Text("● " + t("connected")).font(.system(size: UIScale.small, weight: .bold)).foregroundColor(.green) }
                            }
                        }
                        .buttonStyle(RowStyle(selected: on))
                    }
                }
                .padding(UIScale.pad)
                .frame(maxWidth: UIScale.v(.infinity, 900, 1300))
                .frame(maxWidth: .infinity)
            }
        }
        .task {
            if !standalone {
                loading = true
                await app.loadPlaylists(chooser: true)
                loading = false
            }
        }
        #if os(tvOS)
        .onExitCommand { if standalone { if app.login != nil { app.route = .home } } else { dismiss() } }
        #endif
    }
}
