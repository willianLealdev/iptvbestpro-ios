import AVFoundation
import AVKit
import UIKit
#if canImport(VLCKit)
import VLCKit
#elseif canImport(MobileVLCKit)
import MobileVLCKit
#elseif canImport(TVVLCKit)
import TVVLCKit
#endif

enum EngineState { case idle, loading, playing, paused, ended, failed }

struct Track: Identifiable, Hashable {
    let id: Int
    let name: String
}

/// Motor de vídeo: o player da Apple (HLS, MP4) ou o VLC (MKV, AVI, TS e o que a Apple não toca)
@MainActor protocol Engine: AnyObject {
    var view: UIView { get }
    var state: EngineState { get }
    var time: Double { get }
    var duration: Double { get }
    var muted: Bool { get set }
    var fill: Bool { get set }
    func load(_ url: URL, start: Double, live: Bool)
    func play()
    func pause()
    func seek(to: Double)
    func stop()
    func audioTracks() -> [Track]
    func subtitleTracks() -> [Track]   // id -1 = desligado
    var currentAudio: Int { get }
    var currentSubtitle: Int { get }
    func setAudio(_ id: Int)
    func setSubtitle(_ id: Int)
}

final class PlayerSurface: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

/// Player da Apple (AVPlayer): HLS ao vivo e filmes MP4/M3U8, com AirPlay e Picture-in-Picture
@MainActor final class AVEngine: NSObject, Engine {
    let player = AVPlayer()
    private let surface = PlayerSurface()
    private var ended = false
    private var failed = false
    private var endObs: NSObjectProtocol?
    private var failObs: NSObjectProtocol?
    #if os(iOS)
    var pip: AVPictureInPictureController?
    #endif

    var view: UIView { surface }

    override init() {
        super.init()
        surface.backgroundColor = .black
        surface.playerLayer.player = player
        surface.playerLayer.videoGravity = .resizeAspect
        player.automaticallyWaitsToMinimizeStalling = true
        #if os(iOS)
        player.allowsExternalPlayback = true
        if AVPictureInPictureController.isPictureInPictureSupported() {
            pip = AVPictureInPictureController(playerLayer: surface.playerLayer)
            pip?.canStartPictureInPictureAutomaticallyFromInline = true
        }
        #endif
    }

    var state: EngineState {
        if failed { return .failed }
        if ended { return .ended }
        guard let item = player.currentItem else { return .idle }
        if item.status == .failed { return .failed }
        switch player.timeControlStatus {
        case .playing: return .playing
        case .paused: return item.status == .readyToPlay ? .paused : .loading
        default: return .loading
        }
    }
    var time: Double { let s = player.currentTime().seconds; return s.isFinite ? s : 0 }
    var duration: Double {
        guard let d = player.currentItem?.duration.seconds, d.isFinite, d > 0 else { return 0 }
        return d
    }
    var muted: Bool { get { player.isMuted } set { player.isMuted = newValue } }
    var fill: Bool {
        get { surface.playerLayer.videoGravity == .resizeAspectFill }
        set { surface.playerLayer.videoGravity = newValue ? .resizeAspectFill : .resizeAspect }
    }

    func load(_ url: URL, start: Double, live: Bool) {
        ended = false; failed = false
        var opts: [String: Any] = [:]
        if #available(iOS 16.0, tvOS 16.0, *) { opts[AVURLAssetHTTPUserAgentKey] = Config.userAgent }
        let asset = AVURLAsset(url: url, options: opts)
        let item = AVPlayerItem(asset: asset)
        let stable = Prefs.bufferStable
        // Estável: guarda mais vídeo antes de mostrar (internet oscilando); Rápido: troca de canal mais veloz
        item.preferredForwardBufferDuration = live ? (stable ? 20 : 6) : (stable ? 60 : 20)
        if live {
            item.automaticallyPreservesTimeOffsetFromLive = true
            item.configuredTimeOffsetFromLive = CMTime(seconds: stable ? 18 : 8, preferredTimescale: 1)
        }
        if let endObs { NotificationCenter.default.removeObserver(endObs) }
        if let failObs { NotificationCenter.default.removeObserver(failObs) }
        endObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            if !live { Task { @MainActor in self?.ended = true } }
        }
        failObs = NotificationCenter.default.addObserver(forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.failed = true }
        }
        player.replaceCurrentItem(with: item)
        if start > 1 { player.seek(to: CMTime(seconds: start, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: CMTime(seconds: 2, preferredTimescale: 600)) }
        player.play()
    }
    func play() { player.play() }
    func pause() { player.pause() }
    func seek(to t: Double) { player.seek(to: CMTime(seconds: max(0, t), preferredTimescale: 600)) }
    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
    }

    private func group(_ c: AVMediaCharacteristic) -> AVMediaSelectionGroup? {
        player.currentItem?.asset.mediaSelectionGroup(forMediaCharacteristic: c)
    }
    func audioTracks() -> [Track] {
        guard let g = group(.audible) else { return [] }
        return g.options.enumerated().map { Track(id: $0.offset, name: $0.element.displayName) }
    }
    func subtitleTracks() -> [Track] {
        guard let g = group(.legible) else { return [] }
        return [Track(id: -1, name: t("off"))] + g.options.enumerated().map { Track(id: $0.offset, name: $0.element.displayName) }
    }
    var currentAudio: Int {
        guard let g = group(.audible), let item = player.currentItem, let sel = item.currentMediaSelection.selectedMediaOption(in: g) else { return 0 }
        return g.options.firstIndex(of: sel) ?? 0
    }
    var currentSubtitle: Int {
        guard let g = group(.legible), let item = player.currentItem, let sel = item.currentMediaSelection.selectedMediaOption(in: g) else { return -1 }
        return g.options.firstIndex(of: sel) ?? -1
    }
    func setAudio(_ id: Int) {
        guard let g = group(.audible), id >= 0, id < g.options.count else { return }
        player.currentItem?.select(g.options[id], in: g)
    }
    func setSubtitle(_ id: Int) {
        guard let g = group(.legible) else { return }
        player.currentItem?.select(id >= 0 && id < g.options.count ? g.options[id] : nil, in: g)
    }
}

