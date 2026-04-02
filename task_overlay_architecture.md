# Task Overlay App Architecture

This document captures the **base architectural concept** for a macOS task overlay / HUD application with:

- a **local-first task database**
- **offline-first behaviour**
- optional synchronisation with:
  - Apple Reminders
  - Microsoft To Do
  - CloudKit
- a floating **HUD / overlay** for viewing and completing tasks such as:
  - Today
  - This Week
  - Overdue

---

## 1. High-Level Architectural Overview

```mermaid
classDiagram

%% =========================
%% CORE DOMAIN MODEL
%% =========================

class Task {
    +String id
    +String title
    +String? notes
    +Date? dueDate
    +Bool completed
    +Date? completedAt
    +TaskSource source
    +String? externalId
    +Date createdAt
    +Date lastModified
    +SyncStatus syncStatus
    +String? listId
}

class TaskSource {
    <<enumeration>>
    LOCAL
    APPLE_REMINDERS
    MICROSOFT_TODO
    CLOUDKIT
}

class SyncStatus {
    <<enumeration>>
    SYNCED
    PENDING_UPLOAD
    PENDING_DOWNLOAD
    CONFLICT
    ERROR
}

class TaskList {
    +String id
    +String name
    +TaskSource source
    +String? externalId
    +Date createdAt
    +Date lastModified
}

%% =========================
%% DATA LAYER
%% =========================

class TaskRepository {
    +getAllTasks() [Task]
    +getTasksByFilter(filter) [Task]
    +getTasksForToday() [Task]
    +getTasksForWeek() [Task]
    +saveTask(task)
    +updateTask(task)
    +deleteTask(id)
    +markCompleted(id, completed)
}

class LocalDatabase {
    +fetch(query)
    +insertTask(task)
    +updateTask(task)
    +deleteTask(id)
    +insertList(list)
    +updateList(list)
}

TaskRepository --> LocalDatabase
TaskRepository --> Task
TaskRepository --> TaskList

%% =========================
%% SYNC ENGINE
%% =========================

class SyncEngine {
    +syncAll()
    +syncProvider(provider)
    +pullChanges()
    +pushChanges()
    +resolveConflicts()
}

class SyncManager {
    +startBackgroundSync()
    +triggerSync()
    +syncOnLaunch()
    +syncOnNetworkAvailable()
}

class ConflictResolver {
    +resolve(localTask, remoteTask) Task
}

SyncManager --> SyncEngine
SyncEngine --> TaskRepository
SyncEngine --> ConflictResolver

%% =========================
%% PROVIDER ABSTRACTION
%% =========================

class TaskProvider {
    <<interface>>
    +fetchChanges(since: Date) [Task]
    +pushChanges(tasks: [Task])
    +fetchLists() [TaskList]
    +isAvailable() Bool
}

class AppleRemindersProvider {
    +fetchChanges()
    +pushChanges()
    +fetchLists()
}

class MicrosoftTodoProvider {
    +fetchChanges()
    +pushChanges()
    +fetchLists()
}

class CloudKitProvider {
    +fetchChanges()
    +pushChanges()
    +fetchLists()
}

TaskProvider <|.. AppleRemindersProvider
TaskProvider <|.. MicrosoftTodoProvider
TaskProvider <|.. CloudKitProvider

SyncEngine --> TaskProvider

%% =========================
%% UI LAYER (HUD OVERLAY)
%% =========================

class HUDController {
    +show()
    +hide()
    +toggle()
    +refresh()
}

class TaskViewModel {
    +getTodayTasks() [Task]
    +getWeeklyTasks() [Task]
    +getOverdueTasks() [Task]
    +toggleComplete(taskId)
    +reload()
}

class FilterService {
    +filterToday(tasks) [Task]
    +filterWeek(tasks) [Task]
    +filterOverdue(tasks) [Task]
    +filterIncomplete(tasks) [Task]
}

HUDController --> TaskViewModel
TaskViewModel --> TaskRepository
TaskViewModel --> FilterService

%% =========================
%% SYSTEM SERVICES
%% =========================

class BackgroundScheduler {
    +scheduleSync()
}

class NetworkMonitor {
    +isOnline() Bool
}

SyncManager --> BackgroundScheduler
SyncManager --> NetworkMonitor

%% =========================
%% RELATIONSHIPS
%% =========================

Task --> TaskSource
Task --> SyncStatus
TaskList --> TaskSource
Task "*" --> "1" TaskList : belongs to
```

