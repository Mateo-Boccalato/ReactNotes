# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

ReactNotes is an **iPad-only UIKit app** written in Swift (not a React/JS project). It is a Notes application supporting folders, notebooks, notes, and PencilKit drawing. Deployment target: iPad, iOS 17+. No external dependencies — pure Swift + UIKit + PencilKit.

## Build & Test

This is an Xcode project with no build scripts. All commands go through `xcodebuild` or the Xcode IDE.

```bash
# Build (simulator)
xcodebuild -project ReactNotes.xcodeproj -scheme ReactNotes -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (M4)' build

# Run all tests
xcodebuild test -project ReactNotes.xcodeproj -scheme ReactNotesTests -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (M4)'

# Run a single test method
xcodebuild test -project ReactNotes.xcodeproj -scheme ReactNotesTests -destination 'platform=iOS Simulator,name=iPad Pro (11-inch) (M4)' -only-testing:ReactNotesTests/DataStoreTests/testCreateAndDeleteNote
```

## Architecture

### Data Flow

App launch → `SceneDelegate` creates `LibraryViewController(dataStore: DataStore.shared)` → DataStore loads `Documents/app_data.json` (or seeds defaults) → user mutations call `scheduleSaveAndNotify()` → 2-second debounce triggers disk write + posts `Notification.Name.appDataDidChange` → view controllers reload.

### Key Layers

**Models** (`Models.swift`): Four `Codable`/`Equatable` structs: `Folder`, `Notebook`, `Note`, `AppData` (root container with `schemaVersion`). `AppDataFactory` seeds one default folder/notebook/note on first launch.

**DataStore** (`DataStore.swift`): Singleton (`DataStore.shared`). All mutations go through its CRUD methods, which call `scheduleSaveAndNotify()`. Saves are debounced (2s delay), written atomically (temp file → atomic move to `app_data.json`), and run on a private serial queue (`com.mateobocc.reactnotes.datastore`, `.utility` QoS). Use `saveNowSync()` in tests to bypass the debounce.

**ViewControllers**: `LibraryViewController` (root; folders + notebooks split layout) → `NotesListViewController` → `NoteEditorViewController` → `CanvasViewController` (PencilKit). Each VC observes `appDataDidChange` and calls `reloadData()`.

### Known Stubs / Incomplete Features

- **Canvas is not persisted**: `CanvasViewController` uses PencilKit but has no DataStore integration — drawings are not saved.
- The "Clear" button in CanvasViewController is wired up but does not interact with DataStore.
