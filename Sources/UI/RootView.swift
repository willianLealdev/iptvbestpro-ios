import SwiftUI

struct RootView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter

    var body: some View {
        ZStack {
            BrandBackground()
            switch app.route {
            case .splash: SplashView()
            case .activation(let st, let msg): ActivationView(status: st, initialMessage: msg).id(st + msg)
            case .noList: NoListView()
            case .playlists: PlaylistsView(standalone: true)
            case .home: HomeView().id(app.homeToken)
            }
        }
        .overlay(alignment: .bottom) {
            if let tx = app.toast { ToastView(text: tx).transition(.opacity).allowsHitTesting(false) }
        }
        .animation(.easeInOut(duration: 0.2), value: app.toast)
        .fullScreenCover(item: $player.request) { r in
            PlayerScreen(request: r).environmentObject(app).environmentObject(player)
        }
        .fullScreenCover(isPresented: $player.multiscreen) {
            MultiScreenView().environmentObject(app).environmentObject(player)
        }
        .id(app.lang) // idioma trocado: monta as telas de novo no idioma novo
    }
}

struct SplashView: View {
    @EnvironmentObject var app: AppState
    var body: some View {
        VStack(spacing: UIScale.v(18, 22, 40)) {
            RemoteImage(url: app.brand.logo, fill: false, placeholder: "")
                .frame(width: UIScale.v(130, 170, 300), height: UIScale.v(130, 170, 300))
            if app.brand.showName {
                Text(app.brand.name).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white)
            }
            Spinner()
        }
    }
}

/// Aparelho ativo, mas sem lista: a revenda (ou o suporte) precisa adicionar a lista no painel
struct NoListView: View {
    @EnvironmentObject var app: AppState
    @State private var busy = false
    var body: some View {
        let up = app.status.s("upload_url")
        if !up.isEmpty { UploadListView(url: up) } else { plain }
    }
    private var plain: some View {
        ScrollView {
            CardBox {
                RemoteImage(url: app.brand.logo, fill: false, placeholder: "").frame(width: UIScale.v(80, 100, 160), height: UIScale.v(80, 100, 160))
                Text(t("no_list")).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                Text(t(app.isReseller ? "no_list_msg" : "no_list_customer")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.8)).multilineTextAlignment(.center)
                DeviceIDBox()
                if !app.supportWhatsApp.isEmpty { SupportContact(compact: true) }
                Button { busy = true; Task { await app.checkStatus(); busy = false } } label: {
                    HStack { if busy { ProgressView() }; Text(t("retry")) }
                }.buttonStyle(PillStyle(primary: true))
                NavigationLinkSettingsReset()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, UIScale.v(30, 60, 80))
        }
    }
}

/// Aparelho de servidor parceiro sem lista: QR code da página /lista; confere a cada 5 segundos se a lista chegou
struct UploadListView: View {
    @EnvironmentObject var app: AppState
    let url: String
    var body: some View {
        ScrollView {
            CardBox {
                RemoteImage(url: app.brand.logo, fill: false, placeholder: "").frame(width: UIScale.v(70, 90, 140), height: UIScale.v(70, 90, 140))
                Text(t("up_title")).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white).multilineTextAlignment(.center)
                Text(t("up_msg")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.8)).multilineTextAlignment(.center)
                QRCodeView(text: url).frame(width: UIScale.v(190, 230, 360), height: UIScale.v(190, 230, 360))
                Text(url.replacingOccurrences(of: "https://", with: "").components(separatedBy: "?").first ?? url)
                    .font(.system(size: UIScale.body, weight: .bold)).foregroundColor(.white)
                #if os(iOS)
                if let u = URL(string: url) { Link(t("up_open"), destination: u).buttonStyle(PillStyle(primary: true)) }
                #endif
                DeviceIDBox()
                HStack(spacing: 8) { ProgressView(); Text(t("up_wait")).foregroundColor(.white.opacity(0.7)) }
                NavigationLinkSettingsReset()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, UIScale.v(30, 60, 80))
        }
        .task {
            // confere a cada 5 segundos; quando a lista chega, entra no app
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 5_000_000_000)
                if Task.isCancelled { break }
                if let j = try? await API.panel("get_device_user", [:]),
                   (j as? [JObj] ?? []).contains(where: { !$0.s("user_name").isEmpty }) {
                    await app.loadPlaylists(chooser: false)
                    break
                }
            }
        }
    }
}

/// Botão "Resetar licença" (também nas telas sem lista)
struct NavigationLinkSettingsReset: View {
    @EnvironmentObject var app: AppState
    @State private var ask = false
    var body: some View {
        Button(t("lic_reset")) { ask = true }.buttonStyle(PillStyle())
            .alert(t("lic_reset"), isPresented: $ask) {
                Button(t("lic_cancel"), role: .cancel) {}
                Button(t("lic_yes"), role: .destructive) { Task { _ = await app.resetLicense() } }
            } message: { Text(t("lic_reset_msg")) }
    }
}

struct DeviceIDBox: View {
    var body: some View {
        VStack(spacing: 4) {
            Text(t("act_dev")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.7))
            Text(DeviceID.value).font(.system(size: UIScale.title * 0.85, weight: .bold, design: .monospaced)).foregroundColor(.white)
                .selectableText()
        }
        .padding(.vertical, UIScale.v(8, 10, 16)).padding(.horizontal, UIScale.v(16, 20, 32))
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.08)))
    }
}

/// Suporte: WhatsApp da revenda (ou do admin, para cliente direto). No celular abre o WhatsApp; na TV mostra o QR Code.
struct SupportContact: View {
    @EnvironmentObject var app: AppState
    var compact = false
    var body: some View {
        let wa = app.supportWhatsApp
        VStack(spacing: UIScale.v(8, 10, 18)) {
            if !app.status.s("support_name").isEmpty {
                Text(app.status.s("support_name")).font(.system(size: UIScale.body * 1.1, weight: .bold)).foregroundColor(.white)
            }
            if wa.isEmpty {
                Text(t(app.isReseller ? "sup_talk" : "sup_none")).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.8)).multilineTextAlignment(.center)
            } else {
                Text("WhatsApp: +" + wa).font(.system(size: UIScale.body)).foregroundColor(.white)
                if !app.status.s("support_note").isEmpty {
                    Text(app.status.s("support_note")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.75)).multilineTextAlignment(.center)
                }
                #if os(tvOS)
                QRCodeView(text: "https://wa.me/" + wa).frame(width: compact ? 220 : 320, height: compact ? 220 : 320)
                Text(t("sup_scan")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.75))
                #else
                if let u = URL(string: "https://wa.me/" + wa) {
                    Link(destination: u) { Label(t("open_whatsapp"), systemImage: "message.fill") }.buttonStyle(PillStyle(primary: true))
                }
                if !compact { QRCodeView(text: "https://wa.me/" + wa).frame(width: 170, height: 170) }
                #endif
            }
        }
    }
}