---

## 2. Entity Relationship Diagram (ERD)

This ERD represents a pragmatic **local SQLite schema** for the first version of the application.

```mermaid
erDiagram

    TASK_LISTS {
        TEXT id PK
        TEXT name
        TEXT source
        TEXT external_id
        INTEGER created_at
        INTEGER last_modified
        INTEGER is_deleted
    }

    TASKS {
        TEXT id PK
        TEXT list_id FK
        TEXT title
        TEXT notes
        INTEGER due_date
        INTEGER completed
        INTEGER completed_at
        TEXT source
        TEXT external_id
        INTEGER created_at
        INTEGER last_modified
        TEXT sync_status
        INTEGER is_deleted
    }

    SYNC_STATE {
        TEXT provider PK
        INTEGER last_sync_at
        TEXT last_cursor
        TEXT last_status
        TEXT last_error
    }

    DEVICES {
        TEXT id PK
        TEXT name
        TEXT platform
        INTEGER created_at
        INTEGER last_seen_at
    }

    SYNC_LOG {
        TEXT id PK
        TEXT provider
        TEXT entity_type
        TEXT entity_id
        TEXT action
        TEXT status
        TEXT message
        INTEGER created_at
    }

    TASK_LISTS ||--o{ TASKS : contains
```

---

## 3. Sync Sequence Diagram

This diagram shows a typical sync cycle for a user ticking off a task while offline, followed by background synchronisation when connectivity returns.

```mermaid
sequenceDiagram
    autonumber

    participant User
    participant HUD as HUDController
    participant VM as TaskViewModel
    participant Repo as TaskRepository
    participant DB as LocalDatabase
    participant SM as SyncManager
    participant SE as SyncEngine
    participant Provider as TaskProvider

    User->>HUD: Tick task as complete
    HUD->>VM: toggleComplete(taskId)
    VM->>Repo: markCompleted(taskId, true)
    Repo->>DB: update task\ncompleted = true\nsync_status = PENDING_UPLOAD
    DB-->>Repo: success
    Repo-->>VM: updated task
    VM-->>HUD: refresh visible tasks
    HUD-->>User: UI updates immediately

    Note over SM: Later, on schedule or app wake
    SM->>SE: triggerSync()
    SE->>Repo: get pending local changes
    Repo->>DB: fetch tasks with PENDING_UPLOAD
    DB-->>Repo: pending tasks
    Repo-->>SE: pending tasks

    SE->>Provider: pushChanges(tasks)
    Provider-->>SE: push result

    SE->>Provider: fetchChanges(since last sync)
    Provider-->>SE: remote changes

    SE->>Repo: apply merged updates
    Repo->>DB: update local records\nsync_status = SYNCED
    DB-->>Repo: success

    SE-->>SM: sync complete
    SM->>HUD: request refresh
    HUD->>VM: reload()
    VM->>Repo: getTasksByFilter()
    Repo->>DB: fetch filtered tasks
    DB-->>Repo: tasks
    Repo-->>VM: tasks
    VM-->>HUD: updated view
```

---

## 4. Suggested Database Tables

### `task_lists`
Stores logical lists such as:
- Personal
- Work
- Imported Reminders list
- Imported Microsoft To Do list

### `tasks`
Stores all tasks in a provider-neutral format.

### `sync_state`
Stores per-provider sync metadata, such as:
- last sync timestamp
- pagination or delta cursor
- error state

### `devices`
Optional future table for tracking device identity if you later support your own sync service.

