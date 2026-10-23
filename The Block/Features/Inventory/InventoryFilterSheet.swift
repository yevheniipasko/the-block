//
//  InventoryFilterSheet.swift
//  The Block
//
//  Filter sheet for the inventory list: status, body style, fuel type,
//  province, and Buy Now toggles bound to InventoryViewModel.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Filter sheet: status, body style, fuel type, province, and Buy Now (spec LIST-3).
///
/// Changes apply immediately, so the list behind the sheet updates as you toggle.
struct InventoryFilterSheet: View {

    let viewModel: InventoryViewModel

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section(Localizable.status) {
                    ForEach(StatusFilter.allCases, id: \.self) { status in
                        toggle(.status(status), id: status.rawValue)
                    }
                }
                Section(Localizable.bodyStyle) {
                    ForEach(BodyStyle.allCases, id: \.self) { style in
                        toggle(.bodyStyle(style), id: style.rawValue)
                    }
                }
                Section(Localizable.fuelType) {
                    ForEach(FuelType.allCases, id: \.self) { fuel in
                        toggle(.fuelType(fuel), id: fuel.rawValue)
                    }
                }
                Section(Localizable.province) {
                    ForEach(viewModel.availableProvinces, id: \.self) { province in
                        toggle(.province(province), id: province)
                    }
                }
                Section {
                    toggle(.buyNowOnly, id: "buyNow")
                }
            }
            .navigationTitle(Localizable.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(Localizable.clearAll, action: viewModel.clearFilters)
                        .disabled(!viewModel.hasActiveFilters)
                        .accessibilityIdentifier("filter.clearAllButton")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(Localizable.done) { dismiss() }
                        .accessibilityIdentifier("filter.doneButton")
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Toggle row bound to one filter through the ViewModel.
    private func toggle(_ chip: InventoryViewModel.FilterChip, id: String) -> some View {
        Toggle(
            InventoryLabels.title(for: chip),
            isOn: Binding(
                get: { viewModel.isSelected(chip) },
                set: { viewModel.setFilter(chip, isOn: $0) }
            )
        )
        .accessibilityIdentifier("filter.toggle.\(id)")
    }

}

private enum Localizable {
    static let title = "Filters"
    static let status = "Auction status"
    static let bodyStyle = "Body style"
    static let fuelType = "Fuel type"
    static let province = "Province"
    static let clearAll = "Clear all"
    static let done = "Done"
}
