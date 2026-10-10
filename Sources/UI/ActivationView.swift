import SwiftUI

/// Ativação: código da revenda (6 letras) ou da assinatura (8 números).
/// Cliente direto (sem revenda) também pode assinar pela Apple — aparelho de revenda nunca vê a compra.
struct ActivationView: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var iap = Purchases.shared
    let status: String
    let initialMessage: String

    @State private var code = ""
    @State private var error = ""
    @State private var busy = false
    @FocusState private var codeFocused: Bool
    let poll = Timer.publish(every: 5, on: .main, in: .common).autoconnect()

    var waiting: Bool { status == "pending" }
    var expired: Bool { status == "expired" }
    var showPurchase: Bool { !waiting && app.canPurchase }

    var body: some View {
        ScrollView {
            CardBox {
                RemoteImage(url: app.brand.logo, fill: false, placeholder: "")
                    .frame(width: UIScale.v(80, 100, 170), height: UIScale.v(80, 100, 170))
                Text(app.brand.name).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white)
                Text(t(waiting ? "act_wait" : (expired ? "act_expired" : "act_title")))
                    .font(.system(size: UIScale.title * 0.8, weight: .semibold)).foregroundColor(app.brand.accent).multilineTextAlignment(.center)
                Text(t(waiting ? "act_wait_msg" : (expired ? (app.isReseller ? "act_expired_msg" : "act_expired_customer") : "act_msg")))
                    .font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.85)).multilineTextAlignment(.center)
                DeviceIDBox()

                if waiting {
                    Spinner().padding(.vertical, 6)
                } else {
                    TextField(t("act_code_ph"), text: $code)
                        .font(.system(size: UIScale.title, weight: .bold, design: .monospaced))
                        .multilineTextAlignment(.center)
                        .textInputAutocapitalization(.characters)
                        .disableAutocorrection(true)
                        .focused($codeFocused)
                        .onSubmit { submit() }
                        .onChange(of: code) { v in
                            let c = String(v.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(8))
                            if c != v { code = c }
                        }
                        .padding(.vertical, UIScale.v(10, 12, 20))
                        .padding(.horizontal, 12)
                        .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(app.brand.accent.opacity(codeFocused ? 1 : 0.4), lineWidth: 2))
                        .frame(maxWidth: UIScale.v(320, 380, 640))
                }
                if !error.isEmpty {
                    Text(error).font(.system(size: UIScale.body)).foregroundColor(Color(red: 1, green: 0.45, blue: 0.45)).multilineTextAlignment(.center)
                }
                VStack(spacing: UIScale.v(10, 12, 22)) {
                    if !waiting {
                        Button { submit() } label: { HStack { if busy { ProgressView() }; Text(t("act_btn")) } }
                            .buttonStyle(PillStyle(primary: true)).disabled(busy)
                    }
                    Button(t("act_check")) { busy = true; Task { await app.checkStatus(); busy = false } }.buttonStyle(PillStyle())
                    if waiting {
                        Button(t("act_other")) { app.activation("unlinked", "") }.buttonStyle(PillStyle())
                    } else {
                        Text(t("act_help")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.7)).multilineTextAlignment(.center)
                    }
                }
                if showPurchase { PurchaseBox(error: $error) }
                if expired || waiting { SupportContact(compact: true) }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, UIScale.v(20, 50, 60))
        }
        .onAppear { error = initialMessage }
        .onReceive(poll) { _ in
            // aguardando a revenda liberar: confere sozinho a cada 5 segundos
            guard waiting else { return }
            Task {
                guard let o = try? await API.panelFirst("device_status") else { return }
                if o.s("status") == "active" { app.saveStatus(o); await app.loadPlaylists(chooser: false) }
                else if !o.s("status").isEmpty && o.s("status") != "pending" { app.saveStatus(o); app.activation(o.s("status"), "") }
            }
        }
    }

    private func submit() {
        guard !busy else { return }
        error = ""
        busy = true
        Task {
            if let e = await app.link(code: code) { error = e }
            busy = false
        }
    }
}

/// Assinatura anual pela Apple + Restaurar compras + avisos que a Apple exige (renovação automática, termos e privacidade)
struct PurchaseBox: View {
    @EnvironmentObject var app: AppState
    @ObservedObject var iap = Purchases.shared
    @Binding var error: String

    var body: some View {
        VStack(spacing: UIScale.v(10, 12, 20)) {
            Divider().background(Color.white.opacity(0.2)).padding(.vertical, 4)
            Text(t("iap_title")).font(.system(size: UIScale.body * 1.1, weight: .bold)).foregroundColor(.white)
            Button {
                Task { if let e = await iap.buy() { error = e } }
            } label: {
                HStack {
                    if iap.busy { ProgressView() }
                    Text(iap.price.isEmpty ? t("iap_buy") : t("iap_buy_price", iap.price))
                }
            }
            .buttonStyle(PillStyle(primary: true)).disabled(iap.busy)
            Button(t("iap_restore")) { Task { if let e = await iap.restore() { error = e } } }
                .buttonStyle(PillStyle()).disabled(iap.busy)
            Text(t("iap_terms")).font(.system(size: UIScale.small * 0.95)).foregroundColor(.white.opacity(0.6)).multilineTextAlignment(.center)
            #if os(iOS)
            HStack(spacing: 18) {
                if let u = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/") { Link(t("terms"), destination: u) }
                if let u = URL(string: Config.privacyURL) { Link(t("privacy"), destination: u) }
            }
            .font(.system(size: UIScale.small)).foregroundColor(app.brand.accent)
            #else
            Text(t("terms") + ": apple.com/legal/internet-services/itunes/dev/stdeula  ·  " + t("privacy") + ": iptvbestpro.com/privacy_policy")
                .font(.system(size: UIScale.small * 0.9)).foregroundColor(.white.opacity(0.55)).multilineTextAlignment(.center)
            #endif
        }
        .task { await iap.loadProduct() }
    }
}
