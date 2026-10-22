import SwiftUI

/// Top banner telling the buyer they were outbid, with a shortcut back to the bid sheet
/// (spec ALERT-1, ALERT-2, ALERT-4).
struct OutbidBannerView: View {

    let alert: OutbidAlert
    let onBidAgain: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        layout {
            VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                Text(Localizable.outbidOn(alert.title))
                    .font(.subheadline.weight(.semibold))
                Text(Localizable.now(Formatting.currency(alert.currentBid)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(message)

            Button(Localizable.bidAgain, action: onBidAgain)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityIdentifier("alert.bidAgainButton")
        }
        .padding(Spacing.medium)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
        .overlay {
            RoundedRectangle(cornerRadius: CornerRadius.medium)
                .strokeBorder(.orange.opacity(Constants.borderOpacity))
        }
        .shadow(radius: Constants.shadowRadius, y: Constants.shadowOffset)
        .padding(.horizontal, Spacing.large)
        .gesture(swipeUpToDismiss)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("alert.banner")
        .accessibilityAction(named: Localizable.dismiss, onDismiss)
        .onAppear {
            AccessibilityNotification.Announcement(message).post()
        }
    }

    private var message: String {
        Localizable.message(title: alert.title, amount: Formatting.currency(alert.currentBid))
    }

    /// Side by side normally; stacked at accessibility text sizes so nothing truncates (spec UX-2).
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.small))
            : AnyLayout(HStackLayout(spacing: Spacing.medium))
    }

    private var swipeUpToDismiss: some Gesture {
        DragGesture(minimumDistance: Constants.dragMinimumDistance)
            .onEnded { value in
                if value.translation.height < -Constants.dismissDragDistance {
                    onDismiss()
                }
            }
    }

}

private enum Localizable {
    static let bidAgain = "Bid again"
    static let dismiss = "Dismiss"
    static func outbidOn(_ title: String) -> String { "Outbid on \(title)" }
    static func now(_ amount: String) -> String { "now \(amount)" }
    static func message(title: String, amount: String) -> String { "Outbid on \(title) · now \(amount)" }
}

private enum Constants {
    static let borderOpacity = 0.4
    static let shadowRadius: CGFloat = 8
    static let shadowOffset: CGFloat = 2
    static let dragMinimumDistance: CGFloat = 10
    static let dismissDragDistance: CGFloat = 20
}
