import SwiftUI
import CoreImage

// MARK: - Imagens (logos, capas, pôsteres) com cache

final class ImageCache {
    static let shared = ImageCache()
    private let mem = NSCache<NSString, UIImage>()
    private let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.urlCache = URLCache(memoryCapacity: 30 << 20, diskCapacity: 300 << 20)
        c.requestCachePolicy = .returnCacheDataElseLoad
        c.timeoutIntervalForRequest = 20
        c.httpAdditionalHeaders = ["User-Agent": Config.userAgent]
        return URLSession(configuration: c)
    }()
    init() { mem.countLimit = 400 }

    func cached(_ url: String) -> UIImage? { mem.object(forKey: url as NSString) }
    func load(_ url: String) async -> UIImage? {
        if let i = cached(url) { return i }
        guard let u = URL(string: url.trimmed), u.scheme?.hasPrefix("http") == true else { return nil }
        var req = URLRequest(url: u)
        req.setValue("image/*,*/*", forHTTPHeaderField: "Accept")
        do {
            let (d, resp) = try await session.data(for: req)
            guard let img = UIImage(data: d) else {
                #if DEBUG
                NSLog("[bp-img] não é imagem %@ status=%d tipo=%@ bytes=%d", url, (resp as? HTTPURLResponse)?.statusCode ?? 0, (resp as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "", d.count)
                #endif
                return nil
            }
            mem.setObject(img, forKey: url as NSString)
            return img
        } catch {
            #if DEBUG
            NSLog("[bp-img] erro %@ %@", url, String(describing: error))
            #endif
            return nil
        }
    }
    func clear() {
        mem.removeAllObjects()
        session.configuration.urlCache?.removeAllCachedResponses()
    }
}

struct RemoteImage: View {
    let url: String
    var fill = true
    var placeholder: String = "photo"
    @State private var img: UIImage?

    var body: some View {
        ZStack {
            if let img {
                Image(uiImage: img).resizable().aspectRatio(contentMode: fill ? .fill : .fit)
            } else if !placeholder.isEmpty {
                Image(systemName: placeholder).font(.system(size: UIScale.v(18, 24, 40))).foregroundColor(.white.opacity(0.25))
            } else {
                Color.clear
            }
        }
        .task(id: url) {
            img = ImageCache.shared.cached(url)
            if img == nil, !url.isEmpty { img = await ImageCache.shared.load(url) }
        }
    }
}

// MARK: - Botões que funcionam no toque (iPhone/iPad) e no controle remoto (Apple TV)

/// Estilo dos cartões: no Apple TV o item com foco cresce e ganha a borda da cor do tema
struct TileStyle: ButtonStyle {
    var radius: CGFloat = UIScale.v(14, 16, 22)
    func makeBody(configuration: Configuration) -> some View {
        TileBody(configuration: configuration, radius: radius)
    }
    struct TileBody: View {
        let configuration: Configuration
        let radius: CGFloat
        @Environment(\.isFocused) private var focused
        @EnvironmentObject var app: AppState
        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: radius).stroke(app.brand.accent, lineWidth: focused ? UIScale.v(3, 3, 6) : 0))
                .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.06 : 1))
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: focused ? 18 : 0, y: focused ? 10 : 0)
                .animation(.easeOut(duration: 0.15), value: focused)
                .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
        }
    }
}

