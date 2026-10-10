import Foundation

/// Favoritos, continuar assistindo, posição dos filmes/episódios e o último que o cliente assistiu.
/// Ficam no aparelho, por lista (trocar de lista apaga). kind: live | movie | series
enum Library {
    static func favList(_ kind: String) -> [JObj] { Prefs.json("pl_fav_" + kind) as? [JObj] ?? [] }
    static func favID(_ kind: String, _ it: JObj) -> String {
        kind == "series" ? (it.s("series_id").isEmpty ? it.s("id") : it.s("series_id")) : (it.s("stream_id").isEmpty ? it.s("id") : it.s("stream_id"))
    }
    static func isFav(_ kind: String, _ it: JObj) -> Bool {
        let id = favID(kind, it)
        return favList(kind).contains { favID(kind, $0) == id }
    }
    /// Liga/desliga o favorito. Devolve true quando passou a ser favorito.
    @discardableResult
    static func toggleFav(_ kind: String, _ it: JObj) -> Bool {
        let id = favID(kind, it)
        var l = favList(kind)
        if l.contains(where: { favID(kind, $0) == id }) {
            l.removeAll { favID(kind, $0) == id }
            Prefs.setJSON("pl_fav_" + kind, l)
            return false
        }
        var o: JObj
        switch kind {
        case "series": o = ["series_id": id, "name": it.s("name"), "cover": it.s("cover").isEmpty ? it.s("img") : it.s("cover")]
        case "movie": o = ["stream_id": id, "name": it.s("name"), "stream_icon": it.s("stream_icon").isEmpty ? it.s("img") : it.s("stream_icon"),
                           "container_extension": it.s("container_extension").isEmpty ? "mp4" : it.s("container_extension")]
        default: o = ["stream_id": id, "name": it.s("name"), "stream_icon": it.s("stream_icon"), "epg_channel_id": it.s("epg_channel_id"),
                      "tv_archive": it.s("tv_archive"), "tv_archive_duration": it.s("tv_archive_duration")]
        }
        o["category_name"] = it.s("category_name")
        l.insert(o, at: 0)
        Prefs.setJSON("pl_fav_" + kind, Array(l.prefix(300)))
        return true
    }

    // Continuar assistindo (filmes e séries) e canais recentes
    static func cwList(_ kind: String) -> [JObj] { Prefs.json("pl_cw_" + kind) as? [JObj] ?? [] }
    static func cwAdd(_ kind: String, _ item: JObj) {
        let id = item.s("id")
        var l = cwList(kind).filter { $0.s("id") != id }
        l.insert(item, at: 0)
        Prefs.setJSON("pl_cw_" + kind, Array(l.prefix(max(5, Prefs.recentLimit))))
    }
    static func cwRemove(_ kind: String, _ id: String) {
        Prefs.setJSON("pl_cw_" + kind, cwList(kind).filter { $0.s("id") != id })
    }

    // Posição (segundos) em que o cliente parou
    static func position(movie id: String) -> Double { Double(Prefs.int("pl_pos_m_" + id)) }
    static func position(episode id: String) -> Double { Double(Prefs.int("pl_pos_e_" + id)) }
    static func savePosition(kind: String, id: String, time: Double, duration: Double) {
        let k = (kind == "movie" ? "pl_pos_m_" : "pl_pos_e_") + id
        if duration > 0 && time > duration - 15 { Prefs.del(k); if kind == "movie" { cwRemove("movie", id) } }
        else if time > 5 { Prefs.setInt(k, Int(time)) }
    }

    /// Último que o cliente assistiu (canal, filme ou episódio): o botão "Continuar" da tela inicial abre direto nele
    static var lastPlay: JObj? {
        get { Prefs.json("pl_last_play") as? JObj }
        set { Prefs.setJSON("pl_last_play", newValue) }
    }
    static var lastLive: JObj? {
        get { Prefs.json("pl_last_live") as? JObj }
        set { Prefs.setJSON("pl_last_live", newValue) }
    }
    static var lastSearch: String {
        get { Prefs.str("pl_search") }
        set { Prefs.set("pl_search", newValue) }
    }
}
