import MarkdownUI
import SwiftUI

struct ReferenceDetailInlineView: View {
    @Environment(SkillStore.self) private var store

    var body: some View {
        switch store.referenceState {
        case .idle:
            EmptyView()
        case .loading:
            ProgressView("Loading reference…")
                .frame(maxWidth: .infinity, alignment: .leading)
        case .missing:
            ContentUnavailableView("Missing reference",
                                   systemImage: "doc",
                                   description: Text("This reference file could not be found."))
        case .failed(let message):
            ContentUnavailableView("Unable to load reference",
                                   systemImage: "exclamationmark.triangle",
                                   description: Text(message))
        case .loaded:
            Markdown(store.selectedReferenceMarkdown)
                .textSelection(.enabled)
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.06))
                )
        }
    }
}
