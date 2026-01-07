import SwiftUI

struct SkillListView: View {
    @Binding var source: SkillSource
    let localSkills: [Skill]
    @Binding var localSelection: Skill.ID?
    let remoteSkills: [RemoteSkill]
    @Binding var remoteSelection: RemoteSkill.ID?
    @Environment(SkillStore.self) private var store

    var body: some View {
        List(selection: source == .local ? $localSelection : $remoteSelection) {
            Section {
                if source == .local {
                    ForEach(localSkills) { skill in
                        SkillRowView(skill: skill)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    Task { await store.deleteSkills(ids: [skill.id]) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                    }
                    .onDelete { offsets in
                        let ids = offsets
                            .filter { localSkills.indices.contains($0) }
                            .map { localSkills[$0].id }
                        Task { await store.deleteSkills(ids: ids) }
                    }
                } else {
                    if remoteSkills.isEmpty {
                        Text("Search Clawdhub to see skills.")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        ForEach(remoteSkills) { skill in
                            RemoteSkillRowView(skill: skill)
                        }
                    }
                }
            } header: {
                SidebarHeaderView(
                    source: $source,
                    skillCount: source == .local ? localSkills.count : remoteSkills.count
                )
            }
        }
        .listStyle(.sidebar)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task { await store.loadSkills() }
                } label: {
                    Label("Reload", systemImage: "arrow.clockwise")
                }
                .labelStyle(.iconOnly)
                .disabled(source != .local)
            }
        }
    }
}

private struct SidebarHeaderView: View {
    @Binding var source: SkillSource
    let skillCount: Int

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
                Text(source == .local ? "Codex Skills" : "Clawdhub")
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

private struct RemoteSkillRowView: View {
    let skill: RemoteSkill

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(skill.displayName)
                .font(.headline)
                .foregroundStyle(.primary)

            if let summary = skill.summary, !summary.isEmpty {
                Text(summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let version = skill.version {
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
private struct SkillRowView: View {
    let skill: Skill

    private var visibleTags: [String] {
        Array(skill.tagLabels.prefix(3))
    }

    private var overflowCount: Int {
        max(skill.tagLabels.count - visibleTags.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(skill.displayName)
                .font(.headline)
                .foregroundStyle(.primary)

            Text(skill.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if !skill.tagLabels.isEmpty {
                HStack(spacing: 6) {
                    ForEach(visibleTags, id: \.self) { tag in
                        TagView(text: tag)
                    }
                    if overflowCount > 0 {
                        TagView(text: "+\(overflowCount) more")
                    }
                }
            }
        }
        .padding(.vertical, 6)
    }
}

private struct TagView: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(tagColor.opacity(0.18))
            )
    }

    private var tagColor: Color {
        let colors: [Color] = [
            .mint, .teal, .cyan, .blue, .indigo, .green, .orange
        ]
        let index = abs(text.hashValue) % colors.count
        return colors[index]
    }
}
