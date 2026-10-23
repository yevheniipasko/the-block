//
//  FeeEstimateView.swift
//  The Block
//
//  "Est. total" row with an expandable buyer/documentation fee breakdown,
//  shared by the bid and Buy Now sheets (spec FEES-1, FEES-2).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// "Est. total $X" row with a tap-to-expand fee breakdown and the estimate caption (spec FEES-1, FEES-2).
///
/// Used by the bid entry, the bid review step and the Buy Now confirmation. Amounts never wrap
/// mid-number: each line falls back to a stacked layout when it doesn't fit (spec UX-2).
struct FeeEstimateView: View {

    let estimate: FeeEstimate
    /// Accessibility id prefix, e.g. `bid` → `bid.estimateRow`, `bid.estimateBreakdown`.
    let identifierPrefix: String

    /// Whether the fee breakdown is showing; collapsed by default to keep the sheet short.
    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                totalLine
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Localizable.totalAccessibility(Formatting.currency(estimate.total)))
            .accessibilityHint(isExpanded ? Localizable.hideBreakdownHint : Localizable.showBreakdownHint)
            .accessibilityIdentifier("\(identifierPrefix).estimateRow")

            if isExpanded {
                breakdown
            }

            Text(Localizable.caption)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
        }
        .padding(Spacing.medium)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.fill.quaternary, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    /// Tappable "Est. total $X" line with a chevron that flips when the breakdown is open.
    private var totalLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                    totalTitle
                    totalAmount
                }
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    totalTitle
                    totalAmount
                }
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.down")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.secondary)
                .rotationEffect(.degrees(isExpanded ? Constants.expandedChevronDegrees : 0))
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }

    private var totalTitle: some View {
        Text(Localizable.totalTitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: true, vertical: false)
    }

    private var totalAmount: some View {
        Text(Formatting.currency(estimate.total))
            .font(.headline.monospacedDigit())
            .fixedSize(horizontal: true, vertical: false)
    }

    /// Amount, buyer fee, documentation fee and total, shown after tapping the total (spec FEES-1).
    private var breakdown: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            breakdownLine(Localizable.amount, estimate.amount)
            breakdownLine(Localizable.buyerFee, estimate.buyerFee)
            breakdownLine(Localizable.documentationFee, estimate.documentationFee)
            Divider()
            breakdownLine(Localizable.total, estimate.total)
                .fontWeight(.semibold)
        }
        .font(.subheadline)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("\(identifierPrefix).estimateBreakdown")
    }

    /// One "label … $amount" line that stacks when the text size leaves no room side by side.
    private func breakdownLine(_ title: String, _ value: Int) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: Spacing.small)
                breakdownValue(value)
            }
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(title)
                breakdownValue(value)
            }
        }
        .accessibilityElement(children: .combine)
    }

    /// Dollar value that never wraps mid-number at large text sizes (spec UX-2).
    private func breakdownValue(_ value: Int) -> some View {
        Text(Formatting.currency(value))
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
    }

}

private enum Constants {
    static let expandedChevronDegrees: Double = 180
}

private enum Localizable {
    static let totalTitle = "Est. total"
    static let caption = "Estimate · before taxes and transport"
    static let amount = "Amount"
    static let buyerFee = "Buyer fee"
    static let documentationFee = "Documentation fee"
    static let total = "Total"
    static let showBreakdownHint = "Shows the fee breakdown."
    static let hideBreakdownHint = "Hides the fee breakdown."

    static func totalAccessibility(_ total: String) -> String {
        "Estimated total \(total). Estimate before taxes and transport."
    }
}
