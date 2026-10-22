import SwiftUI

/// Titled card that groups one section of the detail screen.
struct DetailSectionCard<Content: View>: View {

    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.medium) {
            Text(title)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Spacing.large)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: .rect(cornerRadius: CornerRadius.medium))
    }

}
