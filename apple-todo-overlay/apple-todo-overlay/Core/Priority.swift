enum Priority: String, Codable, CaseIterable {
    case high   = "HIGH"
    case medium = "MEDIUM"
    case low    = "LOW"
    case none   = "NONE"

    var sortOrder: Int {
        switch self {
        case .high:   return 0
        case .medium: return 1
        case .low:    return 2
        case .none:   return 3
        }
    }
}
