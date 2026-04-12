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
- Bidirectional sync with Apple Reminders and Microsoft To Do (background sync every 15 minutes, incremental)
- Delete propagation — tasks deleted locally are removed from Microsoft To Do on next sync
- Search tasks by title or notes
- Menu bar badge showing overdue + due-today count — icon appears automatically when tasks need attention
- ← → arrow keys to navigate filter pills
- Configurable HUD opacity via menu bar slider
- Menu bar icon hidden when idle, visible when HUD is open or tasks are urgent

> **Status:** Active development. Core task UI, local database, quick-add, tags, inline editing, Apple Reminders sync, and Microsoft To Do sync are all working.

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

The app runs as a menu bar agent (no Dock icon). On first launch it appears in the top-right corner of your screen. Toggle it with the menu bar icon or **⌃⌥Space** (requires Accessibility permission).

```bash
make release    # production build
make package    # builds + zips apple-todo-overlay.zip
```

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

## Filtering and search

- Use the **smart list pills** at the top to filter by time (Today, This Week, Overdue, etc.)
- Press **← →** arrow keys to cycle through filter pills
- If any tasks have tags, a **tag filter strip** appears below — click a tag chip to narrow the list further
- Switching smart list clears the active tag filter
- Press the **magnifying glass** icon (or click it) to open search — searches title and notes across all tasks
- Press **Escape** to close search

## Sync

### Apple Reminders
Sync starts automatically on launch if Reminders access has been granted. The app fetches incomplete reminders and any completed since the last sync.

### Microsoft To Do
Click **Connect Microsoft To Do…** in the menu bar popover. A browser window opens for OAuth sign-in. After sign-in, a full initial sync runs and subsequent syncs are incremental (only tasks modified since the last run). Sync runs every 15 minutes in the background and whenever network connectivity is restored.

Once connected, the menu bar popover shows **Microsoft To Do: Connected** with a Sync Now and Disconnect option. To disconnect, click **Disconnect Microsoft To Do…** — this clears the stored credentials and stops syncing immediately.

## Permissions

On first launch the app will request access to **Reminders** to sync your existing tasks. This can be revoked at any time in System Settings → Privacy & Security → Reminders.

**⌃⌥Space** global hotkey requires **Accessibility** permission (System Settings → Privacy & Security → Accessibility). The app will prompt on first launch and poll until granted. The menu bar icon works without it.

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

## Roadmap

### High priority
- [x] Search — find tasks by title or notes
- [x] Delete propagation — locally deleted tasks removed from MS Todo on next sync
- [x] Overdue / today badge on menu bar icon
- [ ] Due date notifications — alert when a task becomes overdue

### Medium priority
- [ ] Close button on the HUD
- [x] Task grouping by list in the All view
- [x] Window position persistence across relaunches
- [ ] Recurring task awareness (don't mark MS Todo series complete)

### Blocked
- [ ] CloudKit sync — requires paid Apple Developer account

## Performance

The app is tuned to stay fast as the task list grows:

- **SQLite page cache** — 8 MB in-memory cache (`PRAGMA cache_size`) so repeated reads don't hit disk.
- **WAL + NORMAL sync** — Write-Ahead Logging with `synchronous = NORMAL` avoids full fsyncs on every write while remaining crash-safe.
- **Composite index** — `(is_deleted, completed, due_date)` covers the exact filter pattern used by all smart list views.
- **Batch tag loading** — `getAllTasks` fetches tags for all tasks in one JOIN query instead of one query per task.
- **Transaction batching** — Sync write loops (remote merge, push status updates, deletions) run inside a single explicit transaction, avoiding per-row commit overhead.
- **Cached derived state** — `filteredTasks`, `urgentCount`, `availableTags`, and `groupedFilteredTasks` are stored properties updated only when their inputs change, not recomputed on every SwiftUI render pass.

## Architecture

See [`task_overlay_architecture.md`](task_overlay_architecture.md) for the base architecture, MVP status, and full roadmap.

See [`task_overlay_architecture_extensions.md`](task_overlay_architecture_extensions.md) for the extended design covering smart lists, tags, priority, and task creation/editing.
