import AuthenticationServices
import Foundation

// MARK: - Provider

final class MicrosoftTodoProvider: TaskProvider {

    // -------------------------------------------------------------------------
    // App registration — portal.azure.com → App Registrations → New registration
    //   • Supported account types: "Personal Microsoft accounts only"
    //   • Redirect URI (Mobile & desktop): appletodo://auth
    // -------------------------------------------------------------------------
    static var clientId = "b6d2577f-368d-4163-bc6b-8e07a3a5c2fb"

    private static let redirectScheme = "appletodo"
    private static let redirectURI    = "\(redirectScheme)://auth"
    private static let scopes         = "Tasks.ReadWrite offline_access"
    private static let authBase       = "https://login.microsoftonline.com/consumers/oauth2/v2.0"
    private static let graphBase      = "https://graph.microsoft.com/v1.0/me/todo"

    // Kept alive during the ASWebAuthenticationSession callback round-trip
    private var authSession: ASWebAuthenticationSession?

    // MARK: - TaskProvider

    func isAvailable() -> Bool {
        MSTokenStore.accessToken != nil || MSTokenStore.refreshToken != nil
    }

    func fetchLists() async throws -> [TaskList] {
        msLog("fetchLists()")
        let token = try await validToken()
        let data = try await get("/lists", token: token)
        msLog("lists raw: \(String(data: data, encoding: .utf8) ?? "<binary>")")
        let response = try JSONDecoder().decode(ODataList<MSList>.self, from: data)
        msLog("lists decoded: \(response.value.map(\.displayName))")
        let now = Date()
        return response.value.map { list in
            TaskList(id: list.id, name: list.displayName, source: .microsoftTodo,
                     externalId: list.id, createdAt: now, lastModified: now)
        }
    }

    func fetchChanges(since date: Date) async throws -> [TodoTask] {
        msLog("fetchChanges(since: \(date))")
        let token = try await validToken()

        let listsData = try await get("/lists", token: token)
        let lists = try JSONDecoder().decode(ODataList<MSList>.self, from: listsData).value
        msLog("fetchChanges: \(lists.count) list(s): \(lists.map(\.displayName))")

        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let dateString = iso.string(from: date)

        var tasks: [TodoTask] = []
        for list in lists {
            // Build URL manually to avoid URLComponents percent-encoding the $ in $filter
            let urlStr = "\(Self.graphBase)/lists/\(list.id)/tasks?$filter=lastModifiedDateTime%20ge%20\(dateString)"
            guard let url = URL(string: urlStr) else {
                msLog("ERROR: bad URL for list \(list.displayName)")
                continue
            }
            msLog("fetching tasks: \(urlStr)")
            let taskData = try await get(url: url, token: token)
            msLog("tasks raw [\(list.displayName)]: \(String(data: taskData, encoding: .utf8) ?? "<binary>")")
            let response = try JSONDecoder().decode(ODataList<MSTask>.self, from: taskData)
            msLog("tasks decoded [\(list.displayName)]: \(response.value.count) task(s)")
            tasks += response.value.compactMap { map($0, listId: list.id) }
        }
        msLog("fetchChanges returning \(tasks.count) total task(s)")
        return tasks
    }

    func pushChanges(_ tasks: [TodoTask]) async throws {
        let token = try await validToken()
        for task in tasks {
            guard let extId = task.externalId, let listId = task.listId else { continue }
            let update = MSTaskUpdate(
                status: task.completed ? "completed" : "notStarted",
                importance: task.priority.msImportance,
                completedDateTime: task.completedAt.map { MSDateTimeTimeZone(dateTime: isoFull.string(from: $0)) }
            )
            let body = try JSONEncoder().encode(update)
            try await patch("/lists/\(listId)/tasks/\(extId)", body: body, token: token)
        }
    }

    // MARK: - Sign in / out

