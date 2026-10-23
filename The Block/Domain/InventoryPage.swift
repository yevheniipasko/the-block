//
//  InventoryPage.swift
//  The Block
//
//  Cursor-based paging types and the paginator that cuts query results into pages.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation

/// Where a vehicle sits in a query's order: sort key first, then lot and ID as tiebreaks.
///
/// Comparing two positions gives the same order as `InventoryQuery.apply(to:now:)`.
struct SortPosition: Hashable, Sendable, Comparable {
    /// The query's sort value when the position was taken (smaller sorts first).
    let key: Double
    let lot: String
    let id: VehicleModel.ID

    /// Orders by key, then lot, then ID, so no two vehicles ever tie.
    static func < (lhs: SortPosition, rhs: SortPosition) -> Bool {
        (lhs.key, lhs.lot, lhs.id.uuidString) < (rhs.key, rhs.lot, rhs.id.uuidString)
    }
}

/// Opaque position in a query's results: "continue after this boundary" (keyset pagination).
///
/// Holds the last row's position as it was when the page was served, not just its ID, so the
/// next page continues from the same place even if that lot's price or status changed since
/// (spec LIST-7). Callers only pass back what a page returned; they never build one.
struct PageCursor: Hashable, Sendable {
    /// Position of the last vehicle of the previous page, when that page was served.
    let after: SortPosition
}

/// One page of inventory results (spec LIST-7).
struct InventoryPage: Sendable {
    /// Vehicles on this page, in query order.
    let vehicles: [VehicleModel]
    /// Cursor for the next page, `nil` when this was the last one.
    let nextCursor: PageCursor?
    /// Total matches for the query, for the "142 vehicles" count (spec LIST-6).
    let totalCount: Int
}

/// Why a page request could not be served.
enum PagingError: Error, Equatable {
    /// The cursor's vehicle no longer matches the query (e.g. its auction ended); restart from page one.
    case staleCursor
}

/// Cuts one page out of already filtered and sorted results.
enum Paginator {

    /// Returns up to `limit` vehicles after `cursor`'s boundary (or from the start when `nil`).
    ///
    /// The page starts at the first result whose position is strictly after the boundary, so a
    /// row that moved since the last page (re-priced, ended) doesn't make the next page skip or
    /// repeat the rows around it (spec LIST-7). The moved row itself may come back once more on
    /// a later page; callers drop rows they already have.
    ///
    /// - Parameters:
    ///   - results: Filtered results, sorted by `position`.
    ///   - position: The query's position of a vehicle, e.g. `InventoryQuery.position(of:now:)`.
    /// - Throws: `PagingError.staleCursor` if the cursor's vehicle is no longer in `results`.
    static func page(
        of results: [VehicleModel],
        after cursor: PageCursor?,
        limit: Int,
        position: (VehicleModel) -> SortPosition
    ) throws -> InventoryPage {
        var start = 0
        if let cursor {
            guard results.contains(where: { $0.id == cursor.after.id }) else {
                throw PagingError.staleCursor
            }
            start = results.firstIndex { position($0) > cursor.after } ?? results.count
        }
        let slice = Array(results[start..<min(start + limit, results.count)])
        let hasMore = start + slice.count < results.count
        let next = hasMore ? slice.last.map { PageCursor(after: position($0)) } : nil
        return InventoryPage(vehicles: slice, nextCursor: next, totalCount: results.count)
    }

}
