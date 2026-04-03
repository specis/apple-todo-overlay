import CloudKit
import Foundation

final class CloudKitProvider: TaskProvider {

    private lazy var container: CKContainer = CKContainer.default()
    private var db: CKDatabase { container.privateCloudDatabase }
    private let zone = CKRecordZone(zoneName: "Tasks")

    // MARK: - TaskProvider

    /// CloudKit requires an Apple Developer Program account to register the iCloud container.
    /// Returns false until the entitlements are configured and the capability is enabled in Xcode.
    func isAvailable() -> Bool { false }

    func fetchLists() async throws -> [TaskList] {
        let now = Date()
        return [TaskList(
            id: zone.zoneID.zoneName,
            name: "iCloud Tasks",
            source: .cloudKit,
            externalId: zone.zoneID.zoneName,
            createdAt: now,
            lastModified: now
        )]
    }

    /// Fetches all changed records since the last server change token (incremental sync).
    /// Falls back to a full fetch when no token is stored.
    func fetchChanges(since _: Date) async throws -> [TodoTask] {
        try await ensureZoneExists()

        let changeToken = storedChangeToken()

        var tasks: [TodoTask] = []
        var latestToken: CKServerChangeToken? = nil

        let config = CKFetchRecordZoneChangesOperation.ZoneConfiguration(
            previousServerChangeToken: changeToken
        )
        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zone.zoneID],
            configurationsByRecordZoneID: [zone.zoneID: config]
        )

        op.recordWasChangedBlock = { [weak self] _, result in
            if case .success(let record) = result, let task = self?.map(record) {
                tasks.append(task)
            }
        }

        op.recordZoneFetchResultBlock = { _, result in
            if case .success(let (token, _, _)) = result {
                latestToken = token
            }
        }

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            self.db.add(op)
        }

        if let latestToken {
            persistChangeToken(latestToken)
        }

        return tasks
    }

    func pushChanges(_ tasks: [TodoTask]) async throws {
        guard !tasks.isEmpty else { return }
        try await ensureZoneExists()

        let records = tasks.map { toRecord($0) }
        let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        op.savePolicy = .allKeys

        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success: cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            self.db.add(op)
        }
    }

    // MARK: - Zone

    private func ensureZoneExists() async throws {
        _ = try await db.modifyRecordZones(saving: [zone], deleting: [])
    }

    // MARK: - Change token persistence

    private func storedChangeToken() -> CKServerChangeToken? {
        guard
            let encoded = try? SyncStateStore.lastCursor(for: .cloudKit),
            let data = Data(base64Encoded: encoded)
        else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: CKServerChangeToken.self, from: data)
    }

    private func persistChangeToken(_ token: CKServerChangeToken) {
        guard
            let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true)
        else { return }
        try? SyncStateStore.updateCursor(for: .cloudKit, cursor: data.base64EncodedString())
    }

    // MARK: - Mapping

    private func map(_ record: CKRecord) -> TodoTask? {
        guard let title = record["title"] as? String else { return nil }
        return TodoTask(
            id: UUID().uuidString,
            title: title,
            notes: record["notes"] as? String,
            dueDate: record["dueDate"] as? Date,
            completed: (record["completed"] as? NSNumber)?.boolValue ?? false,
            completedAt: record["completedAt"] as? Date,
            source: .cloudKit,
            externalId: record.recordID.recordName,
            createdAt: record.creationDate ?? Date(),
            lastModified: record.modificationDate ?? Date(),
            syncStatus: .synced,
            listId: zone.zoneID.zoneName,
            priority: Priority(rawValue: record["priority"] as? String ?? "") ?? .none,
            tags: []
        )
    }

    private func toRecord(_ task: TodoTask) -> CKRecord {
        let recordID = CKRecord.ID(
            recordName: task.externalId ?? task.id,
            zoneID: zone.zoneID
        )
        let record = CKRecord(recordType: "Task", recordID: recordID)
        record["title"] = task.title
        record["notes"] = task.notes
        record["dueDate"] = task.dueDate
        record["completed"] = NSNumber(value: task.completed)
        record["completedAt"] = task.completedAt
        record["priority"] = task.priority.rawValue
        record["lastModified"] = task.lastModified
        return record
    }
}
