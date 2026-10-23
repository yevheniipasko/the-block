import SwiftUI

/// Top banner telling the buyer they were outbid, with a shortcut back to the bid sheet
/// (spec ALERT-1, ALERT-2, ALERT-4).
struct OutbidBannerView: View {

    let alert: OutbidAlert
    let onBidAgain: () -> Void
    let onDismiss: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .top, spacing: Spacing.medium) {
            Image(systemName: "exclamationmark")
                .font(.headline.bold())
                .foregroundStyle(.orange)
                .frame(width: Constants.iconSize, height: Constants.iconSize)
                .background(.orange.opacity(Constants.iconBackgroundOpacity), in: Circle())
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Spacing.small) {
                HStack(alignment: .top, spacing: Spacing.small) {
                    VStack(alignment: .leading, spacing: Spacing.xxSmall) {
                        Text(Localizable.title)
                            .font(.headline)
                        Text(alert.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(Constants.vehicleTitleLineLimit)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(Localizable.dismiss, systemImage: "xmark", action: onDismiss)
                        .labelStyle(.iconOnly)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .padding(Spacing.small)
                        .background(.fill.tertiary, in: Circle())
                        .frame(minWidth: Constants.minimumTapSize, minHeight: Constants.minimumTapSize)
                        .contentShape(Rectangle())
                        .accessibilityIdentifier("alert.dismissButton")
                }

                actionLayout {
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
                        Text(Localizable.currentBid)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Text(Formatting.currency(alert.currentBid))
                            .font(.headline.monospacedDigit())
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Button(Localizable.bidAgain, systemImage: "arrow.up", action: onBidAgain)
                        .buttonStyle(.borderedProminent)
                        .controlSize(.regular)
                        .accessibilityIdentifier("alert.bidAgainButton")
                }
            }
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

    /// Price and action stay side by side normally, then stack at accessibility text sizes.
    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.small))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Spacing.medium))
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
    static let title = "You've been outbid"
    static let bidAgain = "Bid again"
    static let dismiss = "Dismiss"
    static let currentBid = "Current bid"
    static func message(title: String, amount: String) -> String {
        "You've been outbid on \(title). Current bid \(amount)."
    }
}

private enum Constants {
    static let borderOpacity = 0.3
    static let iconBackgroundOpacity = 0.14
    static let iconSize: CGFloat = 36
    static let minimumTapSize: CGFloat = 44
    static let shadowRadius: CGFloat = 10
    static let shadowOffset: CGFloat = 4
    static let vehicleTitleLineLimit = 2
    static let dragMinimumDistance: CGFloat = 10
    static let dismissDragDistance: CGFloat = 20
}
