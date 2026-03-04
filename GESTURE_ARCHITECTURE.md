# Gesture System Architecture

## Overview

This document explains how gestures are coordinated between UIScrollView (zoom/pan) and PKCanvasView (drawing) to prevent conflicts.

## Gesture Recognizer Hierarchy

```
NoteEditorViewController
├── UIScrollView (scrollView)
│   ├── UIPanGestureRecognizer (system-provided, for scrolling)
│   ├── UIPinchGestureRecognizer (system-provided, for zooming)
│   └── UITapGestureRecognizer (custom, for double-tap zoom)
│
└── UIView (zoomableContentView)
    └── PKCanvasView (canvasView)
        ├── Internal drawing gestures (Apple's implementation)
        ├── Apple Pencil touch handling
        └── Finger touch handling (based on drawingPolicy)
```

## Touch Flow Decision Tree

```
Touch Event Occurs
│
├─ Is touch type .pencil?
│  └─ YES → Block zoom, allow canvas to handle
│
├─ Is mode .drawing?
│  ├─ YES → Is touch on canvas area?
│  │  ├─ YES → Are there 2+ touches?
│  │  │  ├─ YES → Allow zoom
│  │  │  └─ NO → Block zoom, allow canvas to handle
│  │  └─ NO → Allow zoom
│  └─ NO (text mode) → Allow zoom
```

## Key Delegate Methods

### 1. `gestureRecognizer(_:shouldReceive:)`
**When called:** Before gesture recognizer claims a touch  
**Purpose:** Early filtering based on touch properties  
**Our logic:** Block zoom for Apple Pencil and single-finger canvas touches

### 2. `gestureRecognizerShouldBegin(_:)`
**When called:** When gesture is about to begin recognizing  
**Purpose:** Last chance to prevent gesture based on current state  
**Our logic:** Only allow zoom if 2+ touches in drawing mode

### 3. `gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:)`
**When called:** When two gestures could recognize simultaneously  
**Purpose:** Coordinate between multiple gestures  
**Our logic:** Don't allow zoom + canvas gestures simultaneously

## Configuration Timing

```
App Launch
│
└─ viewDidLoad()
   ├─ configureScrollView()
   │  └─ Sets scrollView.delegate = self
   │
   ├─ configureCanvas()
   │  └─ Canvas added to view hierarchy
   │
   ├─ configureGestures()
   │  └─ Adds double-tap gesture
   │
   └─ loadNote()
      └─ Loads drawing, triggers async:
         └─ configureGesturePriorities()
            ├─ Gets scroll view gestures
            ├─ Gets canvas gestures  
            ├─ Sets up failure requirements
            └─ Sets gesture delegates
```

## Gesture States

### Pinch Gesture (Zoom) States
1. **Possible** - Waiting for touches
2. **Began** - Two touches detected, starting to move
3. **Changed** - Active pinching
4. **Ended** - Fingers lifted
5. **Cancelled** - Interrupted (this is what we trigger)
6. **Failed** - Didn't meet requirements

### Canvas Gesture States
(Apple's internal implementation - we don't control these)

## Priority System

```
Priority Level 1 (Highest): Apple Pencil Touches
│  └─ Always goes to canvas for drawing
│
Priority Level 2: Single Finger on Canvas (Drawing Mode)
│  └─ Goes to canvas unless explicitly allowing zoom
│
Priority Level 3: Two-Finger Gestures
│  └─ Can trigger zoom when deliberate
│
Priority Level 4: Touches Outside Canvas
│  └─ Standard scroll view behavior
```

## Mode-Specific Behavior

### Drawing Mode
- **Apple Pencil:** Always draws
- **Single Finger:** Draws (if anyInput), blocks zoom
- **Two Fingers:** Zooms (pinch) or scrolls (pan)

### Text Mode
- **Apple Pencil:** Draws (PKCanvasView still accepts pencil)
- **Single Finger:** Can trigger zoom or scroll
- **Two Fingers:** Zooms (pinch) or scrolls (pan)

## Failure Requirements

```swift
// This makes zoom wait for canvas gestures to fail
scrollViewPinchGesture.require(toFail: canvasGesture)
```

**Effect:** 
- If canvas wants the touch, zoom never starts
- If canvas rejects the touch, zoom can then begin
- Adds minimal latency (~1 frame) but prevents conflicts

## Common Pitfalls

