# CodexSkillManager

## What this app is
CodexSkillManager is a small macOS SwiftUI app built with SwiftPM (no Xcode project) that lists the Codex skills installed in the user's public skills folder.

## How it works
- The app scans `~/.codex/skills/public` for subdirectories.
- Each directory name becomes a skill entry.
- The UI is a SwiftUI `NavigationSplitView` with a list on the left and a detail view on the right.
- The detail view shows the skill name and its full path.

## Build and run
- Build: `swift build`
- Run: `swift run CodexSkillManager`
When editing this app, build after each change and fix any compile errors before continuing.

## Packaging and release
Use the `macos-spm-app-packaging` skill for packaging, notarization, appcast, and GitHub release steps.
Local packaging helpers live in `Scripts/`:
- `Scripts/compile_and_run.sh`: package (adhoc sign) + launch the `.app`.
- `Scripts/package_app.sh`: build and create `CodexSkillManager.app`.
- `Scripts/sign-and-notarize.sh`: sign + notarize for releases.
- `Scripts/make_appcast.sh`: generate Sparkle appcast from a zip.
- `Scripts/generate_sparkle_keys.sh`: generate Sparkle keypair and export private key.

Sparkle env vars (set in `~/.zshrc`):
- `SPARKLE_PUBLIC_KEY`
- `SPARKLE_PRIVATE_KEY_FILE`
- `SPARKLE_FEED_URL`

## Release flow (commit → changelog → notarize → appcast → GitHub release)
1) Update version: bump `MARKETING_VERSION` and `BUILD_NUMBER` in `version.env`.
2) Build: `swift build`.
3) Commit + push:
   - `git add -A`
   - `git commit -m "feat: ..."` (or other Conventional Commit type)
   - `git push`
4) Write release notes (short, user-facing bullets) and save to a file, e.g. `/tmp/codexskillmanager-release-notes-<version>.md`.
5) Notarize and package:
   - `APP_STORE_CONNECT_API_KEY_P8="/path/to/key.p8" APP_STORE_CONNECT_KEY_ID="..." APP_STORE_CONNECT_ISSUER_ID="..." APP_IDENTITY="Developer ID Application: ..."`
   - `./Scripts/sign-and-notarize.sh`
   - Note: `SPARKLE_PUBLIC_KEY` must be set (and `SPARKLE_FEED_URL` if non-default) or the build will be missing Sparkle keys and updates will not work.
6) Generate Sparkle appcast entry:
   - `SPARKLE_PRIVATE_KEY_FILE="..." ./Scripts/make_appcast.sh CodexSkillManager-<version>.zip https://raw.githubusercontent.com/Dimillian/CodexSkillManager/main/appcast.xml`
   - Note: Sparkle uses the build number (`BUILD_NUMBER`) for `sparkle:version`, so it must increase each release.
   - `git add appcast.xml`
   - `git commit -m "chore: update sparkle appcast"`
   - `git push`
7) Publish GitHub release (creates the tag):
   - `gh release create v<version> CodexSkillManager-<version>.zip appcast.xml --title "Codex Skill Manager <version>" --notes-file /tmp/codexskillmanager-release-notes-<version>.md`

## Project layout
- `Package.swift`: SwiftPM manifest for the executable target.
- `Sources/CodexSkillManager/App/CodexSkillManagerApp.swift`: App entry point + dependency injection.
- `Sources/CodexSkillManager/Skills/SkillStore.swift`: Loads skills + selected SKILL.md content.
- `Sources/CodexSkillManager/Skills/SkillSplitView.swift`: Split view shell with list + detail.
- `Sources/CodexSkillManager/Skills/SkillDetailView.swift`: Markdown rendering for SKILL.md content.
- `version.env`: Template version file (used by the packaging scripts if added later).
