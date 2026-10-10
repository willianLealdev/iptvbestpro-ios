import SwiftUI

/// Busca de canais, filmes e séries (o painel procura na lista inteira e devolve só o que tem o texto)
struct SearchView: View {
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @State private var text = Library.lastSearch
    @State private var live: [JObj] = []
    @State private var movies: [JObj] = []
    @State private var series: [JObj] = []
    @State private var searching = false
    @State private var searched = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 0) {
            TopBar(title: t("search"), onBack: { dismiss() })
            HStack(spacing: 10) {
                TextField(t("search_hint"), text: $text)
                    .font(.system(size: UIScale.body))
                    .disableAutocorrection(true)
                    .focused($focused)
                    .submitLabel(.search)
                    .onSubmit { run() }
                    .padding(UIScale.v(12, 12, 20))
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.1)))
                Button { run() } label: { Image(systemName: "magnifyingglass") }.buttonStyle(PillStyle(primary: true))
            }
            .padding(.horizontal, UIScale.pad).padding(.vertical, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: UIScale.v(10, 14, 24)) {
                    if searching { HStack { Spinner(); Text(t("searching")).foregroundColor(.white.opacity(0.7)) }.padding() }
                    if !live.isEmpty {
                        section(t("ch_title"), live.count)
                        ForEach(Array(live.enumerated()), id: \.offset) { i, c in
                            Button { play(i) } label: {
                                HStack(spacing: 10) {
                                    RemoteImage(url: c.s("stream_icon"), fill: false, placeholder: "tv").frame(width: UIScale.v(40, 46, 80), height: UIScale.v(30, 34, 56))
                                    Text(c.s("name")).font(.system(size: UIScale.body)).lineLimit(1)
                                    Spacer(minLength: 0)
                                }
                            }
                            .buttonStyle(RowStyle())
                        }
                    }
                    if !movies.isEmpty { section(t("mv_title"), movies.count); posterRow(movies, movie: true) }
                    if !series.isEmpty { section(t("sr_title"), series.count); posterRow(series, movie: false) }
                    if searched && !searching && live.isEmpty && movies.isEmpty && series.isEmpty { EmptyText(text: t("search_none")).frame(height: 200) }
                }
                .padding(.horizontal, UIScale.pad).padding(.bottom, 30)
            }
        }
        .onAppear {
            if text.count >= 2 { run() } else { focused = true }
        }
    }

    private func section(_ title: String, _ n: Int) -> some View {
        Text("\(title) (\(n))").font(.system(size: UIScale.body, weight: .bold)).foregroundColor(app.brand.accent).padding(.top, 8)
    }

    private func posterRow(_ l: [JObj], movie: Bool) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(spacing: UIScale.v(10, 14, 40)) {
                ForEach(Array(l.enumerated()), id: \.offset) { _, it in
                    NavigationLink(value: movie ? Dest.movie(Item(it)) : Dest.show(Item(it))) { PosterCard(item: Item(it)) }
                        .buttonStyle(TileStyle())
                }
            }
            .padding(.vertical, UIScale.v(6, 8, 30)).padding(.horizontal, 4)
        }
        #if os(tvOS)
        .focusSection()
        #endif
    }

    private func run() {
        let q = text.trimmed
        guard q.count >= 2 else { app.show(t("search_hint")); return }
        Library.lastSearch = q
        searching = true; searched = true
        live = []; movies = []; series = []
        let pid = app.playlistID
        Task {
            async let a = API.tvSearch(playlistID: pid, type: "live", text: q)
            async let b = API.tvSearch(playlistID: pid, type: "movie", text: q)
            async let c = API.tvSearch(playlistID: pid, type: "series", text: q)
            let (l, m, s) = await (a, b, c)
            guard text.trimmed == q else { return }
            live = l; movies = m; series = s
            searching = false
        }
    }

    private func play(_ i: Int) {
        let c = live[i]
        Library.lastLive = ["cat": SpecialCat.search, "sid": c.s("stream_id")]
        Library.lastPlay = ["kind": "live", "cat": SpecialCat.search, "sid": c.s("stream_id"), "name": c.s("name"), "icon": c.s("stream_icon"), "list": live]
        player.play(PlayRequest(kind: .live, title: c.s("name"), items: live, index: i, catID: SpecialCat.search))
    }
}