    /// Triggers the OAuth browser flow. Returns true if sign-in succeeded.
    /// Call this from a button in the settings UI when the user wants to connect Microsoft To Do.
    @MainActor
    func signIn() async -> Bool {
        msLog("signIn() started")
        msLog("clientId: \(Self.clientId)")
        msLog("redirectURI: \(Self.redirectURI)")
        msLog("redirectScheme: \(Self.redirectScheme)")

        var comps = URLComponents(string: "\(Self.authBase)/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id",     value: Self.clientId),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri",  value: Self.redirectURI),
            URLQueryItem(name: "scope",         value: Self.scopes),
            URLQueryItem(name: "state",         value: UUID().uuidString),
        ]
        guard let authURL = comps.url else {
            msLog("ERROR: failed to build auth URL")
            return false
        }
        msLog("auth URL: \(authURL)")

        let callbackURL: URL
        do {
            msLog("starting ASWebAuthenticationSession...")
            callbackURL = try await withCheckedThrowingContinuation { cont in
                let session = ASWebAuthenticationSession(
                    url: authURL,
                    callbackURLScheme: Self.redirectScheme
                ) { [weak self] url, error in
                    self?.authSession = nil
                    if let url {
                        msLog("callback received: \(url)")
                        cont.resume(returning: url)
                    } else {
                        msLog("callback error: \(error?.localizedDescription ?? "unknown")")
                        cont.resume(throwing: error ?? URLError(.cancelled))
                    }
                }
                session.presentationContextProvider = AnchorProvider.shared
                session.prefersEphemeralWebBrowserSession = true
                authSession = session
                session.start()
                msLog("ASWebAuthenticationSession started")
            }
        } catch {
            msLog("ERROR: session threw — \(error)")
            return false
        }

        msLog("callbackURL: \(callbackURL)")
        guard
            let parts = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
            let code  = parts.queryItems?.first(where: { $0.name == "code" })?.value
        else {
            let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems
            msLog("ERROR: no code in callback. queryItems: \(items ?? [])")
            return false
        }
        msLog("auth code received (length \(code.count))")

        do {
            let token = try await exchangeCode(code)
            msLog("sign-in succeeded — access token length: \(token.count)")
            return true
        } catch {
            msLog("ERROR: token exchange failed — \(error)")
            return false
        }
    }

    func signOut() {
        MSTokenStore.clear()
    }

    // MARK: - Token management

    private func validToken() async throws -> String {
        if let token = MSTokenStore.accessToken,
           let expiry = MSTokenStore.tokenExpiry,
           expiry > Date().addingTimeInterval(60) {
            return token
        }
        if let refresh = MSTokenStore.refreshToken {
            return try await refreshAccessToken(refresh)
        }
        throw MSTodoError.notAuthenticated
    }

    private func exchangeCode(_ code: String) async throws -> String {
        let body = formBody([
            "client_id":    Self.clientId,
            "grant_type":   "authorization_code",
            "code":         code,
            "redirect_uri": Self.redirectURI,
            "scope":        Self.scopes,
        ])
        let response = try await tokenRequest(body: body)
        MSTokenStore.store(response)
        return response.access_token
    }

    private func refreshAccessToken(_ refreshToken: String) async throws -> String {
        let body = formBody([
            "client_id":     Self.clientId,
            "grant_type":    "refresh_token",
            "refresh_token": refreshToken,
            "scope":         Self.scopes,
        ])
        let response = try await tokenRequest(body: body)
        MSTokenStore.store(response)
        return response.access_token
    }

    private func tokenRequest(body: Data) async throws -> MSTokenResponse {
        var req = URLRequest(url: URL(string: "\(Self.authBase)/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        msLog("token request → \(Self.authBase)/token")
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let raw = String(data: data, encoding: .utf8) ?? "<binary>"
        msLog("token response [\(status)]: \(raw)")
        return try JSONDecoder().decode(MSTokenResponse.self, from: data)
    }

    private func formBody(_ params: [String: String]) -> Data {
        params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
              .joined(separator: "&")
              .data(using: .utf8)!
    }

    // MARK: - HTTP helpers

    private func get(_ path: String, token: String) async throws -> Data {
        try await get(url: URL(string: Self.graphBase + path)!, token: token)
    }

    private func get(url: URL, token: String) async throws -> Data {
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: req)
        return data
    }

    private func patch(_ path: String, body: Data, token: String) async throws {
        var req = URLRequest(url: URL(string: Self.graphBase + path)!)
        req.httpMethod = "PATCH"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        _ = try await URLSession.shared.data(for: req)
    }

    // MARK: - Mapping

    private func map(_ ms: MSTask, listId: String) -> TodoTask? {
        let lastModified = parseDate(ms.lastModifiedDateTime) ?? Date()
        let createdAt    = parseDate(ms.createdDateTime)    ?? Date()
        // dueDateTime / completedDateTime use a "dateTime" field without timezone suffix
        let dueDate     = ms.dueDateTime.flatMap       { parseDate($0.dateTime + "Z") }
        let completedAt = ms.completedDateTime.flatMap { parseDate($0.dateTime + "Z") }

        return TodoTask(
            id:           UUID().uuidString,
            title:        ms.title,
            notes:        ms.body?.content,
            dueDate:      dueDate,
            completed:    ms.status == "completed",
            completedAt:  completedAt,
            source:       .microsoftTodo,
            externalId:   ms.id,
            createdAt:    createdAt,
            lastModified: lastModified,
            syncStatus:   .synced,
            listId:       listId,
            priority:     Priority(msImportance: ms.importance ?? "normal"),
            tags:         []
        )
    }

    private func parseDate(_ string: String?) -> Date? {
        guard let string else { return nil }
        return isoFull.date(from: string) ?? isoBasic.date(from: string)
    }

    private let isoFull: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private let isoBasic: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()
}

