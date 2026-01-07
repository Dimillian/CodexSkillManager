import SwiftUI

@main
struct CodexSkillManagerApp: App {
    @State private var store = SkillStore()
    @State private var remoteStore = RemoteSkillStore(client: .live())

    var body: some Scene {
        WindowGroup("Codex Skill Manager") {
            SkillSplitView()
                .environment(store)
                .environment(remoteStore)
        }
    }
}
