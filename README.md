# apple-todo-overlay

A macOS floating HUD for managing tasks. Lives in the menu bar, floats above all windows, and stays visible across every Space and fullscreen app.

## Features

- Floating overlay panel — always on top, visible on all Spaces
- Smart list views: Today, Tomorrow, This Week, Next Week, Overdue, No Due Date, Recently Completed
- Tags and priority levels per task
- Quick-add tasks with natural language date input
- Local-first SQLite database — works fully offline
- Background sync with Apple Reminders, CloudKit, and Microsoft To Do

> **Status:** Early development. The floating shell and project structure are in place; task UI and sync are in progress.

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