#if canImport(VLCKit) || canImport(MobileVLCKit) || canImport(TVVLCKit)
let hasVLC = true

/// Player VLC: toca MKV, AVI, MPEG-TS e outros formatos que o player da Apple não toca
@MainActor final class VLCEngine: NSObject, Engine {
    private let mp = VLCMediaPlayer()
    private let surface = UIView()
    private var startAt: Double = 0
    private var sought = false
    private var isMuted = false

    var view: UIView { surface }

    override init() {
        super.init()
        surface.backgroundColor = .black
        mp.drawable = surface
    }

    var state: EngineState {
        switch mp.state {
        case .opening, .buffering: return mp.isPlaying ? .playing : .loading
        case .playing, .esAdded: return .playing
        case .paused: return .paused
        case .ended: return .ended
        case .error: return .failed
        case .stopped: return .idle
        @unknown default: return .loading
        }
    }
    var time: Double { Double(mp.time.intValue) / 1000 }
    var duration: Double {
        let ms = Double(mp.media?.length.intValue ?? 0)
        return ms > 0 ? ms / 1000 : 0
    }
    var muted: Bool {
        get { isMuted }
        set { isMuted = newValue; (mp.audio as VLCAudio?)?.volume = newValue ? 0 : 100 }
    }
    var fill = false

    func load(_ url: URL, start: Double, live: Bool) {
        let m = VLCMedia(url: url)
        let stable = Prefs.bufferStable
        m.addOption(":network-caching=\(live ? (stable ? 4000 : 1500) : (stable ? 6000 : 2500))")
        m.addOption(":http-user-agent=\(Config.userAgent)")
        m.addOption(":http-reconnect")
        if start > 1 { m.addOption(":start-time=\(Int(start))") }
        startAt = start
        sought = start <= 1
        mp.media = m
        mp.play()
        if isMuted { muted = true }
    }
    func play() { mp.play() }
    func pause() { mp.pause() }
    func seek(to t: Double) { mp.time = VLCTime(int: Int32(max(0, t) * 1000)) }
    func stop() { mp.stop() }

    private func tracks(_ names: [Any]?, _ ids: [Any]?) -> [Track] {
        let n = names ?? [], i = ids ?? []
        var out: [Track] = []
        for k in 0..<min(n.count, i.count) {
            let id = (i[k] as? NSNumber)?.intValue ?? k
            out.append(Track(id: id, name: id < 0 ? t("off") : "\(n[k])"))
        }
        return out
    }
    func audioTracks() -> [Track] { tracks(mp.audioTrackNames, mp.audioTrackIndexes).filter { $0.id >= 0 } }
    func subtitleTracks() -> [Track] {
        let l = tracks(mp.videoSubTitlesNames, mp.videoSubTitlesIndexes)
        return l.contains { $0.id == -1 } ? l : [Track(id: -1, name: t("off"))] + l
    }
    var currentAudio: Int { Int(mp.currentAudioTrackIndex) }
    var currentSubtitle: Int { Int(mp.currentVideoSubTitleIndex) }
    func setAudio(_ id: Int) { mp.currentAudioTrackIndex = Int32(id) }
    func setSubtitle(_ id: Int) { mp.currentVideoSubTitleIndex = Int32(id) }
}
#else
let hasVLC = false
#endif

enum EngineKind { case apple, vlc }

@MainActor func makeEngine(_ k: EngineKind) -> Engine {
    #if canImport(VLCKit) || canImport(MobileVLCKit) || canImport(TVVLCKit)
    if k == .vlc { return VLCEngine() }
    #endif
    return AVEngine()
}
