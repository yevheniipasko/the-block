import SwiftUI

/// Inventory toolbar entry that opens "My bids", badged with the number of lots you're outbid on
/// (spec MYBIDS-1, MYBIDS-6). The badge is hidden at 0.
struct MyBidsToolbarItem: ToolbarContent {

    let outbidCount: Int
    let action: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: action) {
                Image(systemName: "hammer")
                    .overlay(alignment: .topTrailing) { badge }
                    .accessibilityLabel(Localizable.title)
            }
            .accessibilityIdentifier("list.myBidsButton")
            .accessibilityValue(Localizable.outbidValue(outbidCount))
        }
    }

    @ViewBuilder private var badge: some View {
        if outbidCount > 0 {
            Text("\(outbidCount)")
                .font(.caption2.weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .padding(.horizontal, Spacing.xSmall)
                .frame(minWidth: Constants.badgeSize, minHeight: Constants.badgeSize)
                .background(.red, in: Capsule())
                .offset(x: Constants.badgeOffset, y: -Constants.badgeOffset)
                .accessibilityIdentifier("list.myBidsBadge")
        }
    }

}

private enum Constants {
    static let badgeSize: CGFloat = 16
    static let badgeOffset: CGFloat = 8
}

private enum Localizable {
    static let title = "My bids"
    static func outbidValue(_ count: Int) -> String {
        count == 0 ? "" : "Outbid on \(count)"
    }
}
