//
//  OutbidAlertCenter.swift
//  The Block
//
//  App-wide outbid alert queue: watches every lot and raises a banner when
//  the buyer goes from winning to outbid (spec ALERT-1 … ALERT-3).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import Foundation
import Observation

/// One "you've been outbid" notice shown in the banner (spec ALERT-1).
struct OutbidAlert: Identifiable, Equatable, Sendable {
    let id = UUID()
    let lotID: VehicleModel.ID
    let title: String
    let currentBid: Int
}

/// Watches every lot and raises a banner when the buyer goes from winning to outbid
/// (spec ALERT-1 … ALERT-3). App-wide, so it lives above any single screen.
@Observable
final class OutbidAlertCenter {

    /// The alert on screen, or `nil` when the banner is hidden.
    private(set) var current: OutbidAlert?
    /// Lot whose bid sheet is open; its outbids raise no banner because the sheet shows its own notice.
    var suppressedLotID: VehicleModel.ID?

    @ObservationIgnored private var queue: [OutbidAlert] = []
    @ObservationIgnored private var positions: [VehicleModel.ID: BidPosition] = [:]
    @ObservationIgnored private var dismissTask: Task<Void, Never>?
    @ObservationIgnored private let repository: VehicleRepositoryProtocol
    @ObservationIgnored private let displayDuration: Duration

    /// - Parameters:
    ///   - repository: Source of the lots and their live updates.
    ///   - displayDuration: How long each banner stays before it dismisses itself (spec ALERT-2).
    init(repository: VehicleRepositoryProtocol, displayDuration: Duration = Constants.displayDuration) {
        self.repository = repository
        self.displayDuration = displayDuration
    }

    /// Follows every lot change until the calling task is cancelled, raising an alert on each
    /// winning → outbid transition (spec ALERT-1).
    ///
    /// Waits for the first load, then seeds positions from the loaded lots and subscribes in the
    /// same main-actor step, so no update is missed between the two. Seeding from `vehicles`
    /// rather than the snapshot's burst of updates matters: that burst can overflow a stream's
    /// buffer. Lots already outbid when observing starts never alert.
    func observe() async {
        for await state in repository.loadStateUpdates() where state == .loaded {
            break
        }
        guard !Task.isCancelled else { return }
        let now = repository.now
        for vehicle in repository.vehicles {
            positions[vehicle.id] = vehicle.bidPosition(at: now)
        }
        for await vehicle in repository.inventoryUpdates() {
            handle(vehicle)
        }
    }

    /// Hides the current banner and shows the next queued alert, if any (spec ALERT-2).
    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
        showNextIfIdle()
    }

    // MARK: - Private

    /// Records the lot's new position and queues an alert when the buyer just lost the lead.
    private func handle(_ vehicle: VehicleModel) {
        let previous = positions[vehicle.id]
        let position = vehicle.bidPosition(at: repository.now)
        positions[vehicle.id] = position
        guard previous == .winning, position == .outbid, vehicle.id != suppressedLotID,
              let currentBid = vehicle.currentBid else { return }
        enqueue(OutbidAlert(lotID: vehicle.id, title: vehicle.title, currentBid: currentBid))
    }

    /// Adds an alert to the queue; a lot already waiting in the queue is updated in place instead
    /// of stacking a second banner for it.
    private func enqueue(_ alert: OutbidAlert) {
        if let index = queue.firstIndex(where: { $0.lotID == alert.lotID }) {
            queue[index] = alert
        } else {
            queue.append(alert)
        }
        showNextIfIdle()
    }

    /// Shows the oldest queued alert when no banner is on screen and schedules its auto-dismiss.
    private func showNextIfIdle() {
        guard current == nil, !queue.isEmpty else { return }
        current = queue.removeFirst()
        let duration = displayDuration
        dismissTask = Task { [weak self] in
            try? await Task.sleep(for: duration)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

}

private enum Constants {
    /// About four seconds: long enough to read and tap "Bid again" (spec ALERT-2).
    static let displayDuration: Duration = .seconds(4)
}
