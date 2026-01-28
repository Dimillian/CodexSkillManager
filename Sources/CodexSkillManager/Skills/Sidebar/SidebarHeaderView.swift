import SwiftUI

struct SidebarHeaderView: View {
    let skillCount: Int
    @Binding var source: SkillSource

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Picker("Source", selection: $source) {
                    ForEach(SkillSource.allCases) { source in
                        Text(source.rawValue).tag(source)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.trailing, 8)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(source == .local ? "Installed Skills" : "Molthub")
                    .font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("\(skillCount) skills")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .textCase(nil)
    }
}
