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
            print("   - \(decoded.folders.count) folders, \(decoded.notebooks.count) notebooks, \(decoded.notes.count) notes")
            
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

    func foldersSorted() -> [Folder] {
        appData.folders.sorted { $0.order < $1.order }
    }

    func notebooks(in folderId: String) -> [Notebook] {
        appData.notebooks
            .filter { $0.folderId == folderId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func notes(in notebookId: String) -> [Note] {
        appData.notes
            .filter { $0.notebookId == notebookId }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    func allNotesSorted() -> [Note] {
        appData.notes.sorted { $0.updatedAt > $1.updatedAt }
    }

    func notes(inFolder folderId: String) -> [Note] {
        let notebookIds = Set(appData.notebooks.filter { $0.folderId == folderId }.map(\.id))
        return appData.notes
            .filter { notebookIds.contains($0.notebookId) }
            .sorted { $0.updatedAt > $1.updatedAt }
    }

    // MARK: - Folder CRUD

    @discardableResult
    func createFolder(named name: String, color: String? = nil) -> Folder {
        let folder = Folder(
            id: UUID().uuidString,
            name: name.isEmpty ? "Untitled Folder" : name,
            parentFolderId: nil,
            order: appData.folders.count,
            color: color
        )
        appData.folders.append(folder)
        scheduleSaveAndNotify()
        return folder
    }

    func updateFolder(id: String, name: String? = nil, color: String? = nil) {
        guard let index = appData.folders.firstIndex(where: { $0.id == id }) else { return }
        if let name { appData.folders[index].name = name }
        if let color { appData.folders[index].color = color }
        scheduleSaveAndNotify()
    }

    func deleteFolder(id: String) {
        let notebookIds = appData.notebooks.filter { $0.folderId == id }.map(\.id)
        appData.notes.removeAll { notebookIds.contains($0.notebookId) }
        appData.notebooks.removeAll { $0.folderId == id }
        appData.folders.removeAll { $0.id == id }
        if appData.folders.isEmpty {
            _ = createFolder(named: "My Folder")
        } else {
            scheduleSaveAndNotify()
        }
    }

    // MARK: - Notebook CRUD

    @discardableResult
    func createNotebook(in folderId: String, title: String = "Untitled Notebook") -> Notebook {
        let timestamp = nowISO()
        let notebook = Notebook(
            id: UUID().uuidString,
            title: title,
            folderId: folderId,
            createdAt: timestamp,
            updatedAt: timestamp
        )
        appData.notebooks.append(notebook)
        _ = createNote(in: notebook.id, title: "New Note")
        scheduleSaveAndNotify()
        return notebook
    }

    func deleteNotebook(id: String) {
        appData.notes.removeAll { $0.notebookId == id }
        appData.notebooks.removeAll { $0.id == id }
        scheduleSaveAndNotify()
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
