import SwiftUI

/// Compact, notification-style banner telling the buyer they were outbid, with a shortcut back
/// to the bid sheet (spec ALERT-1, ALERT-2, ALERT-4). Dismisses itself, or on swipe up.
struct OutbidBannerView: View {

    let alert: OutbidAlert
    let onBidAgain: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @GestureState private var dragOffset: CGFloat = 0
    @ScaledMetric(relativeTo: .subheadline) private var iconSize = Constants.iconSize

    var body: some View {
        contentLayout {
            HStack(spacing: Spacing.medium) {
                icon
                VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                    Text(Localizable.outbid)
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.orange)
                    Text(alert.title)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(Constants.titleLineLimit)
                    Text(Localizable.now(Formatting.currency(alert.currentBid)))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(Localizable.bidAgain, action: onBidAgain)
                .font(.subheadline.weight(.semibold))
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .accessibilityIdentifier("alert.bidAgainButton")
        }
        .padding(.vertical, Spacing.medium)
        .padding(.horizontal, Spacing.large)
        .glassEffect(.regular, in: .rect(cornerRadius: Constants.cornerRadius))
        .shadow(
            color: .black.opacity(Constants.shadowOpacity),
            radius: Constants.shadowRadius,
            y: Constants.shadowOffset
        )
        .padding(.horizontal, Spacing.medium)
        .offset(y: dragOffset)
        .gesture(swipeUpToDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alert.banner")
        .accessibilityAction(named: Localizable.dismiss, onDismiss)
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var icon: some View {
        Image(systemName: "arrow.down")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: iconSize, height: iconSize)
            .background(.orange.gradient, in: Circle())
            .accessibilityHidden(true)
    }

    private var message: String {
        Localizable.message(title: alert.title, amount: Formatting.currency(alert.currentBid))
    }

    /// Text and action sit side by side normally, then stack at accessibility text sizes.
    private var contentLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.medium))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.medium))
    }

    /// Follows the finger upward (resisting downward pulls) and dismisses past a short distance.
    private var swipeUpToDismiss: some Gesture {
        DragGesture(minimumDistance: Constants.dragMinimumDistance)
            .updating($dragOffset) { value, offset, _ in
                let height = value.translation.height
                offset = height < 0 ? height : height * Constants.downwardResistance
            }
            .onEnded { value in
                if value.translation.height < -Constants.dismissDragDistance {
                    onDismiss()
                }
            }
    }

}

private enum Localizable {
    static let outbid = "Outbid"
    static let bidAgain = "Bid again"
    static let dismiss = "Dismiss"
    static func now(_ amount: String) -> String { "Now \(amount)" }
    static func message(title: String, amount: String) -> String {
        "You've been outbid on \(title). Current bid \(amount)."
    }
}

private enum Constants {
    static let cornerRadius: CGFloat = 24
    static let iconSize: CGFloat = 32
    static let shadowOpacity = 0.15
    static let shadowRadius: CGFloat = 16
    static let shadowOffset: CGFloat = 6
    static let titleLineLimit = 1
    static let dragMinimumDistance: CGFloat = 10
    static let dismissDragDistance: CGFloat = 20
    static let downwardResistance: CGFloat = 0.2
}
