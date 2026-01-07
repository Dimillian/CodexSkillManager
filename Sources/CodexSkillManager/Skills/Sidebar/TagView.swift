import SwiftUI

struct TagView: View {
    let text: String
    let tint: Color?

    init(text: String, tint: Color? = nil) {
        self.text = text
        self.tint = tint
    }

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(tint ?? .secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tagColor.opacity(tint == nil ? 0.18 : 0.28))
            )
    }

    private var tagColor: Color {
        if let tint {
            return tint
        }
        let colors: [Color] = [
            .mint, .teal, .cyan, .blue, .indigo, .green, .orange
        ]
        let index = abs(text.hashValue) % colors.count
        return colors[index]
    }
}
