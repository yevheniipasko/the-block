//
//  VehicleImage.swift
//  The Block
//
//  Network-loaded vehicle photo with a progress placeholder and a
//  fallback icon when loading fails.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Network vehicle photo with a loading placeholder and a failure fallback (spec DETAIL-1).
struct VehicleImage: View {

    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder(systemImage: "car.side", label: "Photo unavailable")
            case .empty:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            @unknown default:
                placeholder(systemImage: "car.side", label: "Photo unavailable")
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipped()
    }

    private func placeholder(systemImage: String, label: String) -> some View {
        Image(systemName: systemImage)
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(label)
    }

}