/// Linha de lista (categorias, canais, episódios) com destaque de seleção e de foco
struct RowStyle: ButtonStyle {
    var selected = false
    func makeBody(configuration: Configuration) -> some View { RowBody(configuration: configuration, selected: selected) }
    struct RowBody: View {
        let configuration: Configuration
        let selected: Bool
        @Environment(\.isFocused) private var focused
        @EnvironmentObject var app: AppState
        var body: some View {
            configuration.label
                .foregroundColor(selected ? app.brand.accent : app.brand.text)
                .padding(.horizontal, UIScale.v(12, 14, 24))
                .frame(maxWidth: .infinity, minHeight: UIScale.rowH, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: UIScale.v(10, 10, 14))
                    .fill(focused ? app.brand.accent.opacity(0.28) : (configuration.isPressed ? Color.white.opacity(0.12) : (selected ? app.brand.accent.opacity(0.12) : Color.white.opacity(0.05)))))
                .overlay(alignment: .leading) {
                    if selected { Rectangle().fill(app.brand.accent).frame(width: UIScale.v(3, 4, 6)).padding(.vertical, 8) }
                }
                .scaleEffect(focused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}

/// Botão principal (cor do tema) ou secundário
struct PillStyle: ButtonStyle {
    var primary = false
    func makeBody(configuration: Configuration) -> some View { PillBody(configuration: configuration, primary: primary) }
    struct PillBody: View {
        let configuration: Configuration
        let primary: Bool
        @Environment(\.isFocused) private var focused
        @EnvironmentObject var app: AppState
        var body: some View {
            configuration.label
                .font(.system(size: UIScale.body, weight: .semibold))
                .foregroundColor(primary ? (app.brand.accentIsLight ? Color(white: 0.08) : .white) : .white)
                .padding(.horizontal, UIScale.v(18, 22, 40))
                .frame(minHeight: UIScale.v(46, 50, 80))
                .background(Capsule().fill(primary ? app.brand.accent : Color.white.opacity(focused ? 0.3 : 0.12)))
                .overlay(Capsule().stroke(focused ? Color.white : .clear, lineWidth: UIScale.v(2, 2, 4)))
                .scaleEffect(configuration.isPressed ? 0.96 : (focused ? 1.06 : 1))
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}

// MARK: - Fundo, topo e avisos

/// Fundo do app: imagem do tema, pôsteres (MovieUI), degradê das cores do tema ou o fundo padrão
struct BrandBackground: View {
    @EnvironmentObject var app: AppState
    @State private var posterIdx = 0
    let timer = Timer.publish(every: 20, on: .main, in: .common).autoconnect()

    var body: some View {
        let b = app.brand
        ZStack {
            Color.black
            if !b.backgroundImage.isEmpty {
                RemoteImage(url: b.backgroundImage, placeholder: "")
                Color.black.opacity(b.overlay)
            } else if !b.posters.isEmpty {
                RemoteImage(url: b.posters[posterIdx % b.posters.count], placeholder: "")
                    .id(posterIdx).transition(.opacity)
                Color.black.opacity(b.overlay)
            } else if let top = b.bgTop {
                LinearGradient(colors: [top, b.bgBottom ?? top], startPoint: .top, endPoint: .bottom)
            } else {
                RemoteImage(url: Config.defaultBackground, placeholder: "")
                Color.black.opacity(b.overlay)
            }
        }
        .ignoresSafeArea()
        .onReceive(timer) { _ in
            if b.posters.count > 1 { withAnimation(.easeInOut(duration: 1)) { posterIdx += 1 } }
        }
    }
}

struct ClockText: View {
    @EnvironmentObject var app: AppState
    @State private var now = Date()
    let timer = Timer.publish(every: 15, on: .main, in: .common).autoconnect()
    var body: some View {
        Text(Fmt.dateTime(now)).font(.system(size: UIScale.small, weight: .medium)).foregroundColor(.white.opacity(0.85))
            .onReceive(timer) { now = $0 }
    }
}

/// Topo das telas: logo e nome da marca (tela inicial) ou o título da tela
struct TopBar<Trailing: View>: View {
    @EnvironmentObject var app: AppState
    var title: String = ""
    var onBack: (() -> Void)?
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: UIScale.v(10, 14, 24)) {
            if let onBack, !DeviceInfo.isTV {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.system(size: UIScale.title * 0.8, weight: .semibold)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundColor(.white)
            }
            RemoteImage(url: app.brand.logo, fill: false, placeholder: "")
                .frame(width: UIScale.v(38, 46, 80), height: UIScale.v(38, 46, 80))
            if !title.isEmpty {
                Text(title).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white).lineLimit(1)
            } else if app.brand.showName && !(DeviceInfo.isPhone && Trailing.self != EmptyView.self) {
                Text(app.brand.name).font(.system(size: UIScale.title, weight: .bold)).foregroundColor(.white).lineLimit(1)
            }
            Spacer(minLength: 8)
            trailing()
            ClockText()
        }
        .padding(.horizontal, UIScale.pad)
        .padding(.top, UIScale.v(4, 8, 20))
    }
}

extension TopBar where Trailing == EmptyView {
    init(title: String = "", onBack: (() -> Void)? = nil) {
        self.title = title
        self.onBack = onBack
        self.trailing = { EmptyView() }
    }
}

struct ToastView: View {
    let text: String
    @EnvironmentObject var app: AppState
    var body: some View {
        Text(text)
            .font(.system(size: UIScale.body, weight: .medium)).foregroundColor(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, UIScale.v(16, 20, 36)).padding(.vertical, UIScale.v(10, 12, 22))
            .background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85)))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(app.brand.accent, lineWidth: 2))
            .padding(.bottom, UIScale.v(30, 40, 60))
            .padding(.horizontal, 20)
    }
}

