//
//  LoadingStates.swift
//  The Block
//
//  Reusable full-screen loading and error states, and the paging status
//  row shown at the end of a list.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Full-screen loading state for a first load (spec UX-5).
struct LoadingStateView: View {

    /// Caption under the spinner, e.g. `Loading inventory…`.
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

    /// Explanation shown under the title.
    let message: String
    /// Called by the Try again button.
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

    /// What the row shows.
    enum Status {
        /// A spinner while the next page loads.
        case loading
        /// An inline retry button after the next page failed.
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

/// User-facing strings for the loading and error states.
private enum Localizable {
    static let title = "Something went wrong"
    static let retry = "Try again"
    static let loadingMore = "Loading more vehicles"
    static let loadMoreFailed = "Couldn't load more — retry"
}
