import Foundation

struct Notebook: Codable, Equatable {
    let id: String
    var title: String
    var createdAt: String
    var updatedAt: String
    var color: String?
    var order: Int
}

struct Note: Codable, Equatable {
    let id: String
    var notebookId: String
    var title: String
    var body: String
    var createdAt: String
    var updatedAt: String
    var canvasData: Data?
    var isFavorite: Bool
    var pencilOnlyMode: Bool

    init(
        id: String,
        notebookId: String,
        title: String,
        body: String,
        createdAt: String,
        updatedAt: String,
        canvasData: Data? = nil,
        isFavorite: Bool = false,
        pencilOnlyMode: Bool = false
    ) {
        self.id = id
        self.notebookId = notebookId
        self.title = title
        self.body = body
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.canvasData = canvasData
        self.isFavorite = isFavorite
        self.pencilOnlyMode = pencilOnlyMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        notebookId = try container.decode(String.self, forKey: .notebookId)
        title = try container.decode(String.self, forKey: .title)
        body = try container.decode(String.self, forKey: .body)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        canvasData = try container.decodeIfPresent(Data.self, forKey: .canvasData)
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        pencilOnlyMode = try container.decodeIfPresent(Bool.self, forKey: .pencilOnlyMode) ?? false
    }
}

struct AppData: Codable, Equatable {
    var schemaVersion: Int
    var notebooks: [Notebook]
    var notes: [Note]
}

enum AppDataFactory {
    static let schemaVersion = 3

    static func makeDefault() -> AppData {
        let timestamp = isoNow()
        let notebookId = UUID().uuidString
        let noteId = UUID().uuidString

        let defaultNotebook = Notebook(
            id: notebookId,
            title: "Organic Chemistry Notes",
            createdAt: timestamp,
            updatedAt: timestamp,
            color: nil,
            order: 0
        )

        let defaultNote = Note(
            id: noteId,
            notebookId: notebookId,
            title: "Welcome",
            body: "Start writing your notes here.",
            createdAt: timestamp,
            updatedAt: timestamp
        )

        return AppData(
            schemaVersion: schemaVersion,
            notebooks: [defaultNotebook],
            notes: [defaultNote]
        )
    }

    static func migrate(_ data: AppData) -> AppData {
        var migrated = data
        migrated.schemaVersion = schemaVersion
        return migrated
    }

    private static let isoFormatter = ISO8601DateFormatter()

    static func isoNow() -> String {
        isoFormatter.string(from: Date())
    }
}
