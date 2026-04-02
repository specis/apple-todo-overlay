enum TaskSource: String, Codable {
    case local           = "LOCAL"
    case appleReminders  = "APPLE_REMINDERS"
    case microsoftTodo   = "MICROSOFT_TODO"
    case cloudKit        = "CLOUDKIT"
}
