//
//  VehicleImage.swift
//  The Block
//
//  Network-loaded vehicle photo with a progress placeholder and a
//  fallback icon when there is no photo or loading fails.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Network vehicle photo with a loading placeholder and a failure fallback (spec DETAIL-1).
struct VehicleImage: View {

    let url: URL?

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        unavailablePlaceholder
                    case .empty:
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    @unknown default:
                        unavailablePlaceholder
                    }
                }
            } else {
                // AsyncImage never leaves `.empty` without a URL, so skip the spinner.
                unavailablePlaceholder
            }
        }
        .background(Color(uiColor: .secondarySystemBackground))
        .clipped()
    }

    /// Centred car symbol labelled "Photo unavailable", filling the frame when there is no photo
    /// or it failed to load.
    private var unavailablePlaceholder: some View {
        Image(systemName: "car.side")
            .font(.largeTitle)
            .foregroundStyle(.tertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel("Photo unavailable")
    }

}
