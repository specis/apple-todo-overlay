# apple-todo-overlay

A macOS floating HUD for managing tasks. Lives in the menu bar, floats above all windows, and stays visible across every Space and fullscreen app.

## Features

- Floating overlay panel — always on top, visible on all Spaces
- Smart list views: Today, Tomorrow, This Week, Next Week, Overdue, No Due Date, Recently Completed
- Quick-add tasks with natural language input (`tomorrow`, `next friday`, `!` high priority, `#tag`)
- Tags with auto-assigned colours — filter the task list by tag
- Priority levels (High, Medium, Low) with colour-coded indicators
- Inline task editing — click any row to edit title, due date, priority, and tags
- Local-first SQLite database — works fully offline
- Sync with Apple Reminders on launch (CloudKit and Microsoft To Do coming)

> **Status:** Active development. Core task UI, local database, quick-add, tags, inline editing, and Apple Reminders sync are all working.

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

Press the `+` button in the HUD header. Type naturally and press **Return** to save. The field stays open for rapid entry. Press **Escape** to dismiss.

| Input | Result |
|---|---|
| `Call dentist tomorrow` | due tomorrow |
| `Submit report friday !` | due next Friday, high priority |
| `Buy milk tod !!` | due today, medium priority |
| `Review PR #work next monday` | due next Monday, tagged "work" |
| `In 3 days` | due in 3 days |

Tags are created automatically on first use and assigned a colour from a built-in palette.

## Editing tasks

Click any task row (excluding the checkbox) to expand the inline editor:

- Edit the title, due date, priority, and tags
- Toggle tags on/off from all tags in the system
- **Save** or press Return to confirm · **Cancel** or Escape to discard · **Delete** to remove

## Filtering

- Use the **smart list pills** at the top to filter by time (Today, This Week, Overdue, etc.)
- If any tasks have tags, a **tag filter strip** appears below — tap a tag chip to narrow the list further
- Switching smart list clears the active tag filter

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
