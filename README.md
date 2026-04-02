# apple-todo-overlay

A macOS floating HUD for managing tasks. Lives in the menu bar, floats above all windows, and stays visible across every Space and fullscreen app.

## Features

- Floating overlay panel — always on top, visible on all Spaces
- Smart list views: Today, Tomorrow, This Week, Next Week, Overdue, No Due Date, Recently Completed
- Quick-add tasks with natural language input (`tomorrow`, `next friday`, `!` for high priority, `#tag`)
- Tags and priority levels (High, Medium, Low) per task
- Local-first SQLite database — works fully offline
- Sync with Apple Reminders on launch (CloudKit and Microsoft To Do coming)

> **Status:** Active development. Core task UI, local database, quick-add, and Apple Reminders sync are working. Tags UI, inline editing, and remaining sync providers are in progress.

## Requirements

- macOS 26.3+
- Xcode 26.4+

## Running

```bash
cd apple-todo-overlay
make run     # build + launch
make kill    # stop the app
make clean   # delete build artefacts
```

The app runs as a menu bar agent (no Dock icon). On first launch it appears in the top-right corner of your screen. Toggle it with the menu bar icon or ⌥Space (requires Accessibility permission).

## Quick-add

Press the `+` button in the HUD header (or tap into the input field at the bottom). Type naturally:

| Input | Result |
|---|---|
| `Call dentist tomorrow` | due tomorrow |
| `Submit report friday !` | due next Friday, high priority |
| `Buy milk tod !!` | due today, medium priority |
| `Review PR #work next monday` | due next Monday, tagged "work" |
| `in 3 days` | due in 3 days |

Press **Return** to save (field stays open for rapid entry). Press **Escape** to dismiss.

## Permissions

On first launch the app will request access to **Reminders** to sync your existing tasks. This can be revoked at any time in System Settings → Privacy & Security → Reminders.

⌥Space global hotkey requires **Accessibility** permission (System Settings → Privacy & Security → Accessibility). The menu bar icon works without it.

## Project structure

```
apple-todo-overlay/
├── Core/               Domain models (TodoTask, TaskList, Tag, Priority, SmartList, …)
├── Data/               SQLite database, repositories, mapper
├── Sync/               Sync engine, conflict resolution, state store
├── Providers/          Apple Reminders, CloudKit, Microsoft To Do integrations
├── UI/                 HUD panel, view models, SwiftUI views
└── System/             Network monitor, background scheduler
```

## Architecture

See [`task_overlay_architecture.md`](task_overlay_architecture.md) for the base architecture (domain model, ERD, sync sequence diagram, SQLite schema).

See [`task_overlay_architecture_extensions.md`](task_overlay_architecture_extensions.md) for the extended design covering smart lists, tags, priority, and task creation/editing.
