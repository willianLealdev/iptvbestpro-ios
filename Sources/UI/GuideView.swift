import SwiftUI

/// Guia de programação (EPG): os canais da categoria com o que passa agora e a seguir
struct GuideView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @State private var cats: [JObj] = []
    @State private var catID = ""
    @State private var chans: [JObj] = []
    @State private var loading = true
    @State private var catchup: Item?

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("guide"), onBack: { dismiss() })
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if !Library.favList("live").isEmpty { chip(SpecialCat.fav, "★ " + t("favorites")) }
                    ForEach(Array(cats.enumerated()), id: \.offset) { _, c in chip(c.s("category_id"), c.s("category_name")) }
                }
                .padding(.horizontal, UIScale.pad).padding(.vertical, 8)
            }
            #if os(tvOS)
            .focusSection()
            #endif
            if loading { Spinner().padding() }
            ScrollView {
                LazyVStack(spacing: UIScale.v(8, 10, 18)) {
                    ForEach(Array(chans.enumerated()), id: \.offset) { i, c in
                        GuideRow(channel: c, onPlay: { play(i) }, onCatchup: { catchup = Item(c) })
                    }
                    if !loading && chans.isEmpty { EmptyText(text: t("empty")) }
                }
                .padding(.horizontal, UIScale.pad).padding(.bottom, 20)
            }
        }
        .task { await load() }
        .navigationDestination(isPresented: Binding(get: { catchup != nil }, set: { if !$0 { catchup = nil } })) {
            if let c = catchup { CatchupView(channel: c).screen() }
        }
    }

    private func chip(_ id: String, _ name: String) -> some View {
        Button { Task { await open(id) } } label: {
            Text(name).font(.system(size: UIScale.small, weight: .semibold)).lineLimit(1)
                .padding(.horizontal, 14).padding(.vertical, UIScale.v(8, 9, 14))
                .background(Capsule().fill(catID == id ? app.brand.accent.opacity(0.85) : Color.white.opacity(0.1)))
                .foregroundColor(catID == id && app.brand.accentIsLight ? .black : .white)
        }
        .buttonStyle(TileStyle(radius: 30))
    }

    private func load() async {
        guard let x = app.xtream else { return }
        cats = filterCategories((try? await x.list("get_live_categories", playlistID: app.playlistID)) ?? []).filter { !Config.isAdult($0.s("category_name")) || AdultLock.shared.unlocked }
        let start = Library.lastLive?.s("cat") ?? ""
        await open(!start.isEmpty && (start == SpecialCat.fav || cats.contains { $0.s("category_id") == start }) ? start : (cats.first?.s("category_id") ?? ""))
    }

    private func open(_ id: String) async {
        catID = id
        loading = true
        chans = []
        if id == SpecialCat.fav { chans = Library.favList("live") }
        else if let x = app.xtream, !id.isEmpty { chans = (try? await x.list("get_live_streams", ["category_id": id], playlistID: app.playlistID)) ?? [] }
        loading = false
    }

    private func play(_ i: Int) {
        let c = chans[i]
        Library.lastLive = ["cat": catID, "sid": c.s("stream_id")]
        Library.lastPlay = ["kind": "live", "cat": catID, "sid": c.s("stream_id"), "name": c.s("name"), "icon": c.s("stream_icon"), "list": Array(chans.prefix(400))]
        player.play(PlayRequest(kind: .live, title: c.s("name"), items: chans, index: i, catID: catID))
    }
}

struct GuideRow: View {
    let channel: JObj
    let onPlay: () -> Void
    let onCatchup: () -> Void
    @EnvironmentObject var app: AppState
    @State private var listings: [JObj] = []

