enum SyncStatus: String, Codable {
    case synced            = "SYNCED"
    case pendingUpload     = "PENDING_UPLOAD"
    case pendingDownload   = "PENDING_DOWNLOAD"
    case conflict          = "CONFLICT"
    case error             = "ERROR"
}
