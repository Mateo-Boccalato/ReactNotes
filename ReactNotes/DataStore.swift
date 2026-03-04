import Foundation

extension Notification.Name {
    static let appDataDidChange = Notification.Name("appDataDidChange")
}

final class DataStore {
    static let shared = DataStore()

    private(set) var appData: AppData

    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let saveQueue = DispatchQueue(label: "com.mateobocc.reactnotes.datastore", qos: .utility)
    private var pendingSaveWorkItem: DispatchWorkItem?
    private let saveDelaySeconds: TimeInterval = 2.0
    private var pendingNotifyWorkItem: DispatchWorkItem?
    private let notifyDelaySeconds: TimeInterval = 0.3

    private let persistenceURL: URL

    init(fileURL: URL? = nil) {
        encoder = JSONEncoder()
        // Removed .prettyPrinted and .sortedKeys for better performance
        // These formatting options can slow down encoding by 50-80%
        decoder = JSONDecoder()
        if let fileURL {
            persistenceURL = fileURL
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            persistenceURL = documents.appendingPathComponent("app_data.json")
        }
        appData = AppDataFactory.makeDefault()
        load()
    }

    // MARK: - Paths

    var dataFileURL: URL {
        persistenceURL
    }

    private var tempFileURL: URL {
        dataFileURL.appendingPathExtension("tmp")
    }

    // MARK: - Loading/Saving

    private func load() {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        guard let data = try? Data(contentsOf: dataFileURL) else {
            appData = AppDataFactory.makeDefault()
            print("⏱️ DataStore: No existing data, created default (\(CFAbsoluteTimeGetCurrent() - startTime)s)")
            return
        }

        print("⏱️ DataStore: Read \(data.count / 1024)KB from disk (\(CFAbsoluteTimeGetCurrent() - startTime)s)")
        
        do {
            let decodeStart = CFAbsoluteTimeGetCurrent()
            var decoded = try decoder.decode(AppData.self, from: data)
            print("⏱️ DataStore: Decoded JSON (\(CFAbsoluteTimeGetCurrent() - decodeStart)s)")
            print("   - \(decoded.notebooks.count) notebooks, \(decoded.notes.count) notes")
            
            if decoded.schemaVersion < AppDataFactory.schemaVersion {
                decoded = AppDataFactory.migrate(decoded)
                appData = decoded
                saveNow()
                print("⏱️ DataStore: Migrated schema and saved")
            } else {
                appData = decoded
            }
            
            print("⏱️ DataStore: Total load time: \(CFAbsoluteTimeGetCurrent() - startTime)s")
        } catch {
            appData = AppDataFactory.makeDefault()
            print("⚠️ DataStore: Failed to decode, using default data: \(error)")
        }
    }

    private func performSave(snapshot: AppData) {
        do {
            let data = try self.encoder.encode(snapshot)
            try data.write(to: self.tempFileURL, options: .atomic)
            if FileManager.default.fileExists(atPath: self.dataFileURL.path) {
                try FileManager.default.removeItem(at: self.dataFileURL)
            }
            try FileManager.default.moveItem(at: self.tempFileURL, to: self.dataFileURL)
        } catch {
            // Keep persistence failure handling simple.
        }
    }

    func saveNow() {
        let snapshot = self.appData
        saveQueue.async { [self] in
            performSave(snapshot: snapshot)
        }
    }

    func saveNowSync() {
        let snapshot = self.appData
        saveQueue.sync {
            performSave(snapshot: snapshot)
        }
    }

    private func scheduleSaveAndNotify() {
        pendingSaveWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSaveWorkItem = workItem
        saveQueue.asyncAfter(deadline: .now() + saveDelaySeconds, execute: workItem)

        pendingNotifyWorkItem?.cancel()
        let notifyItem = DispatchWorkItem {
            NotificationCenter.default.post(name: .appDataDidChange, object: nil)
        }
        pendingNotifyWorkItem = notifyItem
        DispatchQueue.main.asyncAfter(deadline: .now() + notifyDelaySeconds, execute: notifyItem)
    }

