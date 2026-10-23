//
//  PhotoGalleryView.swift
//  The Block
//
//  Swipeable photo gallery with a page indicator for the detail screen (spec DETAIL-1).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Swipeable 4:3 photo gallery with a page indicator (spec DETAIL-1).
///
/// Each page is a `VehicleImage`, which handles its own loading placeholder and failure
/// fallback. A vehicle without photos shows a single fallback page.
struct PhotoGalleryView: View {

    let images: [URL]
    let title: String

    var body: some View {
        TabView {
            if images.isEmpty {
                VehicleImage(url: nil)
            } else {
                ForEach(Array(images.enumerated()), id: \.offset) { index, url in
                    VehicleImage(url: url)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(Localizable.photoLabel(title, index + 1, images.count))
                }
            }
        }
        .tabViewStyle(.page(indexDisplayMode: images.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
        .aspectRatio(Constants.aspectRatio, contentMode: .fit)
        .accessibilityIdentifier("detail.gallery")
    }

}

private enum Constants {
    static let aspectRatio: CGFloat = 4 / 3
}

private enum Localizable {
    static func photoLabel(_ title: String, _ index: Int, _ count: Int) -> String {
        "\(title), photo \(index) of \(count)"
    }
}