    var body: some View {
        HStack(spacing: UIScale.v(8, 10, 18)) {
            Button(action: onPlay) {
                HStack(spacing: 8) {
                    RemoteImage(url: channel.s("stream_icon"), fill: false, placeholder: "tv").frame(width: UIScale.v(40, 48, 80), height: UIScale.v(30, 36, 60))
                    Text(channel.s("name")).font(.system(size: UIScale.small, weight: .semibold)).lineLimit(2).foregroundColor(.white)
                    Spacer(minLength: 0)
                }
                .padding(8)
                .frame(width: UIScale.v(150, 220, 380), height: UIScale.v(64, 70, 110))
                .cardBG(Color.white.opacity(0.08))
            }
            .buttonStyle(TileStyle())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if listings.isEmpty {
                        Text(t("no_epg")).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.5)).padding(.horizontal, 8)
                    }
                    ForEach(Array(listings.enumerated()), id: \.offset) { i, l in
                        let st = Date(timeIntervalSince1970: l.d("start_timestamp")), en = Date(timeIntervalSince1970: l.d("stop_timestamp"))
                        Button(action: onPlay) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(Fmt.hm(st) + " – " + Fmt.hm(en)).font(.system(size: UIScale.small * 0.9)).foregroundColor(i == 0 ? app.brand.accent : .white.opacity(0.6))
                                Text(l.s("title").base64Decoded).font(.system(size: UIScale.small, weight: i == 0 ? .bold : .regular)).foregroundColor(.white).lineLimit(2)
                            }
                            .padding(8)
                            .frame(width: UIScale.v(170, 230, 360), height: UIScale.v(64, 70, 110), alignment: .topLeading)
                            .cardBG(i == 0 ? app.brand.accent.opacity(0.18) : Color.white.opacity(0.06))
                        }
                        .buttonStyle(TileStyle())
                    }
                    if channel.s("tv_archive") == "1" {
                        Button(action: onCatchup) {
                            Label(t("catchup"), systemImage: "clock.arrow.circlepath").font(.system(size: UIScale.small, weight: .semibold)).foregroundColor(.white)
                                .padding(8).frame(height: UIScale.v(64, 70, 110)).cardBG(Color.white.opacity(0.1))
                        }
                        .buttonStyle(TileStyle())
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .task {
            if let x = app.xtream { listings = await EPG.short(x, id: channel.s("stream_id"), limit: 4) }
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }
}

/// Catch-up: programas que já passaram e ficaram gravados no servidor
struct CatchupView: View {
    let channel: Item
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @State private var listings: [JObj] = []
    @State private var loading = true

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("catchup") + " · " + channel.name, onBack: { dismiss() })
            if loading { Spinner().padding() }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: UIScale.v(6, 8, 14)) {
                    ForEach(days, id: \.self) { day in
                        Text(day).font(.system(size: UIScale.body, weight: .bold)).foregroundColor(app.brand.accent).padding(.top, 10)
                        ForEach(Array(listings.filter { dayOf($0) == day }.enumerated()), id: \.offset) { _, l in
                            let st = Date(timeIntervalSince1970: l.d("start_timestamp")), en = Date(timeIntervalSince1970: l.d("stop_timestamp"))
                            Button { play(l) } label: {
                                HStack(spacing: 12) {
                                    Text(Fmt.hm(st)).font(.system(size: UIScale.small, weight: .bold, design: .monospaced)).frame(minWidth: UIScale.v(54, 60, 110), alignment: .leading)
                                    Text(l.s("title").base64Decoded).font(.system(size: UIScale.body)).lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text(Fmt.time(en.timeIntervalSince(st))).font(.system(size: UIScale.small)).foregroundColor(.white.opacity(0.6))
                                    Image(systemName: "play.circle.fill")
                                }
                            }
                            .buttonStyle(RowStyle())
                        }
                    }
                    if !loading && listings.isEmpty { EmptyText(text: t("catchup_none")) }
                }
                .padding(.horizontal, UIScale.pad).padding(.bottom, 20)
            }
        }
        .task {
            guard let x = app.xtream else { return }
            let now = Date().timeIntervalSince1970
            let all = await EPG.table(x, id: channel.id)
            listings = Array(all.filter { $0.s("has_archive") == "1" && $0.d("stop_timestamp") < now }.reversed())
            loading = false
        }
    }

    private func dayOf(_ l: JObj) -> String { Fmt.date(Date(timeIntervalSince1970: l.d("start_timestamp"))) }
    private var days: [String] {
        var seen = Set<String>(), out: [String] = []
        for l in listings { let d = dayOf(l); if seen.insert(d).inserted { out.append(d) } }
        return out
    }

    private func play(_ l: JObj) {
        guard let x = app.xtream else { return }
        let st = Date(timeIntervalSince1970: l.d("start_timestamp")), en = Date(timeIntervalSince1970: l.d("stop_timestamp"))
        let mins = Int((en.timeIntervalSince(st) / 60).rounded(.up))
        guard let u = x.timeshift(channel.id, start: st, minutes: mins, serverTZ: app.serverTimeZone) else { return }
        player.play(PlayRequest(kind: .catchup, title: channel.name + " · " + l.s("title").base64Decoded, url: u))
    }
}
