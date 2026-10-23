import SwiftUI

/// Every lot you bid on or bought, grouped by your position (spec MYBIDS-1 … MYBIDS-5).
///
/// Selecting a row writes its ID into `selection`, which the router turns into the detail screen.
/// The ViewModel is observed by the router for the whole app session, so this view only reads it.
struct MyBidsView: View {

    let viewModel: MyBidsViewModel
    @Binding var selection: VehicleModel.ID?
    /// Leaves "My bids" and returns to the inventory list (empty-state action).
    let onBrowseInventory: () -> Void

    var body: some View {
        content
            .navigationTitle(Localizable.title)
    }

    @ViewBuilder private var content: some View {
        if viewModel.isEmpty {
            emptyState
        } else {
            List(selection: $selection) {
                ForEach(viewModel.groups) { group in
                    Section {
                        ForEach(group.vehicles) { vehicle in
                            MyBidsRow(vehicle: vehicle, position: group.position)
                                .tag(vehicle.id)
                                .accessibilityIdentifier("mybids.row.\(vehicle.lot)")
                        }
                    } header: {
                        Text(Localizable.groupHeader(group.position.groupTitle, count: group.vehicles.count))
                            .accessibilityIdentifier("mybids.group.\(group.position.identifier)")
                    }
                }
            }
            .listStyle(.insetGrouped)
            .animation(.default, value: viewModel.groups)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(Localizable.emptyTitle, systemImage: "hand.raised")
                .accessibilityIdentifier("mybids.emptyState")
        } description: {
            Text(Localizable.emptyDescription)
        } actions: {
            Button(Localizable.browse, action: onBrowseInventory)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("mybids.browseButton")
        }
    }

}

/// One lot: photo, title, lot, current bid, your bid or purchase price, status, position (spec MYBIDS-3).
private struct MyBidsRow: View {

    let vehicle: VehicleModel
    let position: BidPosition

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Spacing.medium))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Spacing.medium))

        layout {
            VehicleImage(url: vehicle.images.first)
                .frame(width: Constants.thumbnailWidth, height: Constants.thumbnailHeight)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.small))
            details
        }
        .padding(.vertical, Spacing.small)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(Localizable.lot(vehicle.lot))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: Spacing.small)
                AuctionStatusBadge(vehicle: vehicle)
            }
            Text(vehicle.title)
                .font(.headline)
                .lineLimit(Constants.titleLineLimit)
            amountLine(title: Localizable.currentBid, amount: vehicle.currentBid ?? vehicle.startingBid)
            if let yourAmount {
                amountLine(title: yourAmountTitle, amount: yourAmount)
            }
            Label(position.badgeTitle, systemImage: position.systemImage)
                .font(.caption.weight(.semibold))
                .foregroundStyle(position.tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Caption title followed by a bold CAD amount, e.g. `Your bid $20,000`.
    private func amountLine(title: String, amount: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xSmall) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(Formatting.currency(amount))
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
        }
    }

    /// Purchase price for Buy Now lots, otherwise your latest bid.
    private var yourAmount: Int? {
        vehicle.yourPurchasePrice ?? vehicle.yourBid
    }

    private var yourAmountTitle: String {
        vehicle.yourPurchasePrice == nil ? Localizable.yourBid : Localizable.paid
    }

    /// VoiceOver summary: title, lot, current bid, your amount, position (spec UX-3).
    private var accessibilityLabel: String {
        var parts = [
            vehicle.title,
            Localizable.lot(vehicle.lot),
            "\(Localizable.currentBid) \(Formatting.currency(vehicle.currentBid ?? vehicle.startingBid))"
        ]
        if let yourAmount {
            parts.append("\(yourAmountTitle) \(Formatting.currency(yourAmount))")
        }
        parts.append(position.badgeTitle)
        return parts.joined(separator: ". ")
    }

}

private enum Constants {
    static let thumbnailWidth: CGFloat = 96
    static let thumbnailHeight: CGFloat = 72
    static let titleLineLimit = 2
}

private enum Localizable {
    static let title = "My bids"
    static let emptyTitle = "You haven't bid on anything yet"
    static let emptyDescription = "Lots you bid on or buy appear here, grouped by whether you're winning."
    static let browse = "Browse inventory"
    static let currentBid = "Current bid"
    static let yourBid = "Your bid"
    static let paid = "You paid"
    static func lot(_ lot: String) -> String { "Lot \(lot)" }
    static func groupHeader(_ title: String, count: Int) -> String { "\(title) · \(count)" }
}
