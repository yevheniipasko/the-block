//
//  ConditionSectionView.swift
//  The Block
//
//  Detail screen condition card: grade scale, report, damage notes and
//  title status with branded titles flagged (spec DETAIL-4).
//
//  Created by Yevhenii Pasko on 2026-10-22.
//  Copyright © 2026 Yevhenii Pasko. All rights reserved.
//

import SwiftUI

/// Condition grade, report, damage notes, and title status (spec DETAIL-4).
struct ConditionSectionView: View {

    let grade: Double
    let gradeText: String
    let report: String
    let damageNotes: [String]
    let titleStatusText: String
    let isTitleFlagged: Bool

    var body: some View {
        DetailSectionCard(title: Localizable.title) {
            gradeRow
            Text(report)
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
            damageList
            titleStatusRow
        }
    }

    private var gradeRow: some View {
        VStack(alignment: .leading, spacing: Spacing.small) {
            HStack(alignment: .firstTextBaseline) {
                Text(Localizable.grade)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(gradeText)
                    .font(.title3.bold().monospacedDigit())
            }
            ProgressView(value: min(max(grade, 0), Constants.maxGrade), total: Constants.maxGrade)
                .tint(gradeTint)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Localizable.grade)
        .accessibilityValue(Localizable.gradeValue(gradeText))
    }

    private var gradeTint: Color {
        if grade >= Constants.goodGrade { return .green }
        if grade >= Constants.fairGrade { return .yellow }
        return .orange
    }

    @ViewBuilder
    private var damageList: some View {
        VStack(alignment: .leading, spacing: Spacing.xSmall) {
            Text(Localizable.damage)
                .font(.subheadline.weight(.semibold))
            if damageNotes.isEmpty {
                Label(Localizable.noDamage, systemImage: "checkmark.circle")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(damageNotes, id: \.self) { note in
                    Label(note, systemImage: "exclamationmark.circle")
                        .font(.subheadline)
                        .symbolRenderingMode(.multicolor)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("detail.damageNotes")
    }

    private var titleStatusRow: some View {
        HStack(spacing: Spacing.small) {
            Text(Localizable.titleStatus)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Label(
                titleStatusText,
                systemImage: isTitleFlagged ? "exclamationmark.triangle.fill" : "checkmark.seal"
            )
            .font(.subheadline.weight(isTitleFlagged ? .semibold : .regular))
            .foregroundStyle(isTitleFlagged ? Color.orange : Color.primary)
            .padding(.horizontal, isTitleFlagged ? Spacing.small : 0)
            .padding(.vertical, isTitleFlagged ? Spacing.xxSmall : 0)
            .background(isTitleFlagged ? Color.orange.opacity(Constants.flagOpacity) : .clear, in: Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Localizable.titleStatusAccessibility(titleStatusText, flagged: isTitleFlagged))
        .accessibilityIdentifier("detail.titleStatus")
    }

}

private enum Constants {
    static let maxGrade = 5.0
    static let goodGrade = 4.0
    static let fairGrade = 3.0
    static let flagOpacity = 0.15
}

private enum Localizable {
    static let title = "Condition"
    static let grade = "Condition grade"
    static func gradeValue(_ text: String) -> String { text.replacingOccurrences(of: "/", with: "out of") }
    static let damage = "Damage notes"
    static let noDamage = "No damage reported"
    static let titleStatus = "Title status"
    static func titleStatusAccessibility(_ status: String, flagged: Bool) -> String {
        flagged ? "Title status: \(status). Warning, branded title." : "Title status: \(status)"
    }
}
