import StoreKit

/// Assinatura anual pela Apple (StoreKit 2). Só aparece para cliente direto — aparelho de revenda renova com a revenda.
/// A compra é conferida pelo painel (helper apple_iap), que ativa o aparelho até o vencimento da assinatura.
/// Renovação, cancelamento e reembolso chegam ao painel pelos avisos da Apple (apple_notify.php).
@MainActor
final class Purchases: ObservableObject {
    static let shared = Purchases()

    @Published var product: Product?
    @Published var busy = false
    private var updates: Task<Void, Never>?

    var price: String { product?.displayPrice ?? "" }

    func start() {
        updates?.cancel()
        // renovações e compras aprovadas depois (ex.: "Pedir para comprar") chegam aqui
        updates = Task {
            for await result in Transaction.updates {
                await self.handle(result, silent: true)
            }
        }
        Task { await loadProduct() }
        #if os(iOS)
        // Compra começada na página do app na App Store (sem abrir o app):
        // aparelho de revenda nunca compra pela Apple — renova com a revenda
        if #available(iOS 16.4, *) {
            intents?.cancel()
            intents = Task {
                for await intent in PurchaseIntent.intents {
                    await self.handleIntent(intent)
                }
            }
        }
        #endif
    }

    #if os(iOS)
    private var intents: Task<Void, Never>?

    @available(iOS 16.4, *)
    private func handleIntent(_ intent: PurchaseIntent) async {
        let app = AppState.shared
        if !app.canPurchase {
            app.show(t("iap_reseller"), seconds: 6)
            return
        }
        guard intent.product.id == Config.productYear else { return }
        product = intent.product
        if let e = await buy() { app.show(e, seconds: 5) }
    }
    #endif

    func loadProduct() async {
        if product != nil { return }
        product = try? await Product.products(for: [Config.productYear]).first
    }

    /// Compra. Devolve a mensagem de erro (ou nil quando deu certo / o cliente desistiu).
    func buy() async -> String? {
        await loadProduct()
        guard let product else { return t("iap_unavailable") }
        busy = true
        defer { busy = false }
        do {
            let r = try await product.purchase(options: [.appAccountToken(Self.accountToken)])
            switch r {
            case .success(let v): return await handle(v, silent: false)
            case .pending: return t("iap_pending")
            case .userCancelled: return nil
            @unknown default: return nil
            }
        } catch {
            return t("iap_fail")
        }
    }

    /// Restaurar compras (a Apple exige o botão): manda a assinatura ativa para o painel
    func restore() async -> String? {
        busy = true
        defer { busy = false }
        try? await AppStore.sync()
        var found: VerificationResult<Transaction>?
        for await r in Transaction.currentEntitlements {
            if case .verified(let tx) = r, tx.productID == Config.productYear { found = r }
        }
        guard let found else { return t("iap_none") }
        return await handle(found, silent: false)
    }

    @discardableResult
    private func handle(_ v: VerificationResult<Transaction>, silent: Bool) async -> String? {
        guard case .verified(let tx) = v else { return silent ? nil : t("iap_fail") }
        let err = await AppState.shared.applePurchased(jws: v.jwsRepresentation)
        if err == nil || tx.revocationDate != nil { await tx.finish() }
        return silent ? nil : err
    }

    /// Identifica o aparelho na compra (o mesmo valor sempre para este aparelho)
    static var accountToken: UUID {
        let d = Array(DeviceID.value.utf8)
        var b = [UInt8](repeating: 0, count: 16)
        for (i, c) in d.enumerated() { b[i % 16] = b[i % 16] &* 31 &+ c }
        b[6] = (b[6] & 0x0f) | 0x40
        b[8] = (b[8] & 0x3f) | 0x80
        return UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
