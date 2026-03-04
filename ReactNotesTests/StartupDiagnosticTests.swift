//
//  StartupDiagnosticTests.swift
//  ReactNotes
//
//  Created by Mateo Boccalato Rodriguez on 2/26/26.
//
import XCTest
import UIKit
@testable import ReactNotes

/// These tests diagnose potential startup freezing issues in the app
final class StartupDiagnosticTests: XCTestCase {
    
    // MARK: - DataStore Performance Tests
    
    func testDataStoreLoadPerformance() async throws {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Create a temporary file URL for testing
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_data.json")
        
        // Clean up any existing test file
        try? FileManager.default.removeItem(at: tempURL)
        
        // Create test data with many notes to simulate real-world scenario
        let testData = createLargeTestData()
        let jsonData = try JSONEncoder().encode(testData)
        try jsonData.write(to: tempURL)
        
        // Test loading
        let dataStore = DataStore(fileURL: tempURL)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        // Clean up
        try? FileManager.default.removeItem(at: tempURL)
        
        // DataStore should load in less than 1 second even with lots of data
        XCTAssertLessThan(duration, 1.0, "DataStore loading took \(duration) seconds, which may freeze the UI")
        XCTAssertEqual(dataStore.appData.notes.count, testData.notes.count)
    }
    
    func testLargeCanvasDataPerformance() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_canvas_data.json")
        try? FileManager.default.removeItem(at: tempURL)
        
        // Create test data with large canvas data (simulating complex drawings)
        let largeCanvasData = Data(repeating: 0, count: 5_000_000) // 5MB of canvas data
        
        let testData = AppData(
            schemaVersion: 2,
            folders: [createTestFolder()],
            notebooks: [createTestNotebook()],
            notes: [createTestNote(canvasData: largeCanvasData)]
        )
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let jsonData = try JSONEncoder().encode(testData)
        try jsonData.write(to: tempURL)
        
        let dataStore = DataStore(fileURL: tempURL)
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        try? FileManager.default.removeItem(at: tempURL)
        
        XCTAssertLessThan(duration, 2.0, "Loading large canvas data took \(duration) seconds")
        XCTAssertEqual(dataStore.appData.notes.first?.canvasData?.count, largeCanvasData.count)
    }
    
    // MARK: - Thumbnail Generation Tests
    
    func testThumbnailGenerationPerformance() async throws {
        // Create a note with canvas data
        let note = createTestNote(canvasData: nil)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Simulate what happens when the grid view loads
        let thumbnail = await ThumbnailCache.shared.thumbnail(for: note, size: CGSize(width: 300, height: 160))
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        // Should complete quickly since there's no canvas data
        XCTAssertLessThan(duration, 0.1, "Thumbnail generation took \(duration) seconds")
    }
    
    // MARK: - UI Component Tests
    
    func testGridViewControllerInitialization() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_grid.json")
        try? FileManager.default.removeItem(at: tempURL)
        
        let testData = createLargeTestData()
        let jsonData = try JSONEncoder().encode(testData)
        try jsonData.write(to: tempURL)
        
        let dataStore = DataStore(fileURL: tempURL)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Initialize the grid view controller
        let gridVC = NoteGridViewController(dataStore: dataStore, filter: .all)
        
        // Trigger viewDidLoad
        _ = gridVC.view
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        try? FileManager.default.removeItem(at: tempURL)
        
        XCTAssertLessThan(duration, 0.5, "Grid view initialization took \(duration) seconds")
    }
    
    func testSidebarViewControllerInitialization() async throws {
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("test_sidebar.json")
        try? FileManager.default.removeItem(at: tempURL)
        
        let testData = createLargeTestData()
        let jsonData = try JSONEncoder().encode(testData)
        try jsonData.write(to: tempURL)
        
        let dataStore = DataStore(fileURL: tempURL)
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        let sidebarVC = SidebarViewController(dataStore: dataStore)
        _ = sidebarVC.view
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        try? FileManager.default.removeItem(at: tempURL)
        
        XCTAssertLessThan(duration, 0.5, "Sidebar initialization took \(duration) seconds")
    }
    
    // MARK: - Main Thread Tests
    
    func testDataStoreSharedMainThreadSafety() async throws {
        // This test checks if DataStore.shared lazy initialization blocks the main thread
        let duration = await MainActor.run {
            let startTime = CFAbsoluteTimeGetCurrent()
            _ = DataStore.shared
            let endTime = CFAbsoluteTimeGetCurrent()
            return endTime - startTime
        }

        // First access should be very fast if it's not doing heavy I/O
        XCTAssertLessThan(duration, 0.1, "DataStore.shared first access took \(duration) seconds on main thread")
    }
    
    // MARK: - Helper Functions
    
    private func createTestFolder() -> Folder {
        Folder(
            id: UUID().uuidString,
            name: "Test Folder",
            parentFolderId: nil,
            order: 0,
            color: nil
        )
    }
    
    private func createTestNotebook() -> Notebook {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return Notebook(
            id: UUID().uuidString,
            title: "Test Notebook",
            folderId: createTestFolder().id,
            createdAt: timestamp,
            updatedAt: timestamp
        )
    }
    
    private func createTestNote(canvasData: Data? = nil) -> Note {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        return Note(
            id: UUID().uuidString,
            notebookId: UUID().uuidString,
            title: "Test Note",
            body: "Test body",
            createdAt: timestamp,
            updatedAt: timestamp,
            canvasData: canvasData
        )
    }
    
    private func createLargeTestData() -> AppData {
        let folder = createTestFolder()
        let notebook = createTestNotebook()
        
        // Create 100 notes to simulate a real-world scenario
        let notes = (0..<100).map { i in
            let timestamp = ISO8601DateFormatter().string(from: Date())
            return Note(
                id: UUID().uuidString,
                notebookId: notebook.id,
                title: "Test Note \(i)",
                body: "Test body \(i)",
                createdAt: timestamp,
                updatedAt: timestamp,
                canvasData: nil
            )
        }
        
        return AppData(
            schemaVersion: 2,
            folders: [folder],
            notebooks: [notebook],
            notes: notes
        )
    }
}

// MARK: - Concurrency Tests

final class MainThreadSafetyTests: XCTestCase {
    
    func testSceneSetupPerformance() async throws {
        // This simulates what happens in SceneDelegate
        let dataStore = DataStore.shared
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        await MainActor.run {
            let splitVC = UISplitViewController(style: .doubleColumn)
            splitVC.preferredDisplayMode = .oneBesideSecondary
            
            let sidebarVC = SidebarViewController(dataStore: dataStore)
            let gridVC = NoteGridViewController(dataStore: dataStore, filter: .all)
            let gridNav = UINavigationController(rootViewController: gridVC)
            
            splitVC.setViewController(sidebarVC, for: .primary)
            splitVC.setViewController(gridNav, for: .secondary)
        }
        
        let endTime = CFAbsoluteTimeGetCurrent()
        let duration = endTime - startTime
        
        XCTAssertLessThan(duration, 0.5, "Scene setup took \(duration) seconds on main thread")
    }
}

