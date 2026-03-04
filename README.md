# ReactNotes (iPad UIKit MVP)

ReactNotes is now an iPad-only UIKit application scaffold for Phase 1:
- folder + notebook shell
- note CRUD
- local JSON persistence
- PencilKit canvas stub

## Project Structure

- `ReactNotes.xcodeproj`: Xcode project
- `ReactNotes/`: App target source files
- `ReactNotesTests/`: Unit tests for persistence and CRUD

## Requirements

- Xcode 15 or newer (full Xcode app, not only command line tools)
- iPad simulator (iOS 17+ target)

## Run

1. Open `ReactNotes.xcodeproj` in Xcode.
2. Select `ReactNotes` scheme.
3. Choose an iPad simulator (for example, iPad Pro 11-inch).
4. Build and run (`Cmd+R`).

## Tests

1. Select `ReactNotesTests` in the test navigator or run all tests with `Cmd+U`.
2. Included tests cover:
   - JSON round-trip load/save
   - note create/delete mutations
   - write/read persistence sanity

## Persistence

- Data file: `app_data.json` in the app Documents directory.
- Writes are debounced (2 seconds) and use temp-file then atomic replace behavior.
