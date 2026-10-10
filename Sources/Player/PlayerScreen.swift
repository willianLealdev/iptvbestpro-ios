import SwiftUI
import AVKit

/// Player em tela cheia: canal ao vivo (troca de canal), filme, episódio (próximo automático) e catch-up
struct PlayerScreen: View {
    let request: PlayRequest
    @EnvironmentObject var app: AppState
    @EnvironmentObject var center: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = PlayerModel()

    @State private var index = 0
    @State private var controls = true
    @State private var hideTask: Task<Void, Never>?
    @State private var zap: String?
    @State private var zapTask: Task<Void, Never>?
    @State private var epg: [JObj] = []
    @State private var showList = false
    @State private var showTracks = false
    @State private var countdown: Int?
    @State private var saveTimer: Timer?
    @State private var scrubbing: Double?
    @State private var fill = false
    @State private var subsApplied = false
    @FocusState private var rootFocus: Bool

    private var isLive: Bool { request.kind == .live }
    private var current: JObj { request.items.indices.contains(index) ? request.items[index] : request.item }
    private var title: String {
        switch request.kind {
        case .live: return "\(index + 1)  ·  " + current.s("name")
        case .episode: return (request.series.s("name").isEmpty ? "" : request.series.s("name") + " – ") + current.s("title")
        default: return request.title
        }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VideoSurface(model: model).ignoresSafeArea()
            if model.state == .loading || model.message != nil {
                VStack(spacing: 12) {
                    if model.state == .loading { Spinner() }
                    if let m = model.message { Text(m).font(.system(size: UIScale.body, weight: .semibold)).foregroundColor(.white).multilineTextAlignment(.center) }
                    if model.state == .failed {
                        Button(t("retry")) { start() }.buttonStyle(PillStyle(primary: true))
                    }
                }
                .padding(20).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.55)))
            }
            if controls { controlsOverlay.transition(.opacity) }
            if let zap { zapBanner(zap) }
            if showList && isLive { channelPanel.transition(.move(edge: .trailing)) }
            if let c = countdown { nextEpisodeBox(c) }
        }
        .contentShape(Rectangle())
        #if os(iOS)
        .onTapGesture { toggleControls() }
        .gesture(DragGesture(minimumDistance: 40).onEnded { v in
            guard isLive, abs(v.translation.height) > abs(v.translation.width) else { return }
            zapStep(v.translation.height < 0 ? 1 : -1)
        })
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        #if os(tvOS)
        .focusable(!controls && !showList)
        .focused($rootFocus)
        .onMoveCommand { d in
            switch d {
            case .up: if isLive { zapStep(-1) } else { showControls() }
            case .down: if isLive { zapStep(1) } else { showControls() }
            case .left: if isLive { withAnimation { showList = true } } else { model.seek(by: -10); showControls() }
            case .right: if isLive { showControls() } else { model.seek(by: 10); showControls() }
            @unknown default: break
            }
        }
        .onPlayPauseCommand { model.togglePlay(); showControls() }
        .onExitCommand {
            if showList { withAnimation { showList = false } }
            else if controls { withAnimation { controls = false }; rootFocus = true }
            else { close() }
        }
        #endif
        .sheet(isPresented: $showTracks) { TracksSheet(model: model) }
        .onAppear {
            index = request.index
            fill = false
            start()
            showControls()
            saveTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { _ in Task { @MainActor in savePosition() } }
        }
        .onDisappear {
            savePosition()
            saveTimer?.invalidate()
            model.stop()
        }
        .onReceive(NotificationCenter.default.publisher(for: .bpStopPlayback)) { _ in close() }
        .onChange(of: model.state) { st in
            if st == .playing && !subsApplied {
                subsApplied = true
                if !Prefs.subtitles { model.engine?.setSubtitle(-1) }
            }
        }
    }

    // MARK: tocar

    private func start() {
        guard let x = app.xtream else { model.message = t("play_err"); return }
        subsApplied = false
        model.onEnded = { ended() }
        switch request.kind {
        case .live:
            let c = current
            model.playLive(x, id: c.s("stream_id"))
            remember(live: c)
            epg = []
            Task { epg = await EPG.short(x, id: c.s("stream_id"), limit: 2) }
        case .movie:
            let it = request.item, id = it.s("stream_id")
            guard let u = x.movie(id, ext: it.s("container_extension")) else { return }
            model.playFile(u, at: request.startAt)
            var cw = it
            cw["id"] = id
            Library.cwAdd("movie", cw)
            Library.lastPlay = ["kind": "movie", "id": id, "name": it.s("name"), "ext": it.s("container_extension"), "icon": it.s("stream_icon")]
        case .episode:
            let ep = current
            guard let u = x.episode(ep.s("id"), ext: ep.s("container_extension")) else { return }
            let at = index == request.index ? request.startAt : Library.position(episode: ep.s("id"))
            model.playFile(u, at: at > 30 ? at : 0)
            var cw = request.series
            cw["id"] = request.series.s("series_id")
            cw["last_season"] = request.series.s("season")
            cw["last_episode"] = ep.s("id")
            Library.cwAdd("series", cw)
            Library.lastPlay = ["kind": "series", "id": ep.s("id"), "title": title, "ext": ep.s("container_extension"), "series": request.series,
                                "episodes": request.items.map { ["id": $0.s("id"), "title": $0.s("title"), "container_extension": $0.s("container_extension")] }]
        case .catchup:
            if let u = request.url { model.playCatchup(u) }
        }
    }

    private func remember(live c: JObj) {
        Library.lastLive = ["cat": request.catID, "sid": c.s("stream_id")]
        var item = c
        item["id"] = c.s("stream_id")
        Library.cwAdd("live", item)
        Library.lastPlay = ["kind": "live", "cat": request.catID, "sid": c.s("stream_id"), "name": c.s("name"), "icon": c.s("stream_icon"),
                            "list": Array(request.items.prefix(400))]
    }

    private func savePosition() {
        guard model.time > 5 else { return }
        if request.kind == .movie { Library.savePosition(kind: "movie", id: request.item.s("stream_id"), time: model.time, duration: model.duration) }
        if request.kind == .episode { Library.savePosition(kind: "episode", id: current.s("id"), time: model.time, duration: model.duration) }
    }

    private func ended() {
        savePosition()
        if request.kind == .episode && Prefs.autoplayNext && index + 1 < request.items.count {
            countdown = 5
            Task {
                while let c = countdown, c > 0 {
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                    if countdown != nil { countdown = c - 1 }
                }
                if countdown == 0 { countdown = nil; nextEpisode() }
            }
        } else if request.kind != .live {
            close()
        }
    }

    private func nextEpisode() {
        savePosition()
        guard index + 1 < request.items.count else { return }
        index += 1
        start()
        showControls()
    }

    private func zapStep(_ step: Int) {
        guard isLive, !request.items.isEmpty else { return }
        index = (index + step + request.items.count) % request.items.count
        start()
        flashZap()
    }

    private func flashZap() {
        zap = title
        zapTask?.cancel()
        zapTask = Task { try? await Task.sleep(nanoseconds: 3_500_000_000); if !Task.isCancelled { withAnimation { zap = nil } } }
    }

    private func close() {
        savePosition()
        model.stop()
        center.request = nil
        dismiss()
    }

    private func toggleControls() { if controls { withAnimation { controls = false } } else { showControls() } }
    private func showControls() {
        withAnimation { controls = true }
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if !Task.isCancelled && !showTracks && scrubbing == nil {
                withAnimation { controls = false }
                #if os(tvOS)
                rootFocus = true
                #endif
            }
        }
    }

    // MARK: telas por cima do vídeo

    private var controlsOverlay: some View {
        VStack(spacing: 0) {
            HStack(spacing: UIScale.v(10, 14, 30)) {
                #if os(iOS)
                Button { close() } label: { Image(systemName: "xmark").font(.system(size: 20, weight: .bold)).frame(width: 44, height: 44) }
                    .buttonStyle(.plain).foregroundColor(.white)
                #endif
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: UIScale.body * 1.1, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    if isLive, let now = epg.first {
                        Text(t("now") + ": " + now.s("title").base64Decoded).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.8)).lineLimit(1)
                    }
                }
                Spacer()
                #if os(iOS)
                AirPlayButton().frame(width: 44, height: 44)
                if let av = model.engine as? AVEngine, let pip = av.pip {
                    Button { pip.startPictureInPicture() } label: { Image(systemName: "pip.enter").font(.system(size: 20)).frame(width: 44, height: 44) }
                        .buttonStyle(.plain).foregroundColor(.white)
                }
                #endif
            }
            .padding(.horizontal, UIScale.pad).padding(.top, UIScale.v(10, 16, 40))
            .background(LinearGradient(colors: [.black.opacity(0.75), .clear], startPoint: .top, endPoint: .bottom).ignoresSafeArea())

            Spacer()

            VStack(spacing: UIScale.v(10, 12, 24)) {
                if !isLive && model.duration > 0 { progressBar }
                HStack(spacing: UIScale.v(14, 22, 40)) {
                    if isLive {
                        ctl("chevron.up", t("prev_ch")) { zapStep(-1) }
                        ctl("chevron.down", t("next_ch")) { zapStep(1) }
                        ctl("list.bullet", t("ch_title")) { withAnimation { showList = true } }
                        ctl(Library.isFav("live", current) ? "star.fill" : "star", t("favorites")) {
                            let on = Library.toggleFav("live", current); app.show(t(on ? "fav_added" : "fav_removed")); showControls()
                        }
                    } else {
                        ctl("gobackward.10", "-10s") { model.seek(by: -10); showControls() }
                    }
                    ctl(model.state == .playing ? "pause.fill" : "play.fill", t("play"), big: true) { model.togglePlay(); showControls() }
                    if !isLive {
                        ctl("goforward.10", "+10s") { model.seek(by: 10); showControls() }
                        if request.kind == .episode && index + 1 < request.items.count {
                            ctl("forward.end.fill", t("next_ep")) { nextEpisode() }
                        }
                    }
                    ctl("captions.bubble", t("tracks")) { showTracks = true }
                    ctl(fill ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right", t("fill")) { fill.toggle(); model.fill = fill; showControls() }
                    #if os(tvOS)
                    ctl("xmark", t("close")) { close() }
                    #endif
                }
            }
            .padding(.horizontal, UIScale.pad).padding(.bottom, UIScale.v(16, 22, 50)).padding(.top, 30)
            .background(LinearGradient(colors: [.clear, .black.opacity(0.8)], startPoint: .top, endPoint: .bottom).ignoresSafeArea())
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func ctl(_ icon: String, _ label: String, big: Bool = false, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: big ? UIScale.v(30, 34, 54) : UIScale.v(20, 24, 38), weight: .semibold))
                .frame(width: big ? UIScale.v(64, 72, 120) : UIScale.v(46, 52, 90), height: big ? UIScale.v(64, 72, 120) : UIScale.v(46, 52, 90))
                .background(Circle().fill(Color.white.opacity(big ? 0.22 : 0.12)))
                .foregroundColor(.white)
        }
        .buttonStyle(TileStyle(radius: 80))
        .accessibilityLabel(label)
    }

    private var progressBar: some View {
        let shown = scrubbing ?? model.time
        return HStack(spacing: 12) {
            Text(Fmt.time(shown)).font(.system(size: UIScale.small, design: .monospaced)).foregroundColor(.white)
            #if os(iOS)
            Slider(value: Binding(get: { scrubbing ?? model.time }, set: { scrubbing = $0 }), in: 0...max(1, model.duration), onEditingChanged: { editing in
                if !editing, let s = scrubbing { model.seek(to: s); scrubbing = nil; showControls() }
            })
            .tint(app.brand.accent)
            #else
            ProgressView(value: min(1, shown / max(1, model.duration))).tint(app.brand.accent)
            #endif
            Text(Fmt.time(model.duration)).font(.system(size: UIScale.small, design: .monospaced)).foregroundColor(.white)
        }
    }

    private func zapBanner(_ text: String) -> some View {
        VStack {
            HStack(spacing: 14) {
                RemoteImage(url: current.s("stream_icon"), fill: false, placeholder: "tv").frame(width: UIScale.v(50, 60, 100), height: UIScale.v(36, 44, 74))
                VStack(alignment: .leading, spacing: 4) {
                    Text(text).font(.system(size: UIScale.body * 1.15, weight: .bold)).foregroundColor(.white).lineLimit(1)
                    if let now = epg.first { Text(t("now") + ": " + now.s("title").base64Decoded).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.8)).lineLimit(1) }
                    if epg.count > 1 { Text(t("next") + ": " + epg[1].s("title").base64Decoded).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.6)).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .padding(UIScale.v(12, 16, 28))
            .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.75)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(app.brand.accent, lineWidth: 2))
            .frame(maxWidth: UIScale.v(500, 640, 1100))
            .padding(.top, UIScale.v(50, 60, 80))
            Spacer()
        }
        .allowsHitTesting(false)
    }

    private var channelPanel: some View {
        HStack {
            Spacer()
            VStack(spacing: 0) {
                HStack {
                    Text(t("ch_title")).font(.system(size: UIScale.body, weight: .bold)).foregroundColor(.white)
                    Spacer()
                    #if os(iOS)
                    Button { withAnimation { showList = false } } label: { Image(systemName: "xmark").foregroundColor(.white).frame(width: 40, height: 40) }.buttonStyle(.plain)
                    #endif
                }
                .padding(12)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(request.items.enumerated()), id: \.offset) { i, c in
                                Button {
                                    index = i; start(); flashZap()
                                    withAnimation { showList = false }
                                } label: {
                                    HStack(spacing: 10) {
                                        Text("\(i + 1)").font(.system(size: UIScale.small, design: .monospaced)).foregroundColor(.white.opacity(0.6)).frame(minWidth: 30)
                                        RemoteImage(url: c.s("stream_icon"), fill: false, placeholder: "tv").frame(width: 36, height: 26)
                                        Text(c.s("name")).font(.system(size: UIScale.small)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(RowStyle(selected: i == index)).id(i)
                            }
                        }
                        .padding(.horizontal, 10).padding(.bottom, 20)
                    }
                    .onAppear { proxy.scrollTo(index, anchor: .center) }
                }
            }
            .frame(width: UIScale.v(300, 380, 640))
            .background(Color.black.opacity(0.85).ignoresSafeArea())
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func nextEpisodeBox(_ c: Int) -> some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("next_ep_in", "\(c)")).font(.system(size: UIScale.body, weight: .bold)).foregroundColor(.white)
                    HStack(spacing: 10) {
                        Button(t("play")) { countdown = nil; nextEpisode() }.buttonStyle(PillStyle(primary: true))
                        Button(t("cancel")) { countdown = nil; close() }.buttonStyle(PillStyle())
                    }
                }
                .padding(18).background(RoundedRectangle(cornerRadius: 14).fill(Color.black.opacity(0.85)))
                .padding(UIScale.pad)
            }
        }
    }
}

