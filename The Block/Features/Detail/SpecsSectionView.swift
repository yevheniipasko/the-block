import SwiftUI
import UIKit

/// Specs grid plus a copyable VIN (spec DETAIL-3).
struct SpecsSectionView: View {

    let rows: [SpecRow]
    let vin: String

    @State private var didCopyVIN = false
    @ScaledMetric(relativeTo: .body) private var columnMinWidth = Constants.columnMinWidth

    var body: some View {
        DetailSectionCard(title: Localizable.title) {
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: columnMinWidth), alignment: .topLeading)],
                alignment: .leading,
                spacing: Spacing.medium
            ) {
                ForEach(rows) { row in
                    specCell(label: row.label, value: row.value)
                }
            }
            Divider()
            vinRow
        }
    }

    /// One label-over-value cell in the specs grid.
    private func specCell(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.subheadline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var vinRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                vinText
                Spacer(minLength: Spacing.small)
                copyButton
            }
            VStack(alignment: .leading, spacing: Spacing.small) {
                vinText
                copyButton
            }
        }
    }

    private var vinText: some View {
        VStack(alignment: .leading, spacing: Spacing.xxSmall) {
            Text(Localizable.vin)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(vin)
                .font(.subheadline.monospaced())
                .textSelection(.enabled)
        }
        .accessibilityElement(children: .combine)
    }

    private var copyButton: some View {
        Button(action: copyVIN) {
            Label(
                didCopyVIN ? Localizable.copied : Localizable.copy,
                systemImage: didCopyVIN ? "checkmark" : "doc.on.doc"
            )
            .font(.subheadline)
        }
        .buttonStyle(.bordered)
        .accessibilityLabel(didCopyVIN ? Localizable.copiedAccessibility : Localizable.copyAccessibility)
        .accessibilityIdentifier("detail.copyVinButton")
        .sensoryFeedback(.success, trigger: didCopyVIN) { _, copied in copied }
    }

    /// Puts the VIN on the pasteboard and shows "Copied" briefly.
    private func copyVIN() {
        UIPasteboard.general.string = vin
        withAnimation { didCopyVIN = true }
        Task {
            try? await Task.sleep(for: Constants.copiedFeedbackDuration)
            withAnimation { didCopyVIN = false }
        }
    }

}

private enum Constants {
    static let columnMinWidth: CGFloat = 140
    static let copiedFeedbackDuration: Duration = .seconds(1.5)
}

private enum Localizable {
    static let title = "Specifications"
    static let vin = "VIN"
    static let copy = "Copy"
    static let copied = "Copied"
    static let copyAccessibility = "Copy VIN"
    static let copiedAccessibility = "VIN copied"
}
