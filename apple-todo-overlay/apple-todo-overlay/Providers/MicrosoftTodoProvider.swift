import AuthenticationServices
import CryptoKit
import Foundation
import Security

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
    // PKCE and CSRF state, valid only during an in-progress sign-in
    private var pendingVerifier: String?
    private var pendingState: String?

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

    func deleteRemote(_ tasks: [TodoTask]) async throws {
        let token = try await validToken()
        for task in tasks {
            guard let extId = task.externalId, let listId = task.listId else { continue }
            msLog("delete remote task '\(task.title)' extId=\(extId)")
            try await delete("/lists/\(listId)/tasks/\(extId)", token: token)
        }
    }

    func pushChanges(_ tasks: [TodoTask]) async throws {
        let token = try await validToken()

        // Resolve a default list ID for tasks that have no assigned list
        var defaultListId: String?

        for task in tasks {
            if let extId = task.externalId, let listId = task.listId {
                // Existing MS Todo task — PATCH all editable fields
                let update = MSTaskPatch(
                    title: task.title,
                    status: task.completed ? "completed" : "notStarted",
                    importance: task.priority.msImportance,
                    body: MSBody(content: task.notes ?? ""),
                    dueDateTime: task.dueDate.map { MSDateTimeTimeZone(dateTime: isoDateOnly.string(from: $0)) },
                    completedDateTime: task.completedAt.map { MSDateTimeTimeZone(dateTime: isoFull.string(from: $0)) }
                )
                let body = try JSONEncoder().encode(update)
                msLog("push PATCH task '\(task.title)' → list \(listId)")
                try await patch("/lists/\(listId)/tasks/\(extId)", body: body, token: token)

            } else {
                // New local task — POST to the default MS Todo list
                if defaultListId == nil {
                    defaultListId = try await resolveDefaultListId(token: token)
                }
                guard let listId = defaultListId else {
                    msLog("push skip '\(task.title)': no default list available")
                    continue
                }
                let create = MSTaskCreate(
                    title: task.title,
                    importance: task.priority.msImportance,
                    body: MSBody(content: task.notes ?? ""),
                    dueDateTime: task.dueDate.map { MSDateTimeTimeZone(dateTime: isoDateOnly.string(from: $0)) }
                )
                let body = try JSONEncoder().encode(create)
                msLog("push POST task '\(task.title)' → list \(listId)")
                let responseData = try await post("/lists/\(listId)/tasks", body: body, token: token)
                if let created = try? JSONDecoder().decode(MSTask.self, from: responseData),
                   var updated = (try? TaskRepository.shared.getAllTasks())?.first(where: { $0.id == task.id }) {
                    updated.externalId = created.id
                    updated.listId = listId
                    updated.source = .microsoftTodo
                    updated.syncStatus = .synced
                    try? TaskRepository.shared.updateTask(updated)
                    msLog("push created externalId \(created.id) for '\(task.title)'")
                }
            }
        }
    }

    private func resolveDefaultListId(token: String) async throws -> String? {
        let data = try await get("/lists", token: token)
        let lists = try JSONDecoder().decode(ODataList<MSList>.self, from: data).value
        return (lists.first(where: { $0.wellknownListName == "defaultList" }) ?? lists.first)?.id
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

        let verifier  = generateCodeVerifier()
        let challenge = codeChallenge(for: verifier)
        let state     = UUID().uuidString
        pendingVerifier = verifier
        pendingState    = state

        var comps = URLComponents(string: "\(Self.authBase)/authorize")!
        comps.queryItems = [
            URLQueryItem(name: "client_id",             value: Self.clientId),
            URLQueryItem(name: "response_type",         value: "code"),
            URLQueryItem(name: "redirect_uri",          value: Self.redirectURI),
            URLQueryItem(name: "scope",                 value: Self.scopes),
            URLQueryItem(name: "state",                 value: state),
            URLQueryItem(name: "code_challenge",        value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
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
        let parts = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)
        let returnedState = parts?.queryItems?.first(where: { $0.name == "state" })?.value
        guard returnedState == pendingState else {
            msLog("ERROR: state mismatch — possible CSRF. Expected \(pendingState ?? "nil"), got \(returnedState ?? "nil")")
            pendingState = nil; pendingVerifier = nil
            return false
        }
        guard let code = parts?.queryItems?.first(where: { $0.name == "code" })?.value else {
            msLog("ERROR: no code in callback. queryItems: \(parts?.queryItems ?? [])")
            pendingState = nil; pendingVerifier = nil
            return false
        }
        msLog("auth code received (length \(code.count))")

        let verifierToUse = pendingVerifier ?? ""
        pendingState = nil
        pendingVerifier = nil

        do {
            let token = try await exchangeCode(code, verifier: verifierToUse)
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

    private func exchangeCode(_ code: String, verifier: String) async throws -> String {
        let body = formBody([
            "client_id":     Self.clientId,
            "grant_type":    "authorization_code",
            "code":          code,
            "redirect_uri":  Self.redirectURI,
            "scope":         Self.scopes,
            "code_verifier": verifier,
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
        msLog("token response [\(status)]: \(status == 200 ? "<redacted>" : (String(data: data, encoding: .utf8) ?? "<binary>"))")
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
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status < 200 || status >= 300 {
            msLog("PATCH \(path) failed with status \(status)")
        }
    }

    private func delete(_ path: String, token: String) async throws {
        var req = URLRequest(url: URL(string: Self.graphBase + path)!)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status < 200 || status >= 300 {
            msLog("DELETE \(path) failed with status \(status)")
        }
    }

    @discardableResult
    private func post(_ path: String, body: Data, token: String) async throws -> Data {
        var req = URLRequest(url: URL(string: Self.graphBase + path)!)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = body
        let (data, response) = try await URLSession.shared.data(for: req)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        if status < 200 || status >= 300 {
            msLog("POST \(path) failed with status \(status): \(String(data: data, encoding: .utf8) ?? "")")
        }
        return data
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

    // MS Todo dueDateTime uses date-only (midnight UTC)
    private let isoDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
        f.timeZone = TimeZone(identifier: "UTC")
        return f
    }()
}

// MARK: - Token store (Keychain)

private enum MSTokenStore {
    private static let service = "apple-todo-overlay.ms-todo"

    private enum Key {
        static let access  = "accessToken"
        static let refresh = "refreshToken"
        static let expiry  = "tokenExpiry"
    }

    static var accessToken:  String? { read(Key.access) }
    static var refreshToken: String? { read(Key.refresh) }
    static var tokenExpiry:  Date? {
        guard let s = read(Key.expiry) else { return nil }
        return ISO8601DateFormatter().date(from: s)
    }

    static func store(_ response: MSTokenResponse) {
        write(response.access_token, forKey: Key.access)
        if let rt = response.refresh_token { write(rt, forKey: Key.refresh) }
        let expiry = Date().addingTimeInterval(TimeInterval(response.expires_in))
        write(ISO8601DateFormatter().string(from: expiry), forKey: Key.expiry)
    }

    static func clear() {
        delete(Key.access)
        delete(Key.refresh)
        delete(Key.expiry)
    }

    // MARK: Keychain primitives

    private static func read(_ key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func write(_ value: String, forKey key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        let status = SecItemUpdate(query as CFDictionary, [kSecValueData: data] as CFDictionary)
        if status == errSecItemNotFound {
            SecItemAdd(query.merging([kSecValueData: data]) { $1 } as CFDictionary, nil)
        }
    }

    private static func delete(_ key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key,
        ]
        SecItemDelete(query as CFDictionary)
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
    let wellknownListName: String?
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

private struct MSBody: Codable {
    let content: String?
}

private struct MSDateTimeTimeZone: Codable {
    let dateTime: String
    var timeZone: String = "UTC"
}

private struct MSTaskPatch: Encodable {
    let title: String
    let status: String
    let importance: String
    let body: MSBody
    let dueDateTime: MSDateTimeTimeZone?
    let completedDateTime: MSDateTimeTimeZone?
}

private struct MSTaskCreate: Encodable {
    let title: String
    let importance: String
    let body: MSBody
    let dueDateTime: MSDateTimeTimeZone?
}

private struct MSTokenResponse: Decodable {
    let access_token: String
    let refresh_token: String?
    let expires_in: Int
}

// MARK: - PKCE helpers

private extension MicrosoftTodoProvider {
    /// Generates a cryptographically random code_verifier (RFC 7636).
    func generateCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncoded
    }

    /// Returns BASE64URL(SHA256(verifier)) as the code_challenge.
    func codeChallenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return Data(digest).base64URLEncoded
    }
}

private extension Data {
    /// Base64URL encoding without padding (RFC 4648 §5).
    var base64URLEncoded: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
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