/// Áudio e legendas (o que o vídeo tiver)
struct TracksSheet: View {
    @ObservedObject var model: PlayerModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var app: AppState
    @State private var audio: [Track] = []
    @State private var subs: [Track] = []
    @State private var curA = 0
    @State private var curS = -1

    var body: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    Text(t("audio")).font(.system(size: UIScale.body, weight: .bold)).foregroundColor(app.brand.accent)
                    if audio.isEmpty { Text(t("tracks_none")).foregroundColor(.white.opacity(0.6)).font(.system(size: UIScale.small)) }
                    ForEach(audio) { tr in
                        Button { model.engine?.setAudio(tr.id); curA = tr.id } label: { Text(tr.name).font(.system(size: UIScale.body)) }
                            .buttonStyle(RowStyle(selected: tr.id == curA))
                    }
                    Text(t("subtitles")).font(.system(size: UIScale.body, weight: .bold)).foregroundColor(app.brand.accent).padding(.top, 12)
                    ForEach(subs) { tr in
                        Button { model.engine?.setSubtitle(tr.id); curS = tr.id } label: { Text(tr.name).font(.system(size: UIScale.body)) }
                            .buttonStyle(RowStyle(selected: tr.id == curS))
                    }
                    Button(t("close")) { dismiss() }.buttonStyle(PillStyle()).padding(.top, 16)
                }
                .padding(UIScale.pad * 1.5)
                .frame(maxWidth: UIScale.v(.infinity, 600, 1000))
            }
        }
        .onAppear {
            audio = model.engine?.audioTracks() ?? []
            subs = model.engine?.subtitleTracks() ?? []
            curA = model.engine?.currentAudio ?? 0
            curS = model.engine?.currentSubtitle ?? -1
        }
    }
}

#if os(iOS)
/// Botão do AirPlay (mandar para a TV / Apple TV)
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: Context) -> AVRoutePickerView {
        let v = AVRoutePickerView()
        v.tintColor = .white
        v.activeTintColor = .systemBlue
        v.prioritizesVideoDevices = true
        return v
    }
    func updateUIView(_ v: AVRoutePickerView, context: Context) {}
}
#endif