// MARK: - Token store

private enum MSTokenStore {
    private static let defaults = UserDefaults.standard
    private enum Key {
        static let access  = "ms.todo.accessToken"
        static let refresh = "ms.todo.refreshToken"
        static let expiry  = "ms.todo.tokenExpiry"
    }

    static var accessToken:  String? { defaults.string(forKey: Key.access) }
    static var refreshToken: String? { defaults.string(forKey: Key.refresh) }
    static var tokenExpiry:  Date?   { defaults.object(forKey: Key.expiry) as? Date }

    static func store(_ response: MSTokenResponse) {
        defaults.set(response.access_token, forKey: Key.access)
        if let rt = response.refresh_token { defaults.set(rt, forKey: Key.refresh) }
        defaults.set(Date().addingTimeInterval(TimeInterval(response.expires_in)), forKey: Key.expiry)
    }

    static func clear() {
        defaults.removeObject(forKey: Key.access)
        defaults.removeObject(forKey: Key.refresh)
        defaults.removeObject(forKey: Key.expiry)
    }
}

// MARK: - ASWebAuthentication anchor

// MARK: - Logging

private func msLog(_ message: String) {
    let ts = DateFormatter.localizedString(from: Date(), dateStyle: .none, timeStyle: .medium)
    print("[MSTodo \(ts)] \(message)")
}

// MARK: - Presentation anchor

private final class AnchorProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = AnchorProvider()
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.windows.first(where: { $0.isVisible }) ?? NSWindow()
    }
}

// MARK: - Errors

enum MSTodoError: Error {
    case notAuthenticated
}

// MARK: - Codable models

private struct ODataList<T: Decodable>: Decodable {
    let value: [T]
}

private struct MSList: Decodable {
    let id: String
    let displayName: String
}

private struct MSTask: Decodable {
    let id: String
    let title: String
    let status: String?
    let importance: String?
    let dueDateTime: MSDateTimeTimeZone?
    let completedDateTime: MSDateTimeTimeZone?
    let lastModifiedDateTime: String?
    let createdDateTime: String?
    let body: MSBody?
}

private struct MSBody: Decodable {
    let content: String?
}

private struct MSDateTimeTimeZone: Codable {
    let dateTime: String
    var timeZone: String = "UTC"
}

private struct MSTaskUpdate: Encodable {
    let status: String
    let importance: String
    let completedDateTime: MSDateTimeTimeZone?
}

private struct MSTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

// MARK: - Priority ↔ MS importance

private extension Priority {
    var msImportance: String {
        switch self {
        case .high:   return "high"
        case .medium: return "normal"
        case .low:    return "low"
        case .none:   return "normal"
        }
    }

    init(msImportance: String) {
        switch msImportance {
        case "high": self = .high
        case "low":  self = .low
        default:     self = .none
        }
    }
}
