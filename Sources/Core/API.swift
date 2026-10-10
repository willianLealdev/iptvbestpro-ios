import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum APIError: Error {
    case network        // sem internet / tempo esgotado
    case server(Int)    // o servidor respondeu com erro
    case invalid        // resposta que não dá para ler
}

/// Dados do aparelho mandados em toda chamada ao painel (aparecem na lista de Dispositivos).
/// Lidos uma vez na abertura do app (o UIDevice só pode ser lido na thread principal).
enum DeviceInfo {
    nonisolated(unsafe) static var platform = "iphone"
    nonisolated(unsafe) static var platformName = "iPhone"
    nonisolated(unsafe) static var model = ""
    nonisolated(unsafe) static var osVersion = ""
    nonisolated(unsafe) static var isPhone = false
    static var isTV: Bool {
        #if os(tvOS)
        return true
        #else
        return false
        #endif
    }

    @MainActor static func setup() {
        #if os(tvOS)
        platform = "apple_tv"; platformName = "Apple TV"; isPhone = false
        #else
        let pad = UIDevice.current.userInterfaceIdiom == .pad
        platform = pad ? "ipad" : "iphone"; platformName = pad ? "iPad" : "iPhone"; isPhone = !pad
        #endif
        osVersion = UIDevice.current.systemVersion
        var u = utsname()
        uname(&u)
        let m = withUnsafePointer(to: &u.machine) { $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) } }
        model = m.isEmpty ? platformName : m
    }
}

