import XCTest
import PencilKit
@testable import ReactNotes

/// Tests that diagnose the freeze when opening a note from the main page.
final class NoteEditorTests: XCTestCase {

    private var tempDirectoryURL: URL!
    private var fileURL: URL!

    override func setUpWithError() throws {
        tempDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: tempDirectoryURL, withIntermediateDirectories: true)
        fileURL = tempDirectoryURL.appendingPathComponent("app_data.json")
    }

    override func tearDownWithError() throws {
        if let tempDirectoryURL {
            try? FileManager.default.removeItem(at: tempDirectoryURL)
        }
    }

    // MARK: - Helpers

    private func makeStore(canvasData: Data? = nil) -> (DataStore, String) {
        let store = DataStore(fileURL: fileURL)
        guard let noteId = store.appData.notes.first?.id else {
            fatalError("Expected seeded note")
        }
        if let canvasData {
            store.updateNoteCanvas(id: noteId, canvasData: canvasData)
        }
        return (store, noteId)
    }

    // MARK: - Tests

    /// Simulates tapping a note with no canvas data.
    func testEditorViewDidLoadWithEmptyNote() throws {
        let (store, noteId) = makeStore()

        let start = CFAbsoluteTimeGetCurrent()
        let vc = NoteEditorViewController(dataStore: store, noteId: noteId)
        _ = vc.view   // triggers viewDidLoad
        let duration = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(duration, 1.0,
            "Opening an empty note took \(duration)s — main thread may be blocked")
    }

    /// Simulates tapping a note that has large canvas data already stored.
    /// This is the primary scenario that causes a freeze.
    func testEditorViewDidLoadWithLargeCanvasData() throws {
        // 5 MB of canvas data — realistic for a drawing-heavy note
        let largeCanvasData = Data(repeating: 0xAB, count: 5_000_000)
        let (store, noteId) = makeStore(canvasData: largeCanvasData)

        let start = CFAbsoluteTimeGetCurrent()
        let vc = NoteEditorViewController(dataStore: store, noteId: noteId)
        _ = vc.view
        let duration = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(duration, 2.0,
            "Opening a note with large canvas data took \(duration)s — likely blocking main thread")
    }

    /// Verifies that canvasViewDrawingDidChange firing during loadNote()
    /// does not unnecessarily re-encode and re-save unchanged canvas data
    /// on the main thread (regression test for the double-save bug).
    func testOpeningNoteDoesNotTriggerRedundantSave() throws {
        // Create valid PKDrawing data
        let drawing = PKDrawing()
        let canvasData = drawing.dataRepresentation()
        let (store, noteId) = makeStore(canvasData: canvasData)
        store.saveNowSync()

        let originalUpdatedAt = store.appData.notes.first(where: { $0.id == noteId })?.updatedAt

        // Simulate opening the note
        let vc = NoteEditorViewController(dataStore: store, noteId: noteId)
        _ = vc.view

        // Opening the note should not have changed updatedAt for unchanged content
        let updatedAt = store.appData.notes.first(where: { $0.id == noteId })?.updatedAt
        XCTAssertEqual(originalUpdatedAt, updatedAt,
            "Opening a note mutated updatedAt — canvasViewDrawingDidChange fired during load, triggering an unnecessary save")
    }

    /// Checks that saveNowSync() (called in viewWillDisappear) does not block
    /// the main thread excessively when canvas data is large.
    func testSaveNowSyncDoesNotBlockMainThreadLong() throws {
        let largeCanvasData = Data(repeating: 0xAB, count: 5_000_000)
        let (store, noteId) = makeStore(canvasData: largeCanvasData)

        // Pre-schedule a pending save (simulating what happens after drawing)
        store.updateNoteCanvas(id: noteId, canvasData: largeCanvasData)

        let start = CFAbsoluteTimeGetCurrent()
        store.saveNowSync()
        let duration = CFAbsoluteTimeGetCurrent() - start

        XCTAssertLessThan(duration, 1.5,
            "saveNowSync() blocked the main thread for \(duration)s with large canvas data")
    }
}
