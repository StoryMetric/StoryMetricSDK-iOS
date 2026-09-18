import Foundation

/// Marker protocol the `@SMEvents`-generated `Log` conforms to; it carries the
/// built-in `purchase` capture.
public protocol SMLogSurface {}

extension SM {

    /// The param ids the built-in `purchase` event fills from StoreKit. They're the
    /// transaction's to state, so a caller's params can't use them — those entries
    /// are dropped. The whole vocabulary is reserved whether or not a given
    /// transaction supplies the value: a one-time purchase has no `period`, and that
    /// absence is a fact, not a gap to fill.
    public static let purchaseParamIDs: Set<String> = [
        "product_id",
        "transaction_id",
        "original_transaction_id",
        "is_renewal",
        "price",
        "currency",
        "period",
        "is_trial",
    ]
}

#if canImport(StoreKit)
import StoreKit

public extension SMLogSurface {

    /// Captures a completed StoreKit 2 purchase as the built-in `purchase` event.
    /// Idempotent — the same transaction logged twice collapses to one row.
    ///
    /// `params` rides alongside the transaction's own fields, for the app state that
    /// made the purchase worth analyzing — which paywall, which experiment arm, how
    /// far into onboarding. Unlike declared events these are unvalidated: nothing
    /// checks the ids or types, so a typo becomes a new column rather than an error.
    /// Keys in the built-in vocabulary are dropped; see `SM.purchaseParamIDs`.
    ///
    /// Renewals are captured too, stamped `is_renewal`. To keep them out, gate a
    /// `Transaction.updates` listener on `originalID == id`.
    static func purchase(_ transaction: Transaction, params: [String: SM.ParamValue] = [:]) {
        SM._recordPurchase(transaction, params: params)
    }

    /// Adds what the transaction can't supply: subscription `period` and `is_trial`.
    ///
    /// `params` behaves as in `purchase(_:params:)`.
    static func purchase(
        _ transaction: Transaction,
        product: Product,
        params: [String: SM.ParamValue] = [:]
    ) {
        SM._recordPurchase(transaction, product: product, params: params)
    }
}

extension SM {

    /// Not for direct use — backs `SM.log.purchase(_:params:)`.
    public static func _recordPurchase(
        _ transaction: Transaction,
        params: [String: ParamValue] = [:]
    ) {
        deliver(PurchaseFacts(transaction), custom: params)
    }

    /// Not for direct use — backs `SM.log.purchase(_:product:params:)`.
    public static func _recordPurchase(
        _ transaction: Transaction,
        product: Product,
        params: [String: ParamValue] = [:]
    ) {
        deliver(PurchaseFacts(transaction, product: product), custom: params)
    }

    private static func deliver(_ facts: PurchaseFacts, custom: [String: ParamValue]) {
        Core.shared.recordPurchase(
            params: facts.params(custom: custom),
            transactionID: facts.transactionID,
            isSandbox: facts.isSandbox
        )
    }
}

struct PurchaseFacts {
    let productID: String
    let transactionID: String
    let originalTransactionID: String
    let isRenewal: Bool
    let price: Double?
    let currencyCode: String?
    /// nil for one-time purchases and for transaction-only capture.
    let period: String?
    /// nil when capturing without the `Product`.
    let isTrial: Bool?
    let isSandbox: Bool

    init(
        productID: String,
        transactionID: String,
        originalTransactionID: String,
        isRenewal: Bool,
        price: Double?,
        currencyCode: String?,
        period: String?,
        isTrial: Bool?,
        isSandbox: Bool
    ) {
        self.productID = productID
        self.transactionID = transactionID
        self.originalTransactionID = originalTransactionID
        self.isRenewal = isRenewal
        self.price = price
        self.currencyCode = currencyCode
        self.period = period
        self.isTrial = isTrial
        self.isSandbox = isSandbox
    }

    /// The transaction's own fields, over any caller params that survived sanitizing.
    /// The transaction is the source of truth; a caller can add to the payload but
    /// never restate it.
    func params(custom: [String: SM.ParamValue] = [:]) -> [String: SM.ParamValue] {
        var params = PurchaseFacts.sanitize(custom)
        params["product_id"] = .string(productID)
        params["transaction_id"] = .string(transactionID)
        params["original_transaction_id"] = .string(originalTransactionID)
        params["is_renewal"] = .bool(isRenewal)
        if let price { params["price"] = .double(price) }
        if let currencyCode { params["currency"] = .string(currencyCode) }
        if let period { params["period"] = .string(period) }
        if let isTrial { params["is_trial"] = .bool(isTrial) }
        return params
    }

    /// Drops what a caller may not send: the built-in vocabulary, and empty ids.
    /// Each drop is a mistake worth hearing about, so each one logs.
    static func sanitize(_ custom: [String: SM.ParamValue]) -> [String: SM.ParamValue] {
        guard !custom.isEmpty else { return [:] }

        var kept: [String: SM.ParamValue] = [:]
        kept.reserveCapacity(custom.count)
        for (id, value) in custom {
            guard !id.isEmpty else {
                Diag.error("`purchase` was sent a param with an empty id — dropped")
                continue
            }
            guard !SM.purchaseParamIDs.contains(id) else {
                Diag.error("`purchase`.`\(id)` comes from the transaction and can't be overridden — dropped")
                continue
            }
            kept[id] = value
        }
        return kept
    }
}

extension PurchaseFacts {

    init(_ t: Transaction) {
        self.init(t, product: nil)
    }

    init(_ t: Transaction, product: Product) {
        self.init(t, product: .some(product))
    }

    private init(_ t: Transaction, product: Product?) {
        var period: String?
        var isTrial: Bool?
        if let subscription = product?.subscription {
            period = PurchaseFacts.normalize(subscription.subscriptionPeriod)
            isTrial = t.offerType == .introductory
                && subscription.introductoryOffer?.paymentMode == .freeTrial
        }

        self.init(
            productID: t.productID,
            transactionID: String(t.id),
            originalTransactionID: String(t.originalID),
            isRenewal: t.originalID != t.id,
            price: t.price.map { NSDecimalNumber(decimal: $0).doubleValue },
            currencyCode: t.currency?.identifier,
            period: period,
            isTrial: isTrial,
            isSandbox: t.environment != .production
        )
    }

    static func normalize(_ p: Product.SubscriptionPeriod) -> String {
        switch (p.unit, p.value) {
        case (.year, _):      return "annual"
        case (.month, 1):     return "monthly"
        case (.month, let n): return "\(n)_month"
        case (.week, _):      return "weekly"
        case (.day, _):       return "daily"
        @unknown default:     return "unknown"
        }
    }
}
#endif
