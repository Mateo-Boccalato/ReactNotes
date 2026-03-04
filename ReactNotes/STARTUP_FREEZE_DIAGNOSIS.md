# Startup Freeze Diagnosis

## Identified Issues

Based on analysis of your codebase, here are the likely causes of the startup freeze:

### 1. **DataStore Loading on Main Thread (MOST LIKELY CAUSE)**

**Problem**: In `SceneDelegate.swift`, `DataStore.shared` is accessed on the main thread during scene setup. The DataStore initializer:
- Loads JSON from disk synchronously
- Decodes potentially large AppData (with canvas drawings)
- May perform schema migrations

**Location**: `SceneDelegate.swift:12`
```swift
let dataStore = DataStore.shared  // ⚠️ This blocks the main thread!
```

**Impact**: If you have many notes or large canvas drawings, this can take 1-5+ seconds, causing the UI to freeze.

**Fix**: See proposed solution below.

---

### 2. **Thumbnail Generation Cascade**

**Problem**: In `NoteGridViewController.swift:141-152`, when the grid view loads, it immediately starts generating thumbnails for ALL visible notes asynchronously. If you have many notes with complex drawings:
- Each thumbnail generation decodes PKDrawing data
- Renders the drawing to an image
- Even though it's async, the sheer volume can overwhelm the system

**Impact**: Can cause stuttering and unresponsiveness during initial load.

**Fix**: Implement thumbnail generation throttling and caching.

---

### 3. **JSON Encoding/Decoding Performance**

**Problem**: The `DataStore` uses `JSONEncoder` with pretty printing and sorted keys:
```swift
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
```

These options significantly slow down encoding, and canvas data (PKDrawing serialized as Data) can be large.

**Impact**: Every save operation (which happens frequently) takes longer than necessary.

---

### 4. **SidebarViewController Data Processing**

**Problem**: In `SidebarViewController.swift:127-144`, the `rebuildRows()` method processes all folders and notebooks every time data changes. With many items, this can be expensive.

**Impact**: Minor but contributes to overall sluggishness.

---

## Recommended Fixes

### Priority 1: Async DataStore Loading

Modify `DataStore.swift` to load asynchronously:

```swift
final class DataStore {
    static let shared = DataStore()
    
    private(set) var appData: AppData
    private var isLoaded = false
    private let loadQueue = DispatchQueue(label: "com.mateobocc.reactnotes.load", qos: .userInitiated)
    
    // ... existing properties ...
    
    init(fileURL: URL? = nil) {
        // ... existing setup ...
        
        // Start with empty data
        appData = AppDataFactory.makeDefault()
        
        // Load asynchronously
        loadAsync()
    }
    
    private func loadAsync() {
        loadQueue.async { [weak self] in
            guard let self else { return }
            
            guard let data = try? Data(contentsOf: self.dataFileURL) else {
                return
            }
            
            do {
                var decoded = try self.decoder.decode(AppData.self, from: data)
                if decoded.schemaVersion < AppDataFactory.schemaVersion {
                    decoded = AppDataFactory.migrate(decoded)
                }
                
                // Update on main thread
                DispatchQueue.main.async {
                    self.appData = decoded
                    self.isLoaded = true
                    NotificationCenter.default.post(name: .appDataDidChange, object: nil)
                }
            } catch {
                // Handle error
            }
        }
    }
}
```

### Priority 2: Optimize JSON Encoding

Remove unnecessary formatting options in `DataStore.swift:16-17`:

```swift
encoder = JSONEncoder()
// Remove: encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
// These are for debugging only and significantly slow down encoding
```

### Priority 3: Throttle Thumbnail Generation

Modify `NoteGridViewController.swift` to limit concurrent thumbnail generation:

