//
//  Spacing.swift
//  The Block
//
//  Layout design tokens: the spacing scale and corner radii.
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import CoreGraphics

/// Spacing scale used across screens so layouts stay consistent.
enum Spacing {
    static let xxSmall: CGFloat = 2
    static let xSmall: CGFloat = 4
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
    static let large: CGFloat = 16
    static let xLarge: CGFloat = 24
}

/// Corner radii for cards and images.
enum CornerRadius {
    static let small: CGFloat = 8
    static let medium: CGFloat = 12
}
