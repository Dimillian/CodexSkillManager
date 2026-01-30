import SwiftUI

struct PublishSkillSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SkillStore.self) private var store

    let skill: Skill
    let nextVersion: String
    let publishedVersion: String?
    @Binding var bump: PublishBump
    @Binding var changelog: String
    @Binding var tags: String

    @State private var isPublishing = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Publish Skill")
                    .font(.title.bold())
                Text("Push changes for \(skill.displayName) to Clawhub.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline) {
                    Picker("Version bump", selection: $bump) {
                        ForEach(PublishBump.allCases) { bump in
                            Text(bump.label).tag(bump)
                        }
                    }
                    Text("Will publish v\(nextVersion)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Changelog")
                        .font(.subheadline.weight(.semibold))
                    TextEditor(text: $changelog)
                        .frame(minHeight: 90)
                        .padding(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                        )
                }

            }

            Spacer()

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                Spacer()
                Button(isPublishing ? "Publishing…" : "Publish") {
                    Task { await publishSkill() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isPublishing || changelog.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(minWidth: 420, minHeight: 360)
        .alert("Publish failed", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "Unable to publish this skill.")
        }
    }

    private func publishSkill() async {
        isPublishing = true
        errorMessage = nil
        do {
            let tagList = tags
                .split(separator: ",")
                .map { String($0) }
            try await store.publishSkill(
                skill,
                bump: bump,
                changelog: changelog,
                tags: tagList,
                publishedVersion: publishedVersion
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
        isPublishing = false
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }
}