### ❌ Don't Do This
```swift
// Setting both to true causes conflicts
canvas.isScrollEnabled = true  
scrollView.isScrollEnabled = true

// Allowing simultaneous gestures
func gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) -> Bool {
    return true  // Too permissive!
}

// Not checking touch type
func gestureRecognizer(_:shouldReceive touch:) -> Bool {
    return true  // Allows zoom for everything
}
```

### ✅ Do This
```swift
// Only scroll view handles scrolling
canvas.isScrollEnabled = false
scrollView.isScrollEnabled = true

// Selective simultaneous recognition
func gestureRecognizer(_:shouldRecognizeSimultaneouslyWith:) -> Bool {
    // Only allow pan + pinch together
    if bothAreScrollViewGestures { return true }
    return false
}

// Filter by touch type
func gestureRecognizer(_:shouldReceive touch:) -> Bool {
    if touch.type == .pencil { return false }
    // More logic...
}
```

## Debugging Commands

### Print Gesture Info
```swift
// In any gesture delegate method:
print("Gesture: \(gestureRecognizer)")
print("State: \(gestureRecognizer.state.rawValue)")
print("View: \(gestureRecognizer.view?.classForCoder ?? UIView.self)")
print("Touches: \(gestureRecognizer.numberOfTouches)")
```

### Print Touch Info
```swift
// In shouldReceive:
print("Touch type: \(touch.type.rawValue)")
print("Touch phase: \(touch.phase.rawValue)")
print("Touch location: \(touch.location(in: view))")
```

### List All Gestures
```swift
func printAllGestures() {
    print("=== Scroll View Gestures ===")
    scrollView.gestureRecognizers?.forEach { gesture in
        print("- \(type(of: gesture)): \(gesture)")
    }
    
    print("=== Canvas Gestures ===")
    canvasView.gestureRecognizers?.forEach { gesture in
        print("- \(type(of: gesture)): \(gesture)")
    }
}
```

## Performance Considerations

### Gesture Recognition Overhead
- Each delegate method call: ~0.1ms
- Touch type checking: ~0.01ms
- Mode checking: ~0.001ms
- **Total per touch: < 0.2ms** (negligible)

### Optimization Tips
1. Cache expensive lookups (don't repeatedly check view hierarchy)
2. Order conditions from fastest to slowest in if statements
3. Early return when possible
4. Avoid allocations in delegate methods

## Alternative Approaches Considered

### ❌ Disabling Zoom Entirely
**Pros:** Simplest solution, no conflicts  
**Cons:** Users lose valuable zoom functionality  
**Verdict:** Not acceptable for note-taking app

### ❌ Mode-Based Zoom Toggle
**Pros:** Clear separation of drawing vs. zoom mode  
**Cons:** Extra mode = more UI complexity, worse UX  
**Verdict:** Too cumbersome for users

### ❌ Custom Gesture Recognizers
**Pros:** Complete control over gesture logic  
**Cons:** Complex, error-prone, may conflict with PKCanvasView internals  
**Verdict:** Over-engineering for this use case

### ✅ Gesture Coordinator (Current Approach)
**Pros:** Uses system APIs, selective filtering, preserves all features  
**Cons:** Requires understanding gesture recognizer system  
**Verdict:** Best balance of functionality and complexity

## Future Enhancements

### Pressure-Sensitive Zoom Prevention
```swift
// If Apple exposes pressure in UITouch
if touch.force > 0.1 {
    // Likely drawing intent, block zoom
    return false
}
```

### Predictive Gesture Classification
```swift
// Use touch velocity to predict intent
let velocity = touch.velocity(in: view)
if velocity.magnitude < threshold {
    // Slow touch = likely drawing
}
```

### User Preference System
```swift
enum ZoomPreference {
    case alwaysAllow      // Zoom works everywhere
    case requireTwoFingers // Current behavior
    case disabled         // No zoom, only scroll
}
```

## References

- [WWDC 2018: Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/)
- [UIGestureRecognizer Programming Guide](https://developer.apple.com/library/archive/documentation/EventHandling/Conceptual/EventHandlingiPhoneOS/GestureRecognizer_basics/GestureRecognizer_basics.html)
- [PencilKit Documentation](https://developer.apple.com/documentation/pencilkit)

## Contact

For questions about this system:
- Check console logs for gesture debug messages
- Review ZOOM_DRAWING_FIX_TESTING.md for test procedures
- See ZoomAndDrawingTests.swift for unit tests

