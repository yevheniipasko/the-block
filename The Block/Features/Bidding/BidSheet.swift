import SwiftUI

/// Place-bid sheet (spec BID-1 … BID-9, UX-5).
///
/// Entry → review → submit → brief success, then `onFinish` dismisses. While a bid is in
/// flight every control is disabled and the sheet can't be swiped away.
struct BidSheet: View {

    let viewModel: BidViewModel
    let onFinish: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .padding(Spacing.large)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle(Localizable.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localizable.cancel, action: onFinish)
                        .disabled(viewModel.isSubmitting)
                }
            }
        }
        .interactiveDismissDisabled(viewModel.isSubmitting)
        .sensoryFeedback(.success, trigger: viewModel.phase) { _, new in new == .succeeded }
        .sensoryFeedback(.error, trigger: viewModel.rejectionMessage) { _, new in new != nil }
        .task(id: viewModel.phase) {
            guard viewModel.phase == .succeeded else { return }
            try? await Task.sleep(for: Constants.successDisplayDuration)
            guard !Task.isCancelled else { return }
            onFinish()
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.phase == .succeeded {
            BidSuccessView(
                title: Localizable.successTitle,
                detail: viewModel.amount.map { Localizable.successDetail(Formatting.currency($0)) },
                identifier: "bid.successMessage"
            )
        } else if viewModel.isAuctionEnded {
            ContentUnavailableView(
                Localizable.endedTitle,
                systemImage: "flag.checkered",
                description: Text(Localizable.endedDetail)
            )
            .accessibilityIdentifier("bid.endedMessage")
        } else if viewModel.phase == .editing {
            BidEntryView(viewModel: viewModel)
        } else {
            BidReviewView(viewModel: viewModel)
        }
    }

}

/// Amount entry with minimum explanation, quick-add buttons and inline validation (spec BID-1 … BID-4).
private struct BidEntryView: View {

    let viewModel: BidViewModel
    @FocusState private var isAmountFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            if let vehicle = viewModel.vehicle {
                Text(vehicle.title)
                    .font(.headline)
            }

            Text(viewModel.minimumExplanation)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("bid.minimumLabel")

            amountField

            if let message = viewModel.validationMessage {
                Label(message, systemImage: "exclamationmark.circle")
                    .font(.footnote)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("bid.validationMessage")
            }

            quickAddButtons

            Button {
                isAmountFocused = false
                viewModel.review()
            } label: {
                Text(Localizable.review)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canReview)
            .accessibilityIdentifier("bid.reviewButton")
        }
    }

    private var amountField: some View {
        HStack(spacing: Spacing.xSmall) {
            Text(Localizable.currencySymbol)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField(Localizable.amountPlaceholder, text: amountBinding)
                .keyboardType(.numberPad)
                .focused($isAmountFocused)
                .accessibilityLabel(Localizable.amountLabel)
                .accessibilityIdentifier("bid.amountField")
        }
        .font(.title.monospacedDigit().weight(.semibold))
        .padding(Spacing.medium)
        .background(.fill.tertiary, in: RoundedRectangle(cornerRadius: CornerRadius.medium))
    }

    private var quickAddButtons: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Spacing.small) { quickAddButtonList }
            VStack(spacing: Spacing.small) { quickAddButtonList }
        }
    }

    @ViewBuilder
    private var quickAddButtonList: some View {
        ForEach(Constants.quickAddSteps, id: \.self) { steps in
            Button {
                viewModel.quickAdd(steps: steps)
            } label: {
                Text(quickAddTitle(steps: steps))
                    .monospacedDigit()
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(Localizable.quickAddAccessibility(quickAddAmount(steps: steps)))
            .accessibilityIdentifier("bid.quickAdd.\(steps)")
        }
    }

    private var amountBinding: Binding<String> {
        Binding(get: { viewModel.amountText }, set: { viewModel.updateAmountText($0) })
    }

    /// Dollar value a quick-add button adds: `steps` × the lot's adaptive step (spec BID-2).
    private func quickAddAmount(steps: Int) -> String {
        Formatting.currency(steps * (viewModel.bidStep ?? 0))
    }

    /// Button title, e.g. `+$1,000`.
    private func quickAddTitle(steps: Int) -> String {
        "+\(quickAddAmount(steps: steps))"
    }

}

/// Confirmation step: vehicle, amount, binding notice, then "Confirm bid" (spec BID-5, UX-5).
private struct BidReviewView: View {

    let viewModel: BidViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.large) {
            VStack(alignment: .leading, spacing: Spacing.xSmall) {
                Text(Localizable.yourBid)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(viewModel.amount.map { Formatting.currency($0) } ?? "")
                    .font(.largeTitle.monospacedDigit().bold())
                if let vehicle = viewModel.vehicle {
                    Text(vehicle.title)
                        .font(.headline)
                }
            }
            .accessibilityElement(children: .combine)

            Label(Localizable.bindingNotice, systemImage: "exclamationmark.shield")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button {
                Task { await viewModel.submitBid() }
            } label: {
                ZStack {
                    Text(Localizable.confirm)
                        .opacity(viewModel.isSubmitting ? 0 : 1)
                    if viewModel.isSubmitting {
                        ProgressView()
                            .accessibilityLabel(Localizable.placingBid)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isSubmitting)
            .accessibilityIdentifier("bid.confirmButton")

            Button(Localizable.edit, action: viewModel.editBid)
                .frame(maxWidth: .infinity)
                .disabled(viewModel.isSubmitting)
                .accessibilityIdentifier("bid.editButton")
        }
    }

}

/// Short success state shown before the sheet closes itself (spec BID-8, BID-10).
struct BidSuccessView: View {

    let title: String
    let detail: String?
    let identifier: String

    var body: some View {
        VStack(spacing: Spacing.medium) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: Constants.successIconSize))
                .foregroundStyle(.green)
                .accessibilityHidden(true)
            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
            if let detail {
                Text(detail)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Spacing.xLarge)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

}

private enum Constants {
    static let quickAddSteps = [1, 2, 5]
    static let successDisplayDuration: Duration = .seconds(1.2)
    static let successIconSize: CGFloat = 56
}

private enum Localizable {
    static let title = "Place bid"
    static let cancel = "Cancel"
    static let review = "Review bid"
    static let confirm = "Confirm bid"
    static let edit = "Edit bid"
    static let placingBid = "Placing bid"
    static let yourBid = "Your bid"
    static let bindingNotice = "Bids are binding. If you win, you're committed to buy this vehicle."
    static let currencySymbol = "$"
    static let amountPlaceholder = "Amount"
    static let amountLabel = "Bid amount in dollars"
    static let endedTitle = "This auction has ended"
    static let endedDetail = "Bidding is closed for this lot."
    static let successTitle = "You're the high bidder"

    static func successDetail(_ amount: String) -> String { "Your bid of \(amount) was placed." }
    static func quickAddAccessibility(_ amount: String) -> String { "Add \(amount)" }
}
