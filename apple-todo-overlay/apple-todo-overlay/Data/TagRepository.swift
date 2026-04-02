import Foundation

final class TagRepository {

    static let shared = TagRepository()
    private let db = LocalDatabase.shared

    private init() {}

    func getAllTags() throws -> [Tag] {
        let rows = try db.query("SELECT * FROM tags ORDER BY name ASC;")
        return rows.compactMap { TaskMapper.toTag(row: $0) }
    }

    func saveTag(_ tag: Tag) throws {
        try db.run("""
            INSERT INTO tags (id, name, colour, created_at) VALUES (?, ?, ?, ?);
        """, params: [tag.id, tag.name, tag.colour, tag.createdAt])
    }

    func updateTag(_ tag: Tag) throws {
        try db.run("""
            UPDATE tags SET name = ?, colour = ? WHERE id = ?;
        """, params: [tag.name, tag.colour, tag.id])
    }

    func deleteTag(id: String) throws {
        try db.run("DELETE FROM tags WHERE id = ?;", params: [id])
    }
}
