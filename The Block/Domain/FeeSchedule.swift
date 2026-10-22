import Foundation

/// What the buyer would pay on top of the hammer price (spec FEES-1).
struct FeeEstimate: Hashable, Sendable {
    let amount: Int
    let buyerFee: Int
    let documentationFee: Int

    var total: Int { amount + buyerFee + documentationFee }
}

/// Simulated buyer fees, before taxes and transport (spec FEES-1 … FEES-3, Assumptions).
///
/// Buyer fee: $300 under $10,000 · $500 for $10,000–$29,999 · 2 % (rounded to the dollar) at $30,000+;
/// plus a flat $99 documentation fee.
enum FeeSchedule {

    /// Tiered buyer fee for a winning amount in whole dollars.
    static func buyerFee(for amount: Int) -> Int {
        switch amount {
        case ..<Constants.midTierStart: Constants.lowTierFee
        case ..<Constants.percentTierStart: Constants.midTierFee
        default: (amount * Constants.percent + Constants.roundingHalf) / Constants.percentDivisor
        }
    }

    /// Full estimate for paying `amount` (a bid or the Buy Now price).
    static func estimate(for amount: Int) -> FeeEstimate {
        FeeEstimate(amount: amount, buyerFee: buyerFee(for: amount), documentationFee: Constants.documentationFee)
    }

}

private enum Constants {
    static let midTierStart = 10_000
    static let percentTierStart = 30_000
    static let lowTierFee = 300
    static let midTierFee = 500
    static let percent = 2
    static let percentDivisor = 100
    static let roundingHalf = 50
    static let documentationFee = 99
}
