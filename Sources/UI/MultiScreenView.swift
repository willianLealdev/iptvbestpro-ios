import SwiftUI

/// Multitela: até 4 canais ao mesmo tempo (iPad e Apple TV) ou 2 (iPhone). O som sai do canal escolhido.
struct MultiScreenView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var center: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @StateObject private var s0 = PlayerModel()
    @StateObject private var s1 = PlayerModel()
    @StateObject private var s2 = PlayerModel()
    @StateObject private var s3 = PlayerModel()
    @State private var chans: [JObj?] = [nil, nil, nil, nil]
    @State private var audio = 0
    @State private var picking: Int?

    private var count: Int { DeviceInfo.isPhone ? 2 : (Prefs.multiLayout == 2 ? 2 : 4) }
    private var models: [PlayerModel] { [s0, s1, s2, s3] }

    var body: some View {
        GeometryReader { g in
            let landscape = g.size.width > g.size.height
            ZStack(alignment: .topTrailing) {
                Color.black.ignoresSafeArea()
                Group {
                    if count == 2 {
                        if landscape { HStack(spacing: 4) { slot(0); slot(1) } } else { VStack(spacing: 4) { slot(0); slot(1) } }
                    } else {
                        VStack(spacing: 4) {
                            HStack(spacing: 4) { slot(0); slot(1) }
                            HStack(spacing: 4) { slot(2); slot(3) }
                        }
                    }
                }
                .ignoresSafeArea()
                #if os(iOS)
                Button { close() } label: {
                    Image(systemName: "xmark").font(.system(size: 18, weight: .bold)).foregroundColor(.white).frame(width: 40, height: 40)
                        .background(Circle().fill(Color.black.opacity(0.6)))
                }
                .padding(12)
                #endif
            }
        }
        .onAppear { restore() }
        .onDisappear { models.forEach { $0.stop() }; save() }
        .sheet(isPresented: Binding(get: { picking != nil }, set: { if !$0 { picking = nil } })) {
            ChannelPicker { c in
                if let i = picking { set(i, c) }
                picking = nil
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .bpStopPlayback)) { _ in close() }
        #if os(tvOS)
        .onExitCommand { close() }
        #endif
    }

    private func close() {
        models.forEach { $0.stop() }
        save()
        center.multiscreen = false
        dismiss()
    }

    @ViewBuilder private func slot(_ i: Int) -> some View {
        let m = models[i]
        Button {
            if chans[i] == nil { picking = i } else { setAudio(i) }
        } label: {
            ZStack {
                Color(white: 0.06)
                if let c = chans[i] {
                    VideoSurface(model: m)
                    VStack {
                        HStack(spacing: 6) {
                            Image(systemName: audio == i ? "speaker.wave.2.fill" : "speaker.slash.fill").font(.system(size: UIScale.small))
                            Text(c.s("name")).font(.system(size: UIScale.small, weight: .semibold)).lineLimit(1)
                            Spacer(minLength: 0)
                        }
                        .foregroundColor(.white).padding(8).background(Color.black.opacity(0.5))
                        Spacer()
                        if m.state == .loading { Spinner() }
                        if let msg = m.message { Text(msg).font(.system(size: UIScale.small)).foregroundColor(.white) }
                        Spacer()
                    }
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill").font(.system(size: UIScale.v(36, 44, 80))).foregroundColor(app.brand.accent)
                        Text(t("multi_add")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.75))
                    }
                }
            }
            .overlay(Rectangle().stroke(audio == i && chans[i] != nil ? app.brand.accent : Color.clear, lineWidth: 3))
        }
        .buttonStyle(TileStyle(radius: 2))
        .contextMenu {
            Button { picking = i } label: { Label(t("multi_change"), systemImage: "arrow.left.arrow.right") }
            if chans[i] != nil {
                Button { setAudio(i) } label: { Label(t("multi_audio"), systemImage: "speaker.wave.2") }
                Button(role: .destructive) { models[i].stop(); chans[i] = nil; save() } label: { Label(t("remove"), systemImage: "xmark") }
            }
        }
        #if os(iOS)
        .simultaneousGesture(LongPressGesture(minimumDuration: 0.6).onEnded { _ in picking = i })
        #endif
    }

    private func set(_ i: Int, _ c: JObj) {
        guard let x = app.xtream else { return }
        chans[i] = c
        models[i].muted = i != audio
        models[i].playLive(x, id: c.s("stream_id"))
        if chans.compactMap({ $0 }).count == 1 { setAudio(i) }
        save()
    }

    private func setAudio(_ i: Int) {
        audio = i
        for (k, m) in models.enumerated() { m.muted = k != i }
    }

    // lembra os canais da multitela
    private func save() { Prefs.setJSON("pl_multi", chans.map { $0 ?? [:] }) }
    private func restore() {
        guard let l = Prefs.json("pl_multi") as? [JObj], let x = app.xtream else { return }
        for (i, c) in l.prefix(count).enumerated() where !c.s("stream_id").isEmpty {
            chans[i] = c
            models[i].muted = i != audio
            models[i].playLive(x, id: c.s("stream_id"))
        }
    }
}

/// Escolher um canal (categorias → canais)
struct ChannelPicker: View {
    let onPick: (JObj) -> Void
    @EnvironmentObject var app: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var cats: [JObj] = []
    @State private var chans: [JObj] = []
    @State private var catName = ""
    @State private var loading = true

    var body: some View {
        ZStack {
            BrandBackground()
            VStack(spacing: 0) {
                TopBar(title: catName.isEmpty ? t("ch_title") : catName, onBack: { if !catName.isEmpty { catName = ""; chans = [] } else { dismiss() } })
                ScrollView {
                    LazyVStack(spacing: UIScale.v(6, 8, 14)) {
                        if loading { Spinner().padding() }
                        if catName.isEmpty {
                            if !Library.favList("live").isEmpty {
                                Button { catName = t("favorites"); chans = Library.favList("live") } label: { Label(t("favorites"), systemImage: "star.fill").font(.system(size: UIScale.body)) }
                                    .buttonStyle(RowStyle())
                            }
                            ForEach(Array(cats.enumerated()), id: \.offset) { _, c in
                                Button { Task { await open(c) } } label: { Text(c.s("category_name")).font(.system(size: UIScale.body)).lineLimit(1) }
                                    .buttonStyle(RowStyle())
                            }
                        } else {
                            ForEach(Array(chans.enumerated()), id: \.offset) { _, c in
                                Button { onPick(c); dismiss() } label: {
                                    HStack(spacing: 10) {
                                        RemoteImage(url: c.s("stream_icon"), fill: false, placeholder: "tv").frame(width: 40, height: 30)
                                        Text(c.s("name")).font(.system(size: UIScale.body)).lineLimit(1)
                                        Spacer(minLength: 0)
                                    }
                                }
                                .buttonStyle(RowStyle())
                            }
                        }
                    }
                    .padding(UIScale.pad)
                }
            }
        }
        .task {
            guard let x = app.xtream else { return }
            cats = filterCategories((try? await x.list("get_live_categories", playlistID: app.playlistID)) ?? []).filter { !Config.isAdult($0.s("category_name")) || AdultLock.shared.unlocked }
            loading = false
        }
    }

    private func open(_ c: JObj) async {
        guard let x = app.xtream else { return }
        loading = true
        catName = c.s("category_name")
        chans = (try? await x.list("get_live_streams", ["category_id": c.s("category_id")], playlistID: app.playlistID)) ?? []
        loading = false
    }
}