/// Comunicação com o painel (api.php) e com o servidor IPTV da lista (player_api.php)
enum API {
    static let session: URLSession = {
        let c = URLSessionConfiguration.default
        c.timeoutIntervalForRequest = 30
        c.timeoutIntervalForResource = 90
        c.httpAdditionalHeaders = ["User-Agent": Config.userAgent]
        c.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: c)
    }()

    private static func send(_ req: URLRequest) async throws -> Any {
        let data: Data, resp: URLResponse
        do { (data, resp) = try await session.data(for: req) } catch { throw APIError.network }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.server(code) }
        guard let j = JSONUtil.parse(data) else { throw APIError.invalid }
        return j
    }

    /// Painel: os dados vão em JSON base64 no campo "data" (o mesmo formato dos outros apps)
    static func panel(_ helper: String, _ extra: [String: Any] = [:]) async throws -> Any {
        var o: [String: Any] = [
            "helper_name": helper, "application_id": Config.appID, "device_id": DeviceID.value,
            "platform": DeviceInfo.platform, "device_model": DeviceInfo.model, "os_version": DeviceInfo.osVersion,
            "app_version": Config.version, "app_name": Config.appName,
        ]
        for (k, v) in extra { o[k] = v }
        let b64 = Data(JSONUtil.string(o).utf8).base64EncodedString()
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        var req = URLRequest(url: URL(string: Config.server + "/api.php")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = ("data=" + (b64.addingPercentEncoding(withAllowedCharacters: allowed) ?? b64)).data(using: .utf8)
        req.timeoutInterval = 60
        let j = try await send(req)
        if let d = j as? JObj, let inner = d["NEMOSOFTS_APP"] { return inner }
        return j
    }

    /// Primeiro item da resposta do painel (device_status, device_link, apple_iap)
    static func panelFirst(_ helper: String, _ extra: [String: Any] = [:]) async throws -> JObj {
        let j = try await panel(helper, extra)
        if let arr = j as? [JObj] { return arr.first ?? [:] }
        return j as? JObj ?? [:]
    }

    /// Busca no servidor (o painel procura na lista inteira e devolve só o que tem o texto)
    static func tvSearch(playlistID: String, type: String, text: String) async -> [JObj] {
        let q: [String: Any] = ["device_id": DeviceID.value, "application_id": Config.appID, "playlist_id": Int(playlistID) ?? 0,
                                "action": "search", "params": ["type": type, "text": text]]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        var req = URLRequest(url: URL(string: Config.server + "/tv_xtream.php")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let qs = JSONUtil.string(q)
        req.httpBody = ("q=" + (qs.addingPercentEncoding(withAllowedCharacters: allowed) ?? qs)).data(using: .utf8)
        return ((try? await send(req)) as? [JObj]) ?? []
    }
}

/// Servidor IPTV (Xtream Codes) da lista em uso
struct Xtream {
    let apiBase: String     // DNS que o painel indicou para a lista
    let streamBase: String  // servidor dos vídeos (o que o servidor IPTV informa no login)
    let user: String
    let pass: String

    func url(_ action: String, _ params: [String: String] = [:]) -> URL? {
        var c = URLComponents(string: apiBase + "/player_api.php")
        var q = [URLQueryItem(name: "username", value: user), URLQueryItem(name: "password", value: pass)]
        if !action.isEmpty { q.append(URLQueryItem(name: "action", value: action)) }
        for (k, v) in params.sorted(by: { $0.key < $1.key }) { q.append(URLQueryItem(name: k, value: v)) }
        c?.queryItems = q
        return c?.url
    }

    func call(_ action: String, _ params: [String: String] = [:]) async throws -> Any {
        guard let u = url(action, params) else { throw APIError.invalid }
        var req = URLRequest(url: u)
        req.setValue(Config.userAgent, forHTTPHeaderField: "User-Agent")
        let data: Data, resp: URLResponse
        do { (data, resp) = try await API.session.data(for: req) } catch { throw APIError.network }
        let code = (resp as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(code) else { throw APIError.server(code) }
        guard let j = JSONUtil.parse(data) else { throw APIError.invalid }
        return j
    }

    /// Lista (categorias, canais, filmes, séries): guarda no aparelho pelo tempo escolhido em Configurações
    func list(_ action: String, _ params: [String: String] = [:], playlistID: String, fresh: Bool = false) async throws -> [JObj] {
        let key = playlistID + "|" + action + "|" + params.sorted(by: { $0.key < $1.key }).map { $0.key + "=" + $0.value }.joined(separator: "&")
        if !fresh, let cached = Catalog.get(key) as? [JObj] { return cached }
        let j = try await call(action, params)
        let arr: [JObj]
        if let a = j as? [JObj] { arr = a }
        else if let d = j as? JObj { arr = d.values.compactMap { $0 as? JObj } } // alguns servidores mandam objeto em vez de lista
        else { arr = [] }
        Catalog.put(key, arr)
        return arr
    }

    // Endereços dos vídeos
    private var u: String { user.urlPath }
    private var p: String { pass.urlPath }
    func live(_ id: String, ext: String = "m3u8") -> URL? { URL(string: "\(streamBase)/live/\(u)/\(p)/\(id).\(ext)") }
    func movie(_ id: String, ext: String) -> URL? { URL(string: "\(streamBase)/movie/\(u)/\(p)/\(id).\(ext.isEmpty ? "mp4" : ext)") }
    func episode(_ id: String, ext: String) -> URL? { URL(string: "\(streamBase)/series/\(u)/\(p)/\(id).\(ext.isEmpty ? "mp4" : ext)") }
    /// Catch-up (programa que já passou): início no fuso do servidor, duração em minutos
    func timeshift(_ id: String, start: Date, minutes: Int, serverTZ: TimeZone) -> URL? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = serverTZ
        f.dateFormat = "yyyy-MM-dd:HH-mm"
        return URL(string: "\(streamBase)/timeshift/\(u)/\(p)/\(max(1, minutes))/\(f.string(from: start))/\(id).ts")
    }
}

/// Catálogo guardado no aparelho (memória + arquivo), válido pelas horas de "Atualização automática"
enum Catalog {
    private static var mem: [String: (Date, Any)] = [:]
    private static let lock = NSLock()
    private static var dir: URL {
        let d = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("catalog", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }
    private static func file(_ key: String) -> URL {
        let safe = Data(key.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-")
        return dir.appendingPathComponent(String(safe.prefix(180)) + ".json")
    }
    static var ttl: TimeInterval { TimeInterval(max(1, Prefs.autoUpdateHours) * 3600) }

    static func get(_ key: String) -> Any? {
        lock.lock(); defer { lock.unlock() }
        if let (t, v) = mem[key], Date().timeIntervalSince(t) < ttl { return v }
        let f = file(key)
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: f.path), let m = attrs[.modificationDate] as? Date,
              Date().timeIntervalSince(m) < ttl, let d = try? Data(contentsOf: f), let v = JSONUtil.parse(d) else { return nil }
        mem[key] = (m, v)
        return v
    }
    static func put(_ key: String, _ v: Any) {
        lock.lock(); defer { lock.unlock() }
        mem[key] = (Date(), v)
        if JSONSerialization.isValidJSONObject(v), let d = try? JSONSerialization.data(withJSONObject: v) { try? d.write(to: file(key), options: .atomic) }
    }
    static func clearMemory() { lock.lock(); mem = [:]; lock.unlock() }
    static func clearDisk() {
        clearMemory()
        try? FileManager.default.removeItem(at: dir)
        URLCache.shared.removeAllCachedResponses()
        ImageCache.shared.clear()
    }
    static func diskSize() -> Int64 {
        let fm = FileManager.default
        let root = fm.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        var total: Int64 = 0
        if let e = fm.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) {
            for case let f as URL in e { total += Int64((try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        }
        return total
    }
}