    // MARK: - Helpers

    private func nowISO() -> String {
        AppDataFactory.isoNow()
    }

    func notebooksSorted() -> [Notebook] {
        appData.notebooks.sorted { $0.order < $1.order }
    }

    func notes(in notebookId: String) -> [Note] {
        appData.notes
            .filter { $0.notebookId == notebookId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func allNotesSorted() -> [Note] {
        appData.notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Notebook CRUD

    @discardableResult
    func createNotebook(title: String = "Untitled Notebook", color: String? = nil) -> Notebook {
        let timestamp = nowISO()
        let notebook = Notebook(
            id: UUID().uuidString,
            title: title,
            createdAt: timestamp,
            updatedAt: timestamp,
            color: color,
            order: appData.notebooks.count
        )
        appData.notebooks.append(notebook)
        scheduleSaveAndNotify()
        return notebook
    }

    func updateNotebook(id: String, title: String? = nil, color: String? = nil) {
        guard let index = appData.notebooks.firstIndex(where: { $0.id == id }) else { return }
        if let title { appData.notebooks[index].title = title }
        if let color { appData.notebooks[index].color = color }
        appData.notebooks[index].updatedAt = nowISO()
        scheduleSaveAndNotify()
    }

    func deleteNotebook(id: String) {
        appData.notes.removeAll { $0.notebookId == id }
        appData.notebooks.removeAll { $0.id == id }
        if appData.notebooks.isEmpty {
            _ = createNotebook(title: "My Notebook")
        } else {
            scheduleSaveAndNotify()
        }
    }

    // MARK: - Note CRUD

    @discardableResult
    func createNote(in notebookId: String, title: String = "Untitled Note") -> Note {
        let timestamp = nowISO()
        let note = Note(
            id: UUID().uuidString,
            notebookId: notebookId,
            title: title,
            body: "",
            createdAt: timestamp,
            updatedAt: timestamp
        )
        appData.notes.append(note)
        touchNotebook(id: notebookId)
        scheduleSaveAndNotify()
        return note
    }

    func updateNote(id: String, title: String, body: String, canvasData: Data? = nil) {
        guard let index = appData.notes.firstIndex(where: { $0.id == id }) else { return }
        appData.notes[index].title = title
        appData.notes[index].body = body
        if let canvasData {
            appData.notes[index].canvasData = canvasData
        }
        appData.notes[index].updatedAt = nowISO()
        touchNotebook(id: appData.notes[index].notebookId)
        scheduleSaveAndNotify()
    }

    func updateNoteCanvas(id: String, canvasData: Data) {
        guard let index = appData.notes.firstIndex(where: { $0.id == id }) else { return }
        appData.notes[index].canvasData = canvasData
        appData.notes[index].updatedAt = nowISO()
        touchNotebook(id: appData.notes[index].notebookId)
        scheduleSaveAndNotify()
    }

    func toggleFavorite(id: String) {
        guard let index = appData.notes.firstIndex(where: { $0.id == id }) else { return }
        appData.notes[index].isFavorite.toggle()
        scheduleSaveAndNotify()
    }

    func togglePencilOnlyMode(id: String) {
        guard let index = appData.notes.firstIndex(where: { $0.id == id }) else { return }
        appData.notes[index].pencilOnlyMode.toggle()
        scheduleSaveAndNotify()
    }

    func deleteNote(id: String) {
        guard let note = appData.notes.first(where: { $0.id == id }) else { return }
        appData.notes.removeAll { $0.id == id }
        touchNotebook(id: note.notebookId)
        scheduleSaveAndNotify()
    }

    private func touchNotebook(id: String) {
        guard let index = appData.notebooks.firstIndex(where: { $0.id == id }) else { return }
        appData.notebooks[index].updatedAt = nowISO()
    }
}