```swift
private var thumbnailTasks: [IndexPath: Task<Void, Never>] = [:]
private let thumbnailSemaphore = DispatchSemaphore(value: 4) // Max 4 concurrent

private func configureDataSource() {
    dataSource = UICollectionViewDiffableDataSource<Int, String>(collectionView: collectionView) { [weak self] cv, indexPath, noteId in
        guard let self,
              let note = self.filteredNotes.first(where: { $0.id == noteId }) else {
            return cv.dequeueReusableCell(withReuseIdentifier: NoteCardCell.reuseId, for: indexPath)
        }
        let cell = cv.dequeueReusableCell(withReuseIdentifier: NoteCardCell.reuseId, for: indexPath) as! NoteCardCell
        cell.configure(note: note, thumbnail: nil)
        
        // Cancel any existing task for this cell
        thumbnailTasks[indexPath]?.cancel()
        
        // Create new task with throttling
        let task = Task {
            thumbnailSemaphore.wait()
            defer { thumbnailSemaphore.signal() }
            
            guard !Task.isCancelled else { return }
            
            let img = await ThumbnailCache.shared.thumbnail(for: note, size: CGSize(width: 300, height: 160))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run {
                if let current = cv.cellForItem(at: indexPath) as? NoteCardCell {
                    current.setThumbnail(img)
                }
            }
        }
        
        thumbnailTasks[indexPath] = task
        
        return cell
    }
}

// Don't forget to cancel tasks when cells are no longer visible
func collectionView(_ collectionView: UICollectionView, didEndDisplaying cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
    thumbnailTasks[indexPath]?.cancel()
    thumbnailTasks[indexPath] = nil
}
```

### Priority 4: Add Loading Indicator

Show the user that the app is loading:

```swift
// In SceneDelegate.swift
func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene else { return }
    
    // Show loading state immediately
    let loadingVC = UIViewController()
    loadingVC.view.backgroundColor = .systemBackground
    let spinner = UIActivityIndicatorView(style: .large)
    spinner.translatesAutoresizingMaskIntoConstraints = false
    spinner.startAnimating()
    loadingVC.view.addSubview(spinner)
    NSLayoutConstraint.activate([
        spinner.centerXAnchor.constraint(equalTo: loadingVC.view.centerXAnchor),
        spinner.centerYAnchor.constraint(equalTo: loadingVC.view.centerYAnchor)
    ])
    
    let window = UIWindow(windowScene: windowScene)
    window.rootViewController = loadingVC
    window.makeKeyAndVisible()
    self.window = window
    
    // Wait for data to load, then show main UI
    let dataStore = DataStore.shared
    
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        let splitVC = UISplitViewController(style: .doubleColumn)
        splitVC.preferredDisplayMode = .oneBesideSecondary
        splitVC.preferredSplitBehavior = .tile
        splitVC.presentsWithGesture = false
        splitVC.primaryBackgroundStyle = .sidebar
        splitVC.minimumPrimaryColumnWidth = 260
        splitVC.maximumPrimaryColumnWidth = 320
        
        let sidebarVC = SidebarViewController(dataStore: dataStore)
        let gridVC = NoteGridViewController(dataStore: dataStore, filter: .all)
        let gridNav = UINavigationController(rootViewController: gridVC)
        
        sidebarVC.delegate = gridVC
        
        splitVC.setViewController(sidebarVC, for: .primary)
        splitVC.setViewController(gridNav, for: .secondary)
        
        window.rootViewController = splitVC
    }
}
```

## Testing the Fixes

Run the diagnostic tests I created:
1. Open the `StartupDiagnosticTests.swift` file
2. Run the tests in Xcode
3. Look for any tests that fail or show high durations
4. Focus on fixing the slowest operations first

## Additional Recommendations

1. **Profile with Instruments**: Use Time Profiler to see exactly where time is being spent
2. **Add Logging**: Add timing logs to identify bottlenecks:
   ```swift
   let start = CFAbsoluteTimeGetCurrent()
   // ... code ...
   print("⏱️ Operation took: \(CFAbsoluteTimeGetCurrent() - start)s")
   ```
3. **Consider Core Data**: If you have many notes (100+), consider migrating from JSON to Core Data for better performance
4. **Lazy Loading**: Don't load all notes at startup - load them as needed

## Quick Win

The fastest fix with the least code changes is to remove the JSON formatting options:

In `DataStore.swift`, change:
```swift
encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
```

To:
```swift
// No formatting for performance
```

This alone could improve save/load times by 50-80%.
