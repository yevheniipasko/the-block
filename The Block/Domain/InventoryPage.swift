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

/// Opaque position in a query's results: "continue after this vehicle" (keyset pagination).
///
/// Callers only pass back what a page returned; they never build one.
struct PageCursor: Hashable, Sendable {
    /// Last vehicle of the previous page.
    let afterID: VehicleModel.ID
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

    /// Returns up to `limit` vehicles following `cursor` (or from the start when `nil`).
    ///
    /// - Throws: `PagingError.staleCursor` if the cursor's vehicle is no longer in `results`.
    static func page(of results: [VehicleModel], after cursor: PageCursor?, limit: Int) throws -> InventoryPage {
        var start = 0
        if let cursor {
            guard let index = results.firstIndex(where: { $0.id == cursor.afterID }) else {
                throw PagingError.staleCursor
            }
            start = index + 1
        }
        let slice = Array(results[min(start, results.count)..<min(start + limit, results.count)])
        let hasMore = start + slice.count < results.count
        let next = hasMore ? slice.last.map { PageCursor(afterID: $0.id) } : nil
        return InventoryPage(vehicles: slice, nextCursor: next, totalCount: results.count)
    }

}
