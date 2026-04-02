import Foundation

struct Tag: Identifiable, Hashable, Codable {
    let id: String
    var name: String
    var colour: String
    let createdAt: Date
}