### `sync_log`
Useful for:
- debugging
- diagnostics
- conflict analysis
- support logs

---

## 5. Suggested Initial SQLite Schema

```sql
CREATE TABLE task_lists (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    source TEXT NOT NULL,
    external_id TEXT,
    created_at INTEGER NOT NULL,
    last_modified INTEGER NOT NULL,
    is_deleted INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE tasks (
    id TEXT PRIMARY KEY,
    list_id TEXT,
    title TEXT NOT NULL,
    notes TEXT,
    due_date INTEGER,
    completed INTEGER NOT NULL DEFAULT 0,
    completed_at INTEGER,
    source TEXT NOT NULL,
    external_id TEXT,
    created_at INTEGER NOT NULL,
    last_modified INTEGER NOT NULL,
    sync_status TEXT NOT NULL DEFAULT 'SYNCED',
    is_deleted INTEGER NOT NULL DEFAULT 0,
    FOREIGN KEY (list_id) REFERENCES task_lists(id)
);

CREATE TABLE sync_state (
    provider TEXT PRIMARY KEY,
    last_sync_at INTEGER,
    last_cursor TEXT,
    last_status TEXT,
    last_error TEXT
);

CREATE TABLE devices (
    id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    platform TEXT NOT NULL,
    created_at INTEGER NOT NULL,
    last_seen_at INTEGER NOT NULL
);

CREATE TABLE sync_log (
    id TEXT PRIMARY KEY,
    provider TEXT NOT NULL,
    entity_type TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    action TEXT NOT NULL,
    status TEXT NOT NULL,
    message TEXT,
    created_at INTEGER NOT NULL
);

CREATE INDEX idx_tasks_due_date ON tasks(due_date);
CREATE INDEX idx_tasks_completed ON tasks(completed);
CREATE INDEX idx_tasks_sync_status ON tasks(sync_status);
CREATE INDEX idx_tasks_list_id ON tasks(list_id);
CREATE INDEX idx_tasks_last_modified ON tasks(last_modified);
```

---

## 6. Suggested Folder / Module Structure

```text
/Core
  Task.swift
  TaskList.swift
  TaskSource.swift
  SyncStatus.swift

/Data
  LocalDatabase.swift
  TaskRepository.swift
  TaskMapper.swift

/Sync
  SyncManager.swift
  SyncEngine.swift
  ConflictResolver.swift
  SyncStateStore.swift

/Providers
  TaskProvider.swift
  AppleRemindersProvider.swift
  MicrosoftTodoProvider.swift
  CloudKitProvider.swift

/UI
  HUDController.swift
  TaskViewModel.swift
  FilterService.swift
  OverlayPanel.swift

/System
  BackgroundScheduler.swift
  NetworkMonitor.swift
```

---

## 7. Architectural Notes

### Local-first
The local database should remain the **immediate source of truth for the UI**.  
All user actions should write locally first, then sync asynchronously.

### Eventual consistency
Remote providers should be treated as integration endpoints, not as the UI’s primary backing store.

### Provider-neutral task model
The app should map Apple Reminders, Microsoft To Do, and CloudKit records into one internal task format.

### Conflict strategy
For the MVP, a simple **last-write-wins** model based on `last_modified` is sufficient.

### Offline support
A task should be completable even when no network or provider access is available.  
The sync engine can upload the change later.

---

## 8. MVP Recommendation

A sensible MVP would be:

1. Local SQLite database
2. HUD / overlay UI
3. Filters for:
   - Today
   - This Week
   - Overdue
4. Mark complete / incomplete
5. Background sync engine skeleton
6. Apple Reminders integration first
7. CloudKit second
8. Microsoft To Do after core sync is stable

---

## 9. Future Extensions

Potential future additions:

- subtasks
- tags
- recurring tasks
- natural language date parsing
- own backend sync
- macOS menu bar mode
- iPhone / iPad companion app
- user analytics / sync diagnostics panel
