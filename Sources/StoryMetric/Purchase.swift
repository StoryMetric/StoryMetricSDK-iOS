import Foundation

/// Marker protocol the `@SMEvents`-generated `Log` conforms to; it carries the
/// built-in `purchase` capture.
public protocol SMLogSurface {}

#if canImport(StoreKit)
import StoreKit

public extension SMLogSurface {

    /// Captures a completed StoreKit 2 purchase as the built-in `purchase` event.
    /// Idempotent — the same transaction logged twice collapses to one row.
    ///
    /// Renewals are captured too, stamped `is_renewal`. To keep them out, gate a
    /// `Transaction.updates` listener on `originalID == id`.
    static func purchase(_ transaction: Transaction) {
        SM._recordPurchase(transaction)
    }

    /// Adds what the transaction can't supply: subscription `period` and `is_trial`.
    static func purchase(_ transaction: Transaction, product: Product) {
        SM._recordPurchase(transaction, product: product)
    }
}

extension SM {

    /// Not for direct use — backs `SM.log.purchase(_:)`.
    public static func _recordPurchase(_ transaction: Transaction) {
        deliver(PurchaseFacts(transaction))
    }

    /// Not for direct use — backs `SM.log.purchase(_:product:)`.
    public static func _recordPurchase(_ transaction: Transaction, product: Product) {
        deliver(PurchaseFacts(transaction, product: product))
    }

    private static func deliver(_ facts: PurchaseFacts) {
        Core.shared.recordPurchase(
            params: facts.params(),
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

    func params() -> [String: SM.ParamValue] {
        var params: [String: SM.ParamValue] = [
            "product_id": .string(productID),
            "transaction_id": .string(transactionID),
            "original_transaction_id": .string(originalTransactionID),
            "is_renewal": .bool(isRenewal),
        ]
        if let price { params["price"] = .double(price) }
        if let currencyCode { params["currency"] = .string(currencyCode) }
        if let period { params["period"] = .string(period) }
        if let isTrial { params["is_trial"] = .bool(isTrial) }
        return params
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
