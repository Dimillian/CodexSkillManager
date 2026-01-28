# Codex Skill Manager

![image](image.png)

Codex Skill Manager is a macOS SwiftUI app built with SwiftPM (no Xcode project). It manages local skills for Codex and Claude Code, renders each `SKILL.md`, and lets you browse remote skills from Molthub.

## Features
- Browse local skills from `~/.codex/skills`, `~/.codex/skills/public`, and `~/.claude/skills`
- Render `SKILL.md` with Markdown, plus inline reference previews
- Import skills from a folder or zip
- Delete skills from the sidebar
- Browse Molthub skills with search + latest drops
- Download remote skills into Codex and/or Claude Code
- Show Molthub author info in the detail view
- Visual tags for installed status (Codex/Claude) and versions

## Requirements
- macOS 26+
- Swift 6.2+

## Build and run
```
swift build
swift run CodexSkillManager
```

## Package a local app
```
./Scripts/compile_and_run.sh
```

## Credits
- Markdown rendering via https://github.com/gonzalezreal/swift-markdown-ui
- Remote skill catalog via https://clawdhub.com
