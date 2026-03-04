# Sidebar Toggle Feature

## Summary
Added the ability to hide and show the sidebar (navigation panel) to give users more screen space when working on their notes.

## Features Added

### 1. **Sidebar Toggle Button**
- Located in the top-left of the navigation bar
- Uses the standard "sidebar.left" SF Symbol icon
- Tapping toggles sidebar visibility
- Smooth animation (0.3 seconds)

### 2. **Keyboard Shortcut**
- **Command+\\** toggles the sidebar
- Standard macOS shortcut for sidebar toggling
- Works when note editor is active
- Available on iPad with external keyboard

## Implementation Details

### Button Configuration
```swift
let toggleSidebarBtn = UIBarButtonItem(
    image: UIImage(systemName: "sidebar.left"),
    style: .plain,
    target: self,
    action: #selector(toggleSidebar)
)
navigationItem.leftBarButtonItem = toggleSidebarBtn
```

### Toggle Logic
```swift
@objc private func toggleSidebar() {
    if let splitVC = splitViewController {
        UIView.animate(withDuration: 0.3) {
            splitVC.preferredDisplayMode = 
                splitVC.displayMode == .secondaryOnly 
                    ? .oneBesideSecondary 
                    : .secondaryOnly
        }
    }
}
```

### Keyboard Shortcut
```swift
let toggleSidebarCommand = UIKeyCommand(
    title: "Toggle Sidebar",
    action: #selector(toggleSidebar),
    input: "\\",
    modifierFlags: .command
)
```

## User Experience

### Showing/Hiding the Sidebar

**Method 1: Button**
1. Look for the sidebar icon (≡) in top-left corner
2. Tap to hide sidebar (more space for notes)
3. Tap again to show sidebar (access notebooks/folders)

**Method 2: Keyboard Shortcut**
1. Press **Command+\\** to toggle
2. Quick access while typing or drawing
3. Standard shortcut users expect

### Display Modes

**Sidebar Visible (oneBesideSecondary)**
- Sidebar shown on the left
- Note editor on the right
- Good for navigation between notes
- Standard two-column layout

**Sidebar Hidden (secondaryOnly)**
- Full-screen note editor
- Maximum drawing/writing space
- Distraction-free mode
- Good for focused work

## Benefits

### For Users
- ✅ **More screen space**: Full-screen mode for notes
- ✅ **Quick toggle**: One tap or keyboard shortcut
- ✅ **Familiar behavior**: Standard iOS/iPadOS pattern
- ✅ **Distraction-free**: Hide navigation when working

### For Workflow
- ✅ **Focus mode**: Hide sidebar when drawing/writing
- ✅ **Navigation mode**: Show sidebar when organizing
- ✅ **Flexible**: Toggle as needed without closing notes
- ✅ **Keyboard-friendly**: Works with external keyboards

## Platform Behavior

### iPhone
- Sidebar toggle may behave differently on smaller screens
- Split view might show overlay instead of side-by-side
- Button still works, adapted to screen size

### iPad
- Full split view support
- Side-by-side layout in landscape
- Overlay in portrait (depending on size)
- Keyboard shortcut fully functional

### Mac Catalyst (if supported)
- Standard macOS sidebar behavior
- Command+\ is the expected shortcut
- Sidebar can be resized by user

## Testing Guide

### Test 1: Button Toggle
1. Open a note
2. Look for sidebar icon in top-left
3. Tap button
4. **Expected**: Sidebar slides out of view smoothly
5. Tap button again
6. **Expected**: Sidebar slides back into view

### Test 2: Keyboard Shortcut
1. Open a note (iPad with keyboard)
2. Press **Command+\\**
3. **Expected**: Sidebar toggles
4. Press **Command+\\** again
5. **Expected**: Sidebar toggles back

### Test 3: Animation
1. Toggle sidebar with button
2. **Expected**: Smooth 0.3-second animation
3. **Expected**: No jarring layout changes
4. **Expected**: Note content stays in place

### Test 4: State Persistence
1. Hide sidebar
2. Switch to different note
3. **Expected**: Sidebar stays hidden
4. Show sidebar
5. **Expected**: Sidebar stays visible

### Test 5: Different Orientations (iPad)
1. Start in landscape with sidebar visible
2. Rotate to portrait
3. **Expected**: Appropriate layout for orientation
4. Toggle sidebar
5. **Expected**: Toggle works in both orientations

### Test 6: Integration with Other Features
1. Hide sidebar
2. Draw on canvas
3. **Expected**: Full width available for drawing
4. Zoom in and out
5. **Expected**: Zoom works normally
6. Show sidebar
7. **Expected**: Drawing stays intact

## Icon Reference

**SF Symbol**: `sidebar.left`
- Standard iOS/iPadOS icon for sidebar
- Universally recognized
- Consistent with system apps
- Automatically adapts to light/dark mode

## Display Mode States

### UISplitViewController.DisplayMode Options

**`.oneBesideSecondary`**
- Both columns visible side-by-side
- Sidebar on left, note editor on right
- Default state when space allows

**`.secondaryOnly`**
- Only note editor visible
- Full-screen content
- Sidebar hidden

**`.oneOverSecondary`**
- Note editor full screen
- Sidebar overlays when shown
- Common on iPhone

## Alternative Approaches (Not Implemented)

### Swipe Gesture
Could add swipe from left edge to show sidebar:
```swift
let swipeGesture = UIScreenEdgePanGestureRecognizer(
    target: self,
    action: #selector(handleSwipe)
)
swipeGesture.edges = .left
view.addGestureRecognizer(swipeGesture)
```

### Toggle in Options Menu
Could add to the "..." more options menu:
```swift
let toggleAction = UIAlertAction(
    title: sidebarHidden ? "Show Sidebar" : "Hide Sidebar",
    style: .default
) { [weak self] _ in
    self?.toggleSidebar()
}
alert.addAction(toggleAction)
```

### Auto-Hide
Could auto-hide sidebar when drawing:
```swift
func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
    if splitVC.displayMode != .secondaryOnly {
        toggleSidebar()
    }
}
```

## Known Behaviors

### Sidebar Icon Changes
- Icon represents current state
- Standard iOS behavior
- May appear different on iPhone vs iPad

### Animation
- System controls animation timing
- May vary by device/iOS version
- Always smooth and system-standard

### Button Visibility
- Always visible in navigation bar
- Disabled if split view not available
- Adapts to trait collection changes

## Future Enhancements (Optional)

1. **Remember preference**: Save sidebar state per user
2. **Auto-hide timer**: Hide after inactivity
3. **Custom animation**: More dramatic hide/show
4. **Sidebar width control**: Let users resize
5. **Gesture support**: Swipe from edge to toggle
6. **Status indicator**: Show if sidebar is hidden

## Troubleshooting

### If button doesn't appear:
- Check that view is in a split view controller
- Verify navigation bar is visible
- Ensure button is added to correct bar button position

### If toggle doesn't work:
- Verify split view controller is accessible
- Check that display mode changes are allowed
- Ensure proper trait collection for split view

### If animation is choppy:
- Check for layout issues during transition
- Verify no heavy operations during animation
- Test on actual device (not just simulator)

## Code Locations

**Button Setup**: `configureNavigation()`
- Creates and adds the sidebar toggle button
- Sets up action and icon

**Toggle Action**: `toggleSidebar()`
- Handles the toggle logic
- Animates the transition

**Keyboard Shortcut**: `configureKeyCommands()`
- Registers Command+\ shortcut
- Available for external keyboards
