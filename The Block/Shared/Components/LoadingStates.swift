import SwiftUI

/// Full-screen loading state for a first load (spec UX-5).
struct LoadingStateView: View {

    let message: String

    var body: some View {
        ProgressView {
            Text(message).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("state.loading")
    }

}

/// Full-screen error with a retry button, used instead of an empty list (spec DATA-3, UX-5).
struct ErrorStateView: View {

    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(Localizable.title, systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button(Localizable.retry, action: retry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("state.retryButton")
        }
    }

}

/// Last list row while the next page loads, or an inline retry if it failed (spec LIST-7, UX-5).
struct PageStatusRow: View {

    enum Status {
        case loading
        case failed(retry: () -> Void)
    }

    let status: Status

    var body: some View {
        HStack {
            Spacer()
            switch status {
            case .loading:
                ProgressView()
                    .accessibilityLabel(Localizable.loadingMore)
            case .failed(let retry):
                Button(Localizable.loadMoreFailed, systemImage: "arrow.clockwise", action: retry)
                    .accessibilityIdentifier("list.pageRetryButton")
            }
            Spacer()
        }
        .padding(.vertical, Spacing.medium)
        .listRowSeparator(.hidden)
        .accessibilityIdentifier("list.pageStatus")
    }

}

private enum Localizable {
    static let title = "Something went wrong"
    static let retry = "Try again"
    static let loadingMore = "Loading more vehicles"
    static let loadMoreFailed = "Couldn't load more — retry"
}
