import XCTest
@testable import ReactNotes

final class DataStoreTests: XCTestCase {
    private var tempDirectoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectoryURL, withIntermediateDirectories: true)
        fileURL = tempDirectoryURL.appendingPathComponent("app_data.json")
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
    }

    func testDefaultDataRoundTrip() throws {
        let store = DataStore(fileURL: fileURL)
        store.saveNowSync()

        let loadedStore = DataStore(fileURL: fileURL)
        XCTAssertEqual(store.appData.schemaVersion, loadedStore.appData.schemaVersion)
        XCTAssertEqual(store.appData.folders.count, loadedStore.appData.folders.count)
        XCTAssertEqual(store.appData.notebooks.count, loadedStore.appData.notebooks.count)
        XCTAssertEqual(store.appData.notes.count, loadedStore.appData.notes.count)
    }

    func testCreateAndDeleteNote() throws {
        let store = DataStore(fileURL: fileURL)
        guard let notebookId = store.appData.notebooks.first?.id else {
            return XCTFail("Expected seeded notebook")
        }

        let newNote = store.createNote(in: notebookId, title: "Test Note")
        XCTAssertTrue(store.notes(in: notebookId).contains(where: { $0.id == newNote.id }))

        store.deleteNote(id: newNote.id)
        XCTAssertFalse(store.notes(in: notebookId).contains(where: { $0.id == newNote.id }))
    }

    func testWriteReadSanity() throws {
        let store = DataStore(fileURL: fileURL)
        guard let note = store.appData.notes.first else {
            return XCTFail("Expected seeded note")
        }

        store.updateNote(id: note.id, title: "Updated", body: "Hello persistence")
        store.saveNowSync()

        let loaded = DataStore(fileURL: fileURL)
        guard let loadedNote = loaded.appData.notes.first(where: { $0.id == note.id }) else {
            return XCTFail("Expected saved note")
        }

        XCTAssertEqual(loadedNote.title, "Updated")
        XCTAssertEqual(loadedNote.body, "Hello persistence")
    }

    func testCanvasDataRoundTrip() throws {
        let store = DataStore(fileURL: fileURL)
        guard let note = store.appData.notes.first else {
            return XCTFail("Expected seeded note")
        }

        let fakeCanvasData = Data([0x01, 0x02, 0x03, 0x04, 0xFF])
        store.updateNoteCanvas(id: note.id, canvasData: fakeCanvasData)
        store.saveNowSync()

        let loaded = DataStore(fileURL: fileURL)
        guard let loadedNote = loaded.appData.notes.first(where: { $0.id == note.id }) else {
            return XCTFail("Expected saved note with canvas data")
        }

        XCTAssertEqual(loadedNote.canvasData, fakeCanvasData)
    }

    func testToggleFavorite() throws {
        let store = DataStore(fileURL: fileURL)
        guard let note = store.appData.notes.first else {
            return XCTFail("Expected seeded note")
        }

        XCTAssertFalse(note.isFavorite)
        store.toggleFavorite(id: note.id)
        XCTAssertTrue(store.appData.notes.first(where: { $0.id == note.id })!.isFavorite)
        store.toggleFavorite(id: note.id)
        XCTAssertFalse(store.appData.notes.first(where: { $0.id == note.id })!.isFavorite)
    }

    func testSchemaMigrationV1toV2() throws {
        // Build a v1 JSON payload (no canvasData, no isFavorite, schemaVersion=1)
        let v1Json = """
        {
          "schemaVersion": 1,
          "folders": [
            {"id": "f1", "name": "Old Folder", "order": 0}
          ],
          "notebooks": [
            {"id": "nb1", "title": "Old Notebook", "folderId": "f1", "createdAt": "2024-01-01T00:00:00Z", "updatedAt": "2024-01-01T00:00:00Z"}
          ],
          "notes": [
            {"id": "n1", "notebookId": "nb1", "title": "Old Note", "body": "Legacy body", "createdAt": "2024-01-01T00:00:00Z", "updatedAt": "2024-01-01T00:00:00Z"}
          ]
        }
        """
        try v1Json.data(using: .utf8)!.write(to: fileURL)

        let store = DataStore(fileURL: fileURL)

        // After loading, schema should be migrated to v2
        XCTAssertEqual(store.appData.schemaVersion, AppDataFactory.schemaVersion)

        // Original data should be preserved
        XCTAssertEqual(store.appData.folders.count, 1)
        XCTAssertEqual(store.appData.folders.first?.name, "Old Folder")
        XCTAssertEqual(store.appData.notes.first?.title, "Old Note")
        XCTAssertEqual(store.appData.notes.first?.body, "Legacy body")

        // New fields should have safe defaults
        XCTAssertNil(store.appData.notes.first?.canvasData)
        XCTAssertEqual(store.appData.notes.first?.isFavorite, false)

        // Verify migrated data was saved
        store.saveNowSync()
        let reloaded = DataStore(fileURL: fileURL)
        XCTAssertEqual(reloaded.appData.schemaVersion, AppDataFactory.schemaVersion)
    }

    func testAllNotesSorted() throws {
        let store = DataStore(fileURL: fileURL)
        guard let notebookId = store.appData.notebooks.first?.id else {
            return XCTFail("Expected seeded notebook")
        }

        let note1 = store.createNote(in: notebookId, title: "First")
        let note2 = store.createNote(in: notebookId, title: "Second")

        // Verify both notes appear in the sorted list
        let sorted = store.allNotesSorted()
        XCTAssertTrue(sorted.contains(where: { $0.id == note1.id }))
        XCTAssertTrue(sorted.contains(where: { $0.id == note2.id }))

        // Update note1 to give it a definitively newer timestamp, then verify ordering
        store.updateNote(id: note1.id, title: "First Updated", body: "")
        let sortedAfterUpdate = store.allNotesSorted()
        XCTAssertTrue(
            sortedAfterUpdate.firstIndex(where: { $0.id == note1.id })! <
            sortedAfterUpdate.firstIndex(where: { $0.id == note2.id })!
        )
    }

    func testNotesInFolder() throws {
        let store = DataStore(fileURL: fileURL)
        guard let folder = store.appData.folders.first else {
            return XCTFail("Expected seeded folder")
        }

        let notesInFolder = store.notes(inFolder: folder.id)
        XCTAssertFalse(notesInFolder.isEmpty)

        // Notes from other folders should not appear
        let otherFolder = store.createFolder(named: "Other Folder")
        let otherNotebook = store.createNotebook(in: otherFolder.id, title: "Other Notebook")
        let _ = store.createNote(in: otherNotebook.id, title: "Other Note")

        let folderNotes = store.notes(inFolder: folder.id)
        XCTAssertFalse(folderNotes.contains(where: { note in
            !store.appData.notebooks.filter { $0.folderId == folder.id }.map(\.id).contains(note.notebookId)
        }))
    }
}
