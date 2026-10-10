import SwiftUI
import AVFoundation

/// O que vai tocar: canal ao vivo (com a lista para trocar de canal), filme, episódio (com os próximos) ou catch-up
struct PlayRequest: Identifiable {
    enum Kind { case live, movie, episode, catchup }
    let id = UUID()
    var kind: Kind
    var title: String
    var items: [JObj] = []        // canais da categoria (live) ou episódios da temporada (episode)
    var index: Int = 0
    var item: JObj = [:]          // filme
    var series: JObj = [:]        // série do episódio (continuar assistindo)
    var startAt: Double = 0
    var url: URL?                 // catch-up
    var catID: String = ""        // categoria do canal (para o "Continuar")
}

/// Controla um player: escolhe o motor, tenta outro formato se não tocar, reconecta e informa tempo/estado
@MainActor
final class PlayerModel: ObservableObject {
    @Published var state: EngineState = .idle
    @Published var time: Double = 0
    @Published var duration: Double = 0
    @Published var message: String?
    @Published var engineToken = UUID()   // muda quando o motor (a tela do vídeo) troca

    private(set) var engine: Engine?
    private var attempts: [(URL, EngineKind)] = []
    private var attempt = 0
    private var live = false
    private var startAt: Double = 0
    private var retries = 0
    private var ticker: Timer?
    private var loadingSince: Date?
    private var everPlayed = false
    var muted = false { didSet { engine?.muted = muted } }
    var fill = false { didSet { engine?.fill = fill } }
    var onEnded: (() -> Void)?

    deinit { ticker?.invalidate() }

    /// Canal ao vivo: tenta HLS (.m3u8) e, se não tocar, MPEG-TS (.ts) pelo VLC — ou o formato escolhido em Configurações
    func playLive(_ x: Xtream, id: String) {
        var l: [(URL, EngineKind)] = []
        let hls = x.live(id, ext: "m3u8"), ts = x.live(id, ext: "ts")
        switch Prefs.liveFormat {
        case 1: if let hls { l += [(hls, .apple)]; if hasVLC { l += [(hls, .vlc)] } }
        case 2: if hasVLC, let ts { l += [(ts, .vlc)] }; if let hls { l += [(hls, .apple)] }
        default:
            if let hls { l += [(hls, .apple)] }
            if hasVLC { if let ts { l += [(ts, .vlc)] }; if let hls { l += [(hls, .vlc)] } }
        }
        start(l, live: true, at: 0)
    }

    /// Filme ou episódio: MP4/M3U8/MOV no player da Apple; MKV, AVI e outros no VLC (e o outro se o primeiro falhar)
    func playFile(_ url: URL, at: Double) {
        let ext = url.pathExtension.lowercased()
        let apple = ["mp4", "m4v", "mov", "m3u8", "3gp"].contains(ext)
        var l: [(URL, EngineKind)] = apple ? [(url, .apple)] : []
        if hasVLC { l.append((url, .vlc)) }
        if !apple { l.append((url, .apple)) }
        start(l, live: false, at: at)
    }

    func playCatchup(_ url: URL) {
        start(hasVLC ? [(url, .vlc), (url, .apple)] : [(url, .apple)], live: false, at: 0)
    }

    private func start(_ l: [(URL, EngineKind)], live: Bool, at: Double) {
        attempts = l; attempt = 0; retries = 0; self.live = live; startAt = at; everPlayed = false
        message = nil
        guard !l.isEmpty else { state = .failed; message = t("play_err"); return }
        load()
        ticker?.invalidate()
        ticker = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
    }

    private func load() {
        let (url, kind) = attempts[attempt]
        let needNew: Bool = {
            guard let e = engine else { return true }
            return (kind == .vlc) != !(e is AVEngine)
        }()
        if needNew {
            engine?.stop()
            engine = makeEngine(kind)
            engine?.muted = muted
            engine?.fill = fill
            engineToken = UUID()
        }
        loadingSince = Date()
        state = .loading
        engine?.load(url, start: startAt, live: live)
    }

    private func tick() {
        guard let e = engine else { return }
        let st = e.state
        if st == .playing {
            everPlayed = true; retries = 0; loadingSince = nil; message = nil
            if !live && e.time > 1 { startAt = e.time }
        }
        time = e.time
        duration = e.duration
        switch st {
        case .failed:
            next()
            return
        case .ended:
            if state != .ended { state = .ended; onEnded?() }
            return
        case .loading:
            if loadingSince == nil { loadingSince = Date() }
            // travou carregando muito tempo: tenta de novo (ao vivo) ou o outro formato
            if let s = loadingSince, Date().timeIntervalSince(s) > (everPlayed ? 25 : 18) { loadingSince = nil; next() ; return }
        default: break
        }
        state = st
    }

    /// Não tocou: próximo formato; acabou a lista, reconecta mais 2 vezes e depois mostra o erro
    private func next() {
        if !everPlayed && attempt + 1 < attempts.count {
            attempt += 1
            load()
            return
        }
        retries += 1
        if retries <= 2 {
            message = t("reconnect")
            if !everPlayed { attempt = 0 }
            state = .loading
            let a = attempt
            Task { [weak self] in
                try? await Task.sleep(nanoseconds: 2_500_000_000)
                guard let self, self.attempt == a, !self.attempts.isEmpty else { return }
                self.load()
            }
            loadingSince = Date().addingTimeInterval(5)
        } else {
            state = .failed
            message = t(live ? "ch_off" : "play_err")
            engine?.stop()
        }
    }

    func togglePlay() {
        guard let e = engine else { return }
        if e.state == .playing { e.pause(); state = .paused } else { e.play(); state = .playing }
    }
    func seek(by s: Double) {
        guard let e = engine, !live else { return }
        let to = max(0, min((e.duration > 0 ? e.duration - 2 : e.time + s), e.time + s))
        e.seek(to: to)
        time = to
    }
    func seek(to s: Double) { engine?.seek(to: s); time = s }

    func stop() {
        ticker?.invalidate(); ticker = nil
        engine?.stop()
        engine = nil
        attempts = []
        state = .idle
        engineToken = UUID()
    }
}

/// Mostra o vídeo do motor atual
struct VideoSurface: UIViewRepresentable {
    @ObservedObject var model: PlayerModel
    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .black
        return v
    }
    func updateUIView(_ v: UIView, context: Context) {
        guard let ev = model.engine?.view else { v.subviews.forEach { $0.removeFromSuperview() }; return }
        if ev.superview !== v {
            v.subviews.forEach { $0.removeFromSuperview() }
            ev.frame = v.bounds
            ev.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            v.addSubview(ev)
        }
        _ = model.engineToken
    }
}

enum AudioSessionSetup {
    static func activate() {
        #if os(iOS) || os(tvOS)
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)
        try? AVAudioSession.sharedInstance().setActive(true)
        #endif
    }
}