/// Favoritos (canais, filmes e séries) ou Continuar assistindo
struct FavoritesView: View {
    var continueMode = false
    @EnvironmentObject var app: AppState
    @EnvironmentObject var player: PlayerCenter
    @Environment(\.dismiss) private var dismiss
    @State private var tick = 0

    var body: some View {
        let lv = continueMode ? Library.cwList("live") : Library.favList("live")
        let mv = continueMode ? Library.cwList("movie") : Library.favList("movie")
        let sr = continueMode ? Library.cwList("series") : Library.favList("series")
        VStack(spacing: 0) {
            TopBar(title: t(continueMode ? "continue" : "favorites"), onBack: { dismiss() })
            ScrollView {
                VStack(alignment: .leading, spacing: UIScale.v(10, 14, 24)) {
                    if lv.isEmpty && mv.isEmpty && sr.isEmpty { EmptyText(text: t(continueMode ? "cw_empty" : "fav_empty")).frame(height: 240) }
                    if !lv.isEmpty {
                        Text(t("ch_title") + " (\(lv.count))").font(.system(size: UIScale.body, weight: .bold)).foregroundColor(app.brand.accent)
                        ScrollView(.horizontal, showsIndicators: false) {
                            LazyHStack(spacing: UIScale.v(10, 14, 30)) {
                                ForEach(Array(lv.enumerated()), id: \.offset) { i, c in
                                    Button { player.play(PlayRequest(kind: .live, title: c.s("name"), items: lv, index: i, catID: continueMode ? SpecialCat.recent : SpecialCat.fav)) } label: {
                                        VStack(spacing: 8) {
                                            RemoteImage(url: c.s("stream_icon"), fill: false, placeholder: "tv").frame(width: UIScale.v(90, 120, 200), height: UIScale.v(60, 80, 130))
                                            Text(c.s("name")).font(.system(size: UIScale.small)).foregroundColor(.white).lineLimit(1).frame(width: UIScale.v(100, 130, 220))
                                        }
                                        .padding(10).cardBG(Color.white.opacity(0.07))
                                    }
                                    .buttonStyle(TileStyle())
                                    .contextMenu {
                                        if !continueMode { Button(t("fav_del")) { Library.toggleFav("live", c); tick += 1 } }
                                    }
                                }
                            }
                            .padding(.vertical, UIScale.v(6, 8, 30)).padding(.horizontal, 4)
                        }
                        #if os(tvOS)
                        .focusSection()
                        #endif
                    }
                    if !mv.isEmpty { row(t("mv_title"), mv, movie: true) }
                    if !sr.isEmpty { row(t("sr_title"), sr, movie: false) }
                }
                .padding(.horizontal, UIScale.pad).padding(.bottom, 30)
                .id(tick)
            }
        }
    }

    private func row(_ title: String, _ l: [JObj], movie: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title + " (\(l.count))").font(.system(size: UIScale.body, weight: .bold)).foregroundColor(app.brand.accent)
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: UIScale.v(10, 14, 40)) {
                    ForEach(Array(l.enumerated()), id: \.offset) { _, it in
                        NavigationLink(value: movie ? Dest.movie(Item(it)) : Dest.show(Item(it))) {
                            PosterCard(item: Item(it), progress: movie ? min(1, Library.position(movie: Item(it).id) / max(1, Double(it.s("duration_secs")) ?? 5400)) : 0)
                        }
                        .buttonStyle(TileStyle())
                        .contextMenu {
                            Button(t(continueMode ? "remove" : "fav_del")) {
                                if continueMode { Library.cwRemove(movie ? "movie" : "series", Item(it).id) } else { Library.toggleFav(movie ? "movie" : "series", it) }
                                tick += 1
                            }
                        }
                    }
                }
                .padding(.vertical, UIScale.v(6, 8, 30)).padding(.horizontal, 4)
            }
            #if os(tvOS)
            .focusSection()
            #endif
        }
    }
}