struct Spinner: View {
    @EnvironmentObject var app: AppState
    var body: some View { ProgressView().progressViewStyle(.circular).tint(app.brand.accent).scaleEffect(UIScale.v(1.3, 1.5, 2)) }
}

struct EmptyText: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: UIScale.body)).foregroundColor(.white.opacity(0.65)).multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity).padding()
    }
}

/// Cartão de diálogo (ativação, sem lista, avisos)
struct CardBox<Content: View>: View {
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(spacing: UIScale.v(14, 18, 30)) { content() }
            .padding(UIScale.v(22, 32, 60))
            .frame(maxWidth: UIScale.v(520, 620, 1100))
            .background(RoundedRectangle(cornerRadius: UIScale.v(20, 24, 34)).fill(Color.black.opacity(0.72)))
            .overlay(RoundedRectangle(cornerRadius: UIScale.v(20, 24, 34)).stroke(Color.white.opacity(0.1), lineWidth: 1))
            .padding(UIScale.pad)
    }
}

/// QR Code (WhatsApp do suporte): no Apple TV o cliente aponta a câmera do celular
struct QRCodeView: View {
    let text: String
    var body: some View {
        if let img = Self.make(text) {
            Image(uiImage: img).interpolation(.none).resizable().scaledToFit()
                .padding(UIScale.v(8, 10, 16)).background(Color.white).cornerRadius(10)
        }
    }
    static func make(_ text: String) -> UIImage? {
        guard let f = CIFilter(name: "CIQRCodeGenerator") else { return nil }
        f.setValue(Data(text.utf8), forKey: "inputMessage")
        f.setValue("M", forKey: "inputCorrectionLevel")
        guard let out = f.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(out, from: out.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}

// MARK: - Formatos de data e hora

enum Fmt {
    static func time(_ sec: Double) -> String {
        let s = max(0, Int(sec)), h = s / 3600, m = s % 3600 / 60, ss = s % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, ss) : String(format: "%d:%02d", m, ss)
    }
    static func hm(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.localeID)
        f.dateFormat = Prefs.time24h ? "HH:mm" : "h:mm a"
        return f.string(from: d)
    }
    static func dateTime(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.localeID)
        f.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return f.string(from: d) + "  " + hm(d)
    }
    static func date(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: L10n.localeID)
        f.dateStyle = .medium
        return f.string(from: d)
    }
    static func bytes(_ b: Int64) -> String { ByteCountFormatter.string(fromByteCount: b, countStyle: .file) }
}

extension View {
    /// Cantos e fundo de cartão
    func cardBG(_ color: Color, radius: CGFloat = UIScale.v(14, 16, 22)) -> some View {
        background(RoundedRectangle(cornerRadius: radius).fill(color)).clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

extension View {
    /// No iPhone/iPad dá para copiar o texto (ID do aparelho); no Apple TV não existe
    @ViewBuilder func selectableText() -> some View {
        #if os(iOS)
        self.textSelection(.enabled)
        #else
        self
        #endif
    }
}
