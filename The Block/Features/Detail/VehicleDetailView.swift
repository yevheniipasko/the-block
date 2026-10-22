import SwiftUI

/// Vehicle detail: gallery, header, specs, condition, seller, and a pinned action bar (spec DETAIL-*).
///
/// The bottom action bar calls `onPlaceBid` / `onBuyNow`; the router presents the sheets.
struct VehicleDetailView: View {

    let viewModel: VehicleDetailViewModel
    let onPlaceBid: () -> Void
    let onBuyNow: () -> Void

    var body: some View {
        if let vehicle = viewModel.vehicle {
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.large) {
                    PhotoGalleryView(images: vehicle.images, title: vehicle.title)
                    VStack(alignment: .leading, spacing: Spacing.large) {
                        header(vehicle)
                        SpecsSectionView(rows: viewModel.specRows, vin: vehicle.vin)
                        ConditionSectionView(
                            grade: vehicle.conditionGrade,
                            gradeText: viewModel.conditionGradeText,
                            report: vehicle.conditionReport,
                            damageNotes: vehicle.damageNotes,
                            titleStatusText: viewModel.titleStatusText,
                            isTitleFlagged: viewModel.isTitleFlagged
                        )
                        seller(vehicle)
                    }
                    .padding(.horizontal, Spacing.large)
                }
                .padding(.bottom, Spacing.large)
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .safeAreaInset(edge: .bottom, spacing: 0) {
                AuctionActionBar(viewModel: viewModel, onPlaceBid: onPlaceBid, onBuyNow: onBuyNow)
            }
            .navigationTitle(vehicle.lot)
            .navigationBarTitleDisplayMode(.inline)
        } else {
            ContentUnavailableView(
                Localizable.notFoundTitle,
                systemImage: "car.side",
                description: Text(Localizable.notFoundMessage)
            )
        }
    }

    // MARK: - Header (DETAIL-2)

    private func header(_ vehicle: VehicleModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            Text(Localizable.lot(vehicle.lot))
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(vehicle.title)
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("detail.title")
            AuctionStatusBadge(vehicle: vehicle)
            buyerMarker
            priceBlock(vehicle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var buyerMarker: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            switch viewModel.buyerMarker(at: context.date) {
            case .highBidder:
                markerLabel(Localizable.highBidder, systemImage: "hand.thumbsup.fill", tint: .green)
            case .purchased:
                markerLabel(Localizable.purchased, systemImage: "checkmark.seal.fill", tint: .accentColor)
            case nil:
                EmptyView()
            }
        }
    }

    private func markerLabel(_ title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .accessibilityIdentifier("detail.buyerMarker")
    }

    private func priceBlock(_ vehicle: VehicleModel) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.small) {
                Text(viewModel.priceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.priceAmount)
                    .font(.title.bold().monospacedDigit())
            }
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("detail.currentBid")

            HStack(spacing: Spacing.small) {
                Text(viewModel.bidCountText)
                Text(Localizable.separator).accessibilityHidden(true)
                Text(vehicle.floorState.title)
                    .accessibilityIdentifier("detail.floorState")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)

            if let buyNowPrice = vehicle.buyNowPrice {
                Label(Localizable.buyNowPrice(Formatting.currency(buyNowPrice)), systemImage: "bolt.fill")
                    .font(.subheadline.weight(.medium))
            }
        }
    }

    // MARK: - Seller (DETAIL-5)

    private func seller(_ vehicle: VehicleModel) -> some View {
        DetailSectionCard(title: Localizable.sellerTitle) {
            Label(vehicle.sellingDealership, systemImage: "building.2")
            Label(viewModel.locationText, systemImage: "mappin.and.ellipse")
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }

}

private enum Localizable {
    static let notFoundTitle = "Vehicle not found"
    static let notFoundMessage = "This lot is no longer available."
    static func lot(_ lot: String) -> String { "Lot \(lot)" }
    static let highBidder = "You're the high bidder"
    static let purchased = "Purchased by you"
    static let separator = "·"
    static func buyNowPrice(_ price: String) -> String { "Buy Now \(price)" }
    static let sellerTitle = "Seller"
}
