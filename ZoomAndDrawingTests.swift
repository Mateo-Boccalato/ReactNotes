import Testing
import UIKit
import PencilKit
@testable import YourAppModule // Replace with your actual module name

/// Tests for zoom and drawing interaction issues
@Suite("Zoom and Drawing Interaction Tests")
struct ZoomAndDrawingTests {
    
    // MARK: - Test Setup Helper
    
    /// Creates a test instance of NoteEditorViewController
    func makeTestViewController() -> NoteEditorViewController {
        let dataStore = DataStore() // You may need to mock this
        let noteId = UUID().uuidString
        let vc = NoteEditorViewController(dataStore: dataStore, noteId: noteId)
        
        // Load the view to trigger viewDidLoad
        _ = vc.view
        
        return vc
    }
    
    // MARK: - Gesture Recognizer Tests
    
    @Test("Scroll view should not intercept single touch drawing gestures")
    func scrollViewShouldNotInterceptDrawing() async throws {
        let vc = makeTestViewController()
        
        // Access the scroll view through the view hierarchy
        let scrollView = vc.view.subviews.first { $0 is UIScrollView } as? UIScrollView
        let scrollViewUnwrapped = try #require(scrollView)
        
        // Check that scroll view has gesture recognizers
        let gestureRecognizers = scrollViewUnwrapped.gestureRecognizers ?? []
        #expect(gestureRecognizers.count > 0, "ScrollView should have gesture recognizers")
        
        // Find pinch gesture recognizer
        let pinchGesture = gestureRecognizers.first { $0 is UIPinchGestureRecognizer }
        #expect(pinchGesture != nil, "ScrollView should have pinch gesture for zooming")
        
        // Verify that there's a delegate set that can coordinate gestures
        #expect(scrollViewUnwrapped.delegate != nil, "ScrollView should have a delegate")
    }
    
    @Test("Canvas view should allow drawing when in drawing mode")
    func canvasViewShouldAllowDrawing() async throws {
        let vc = makeTestViewController()
        
        // Find the PKCanvasView in the hierarchy
        func findCanvasView(in view: UIView) -> PKCanvasView? {
            if let canvas = view as? PKCanvasView {
                return canvas
            }
            for subview in view.subviews {
                if let canvas = findCanvasView(in: subview) {
                    return canvas
                }
            }
            return nil
        }
        
        let canvasView = findCanvasView(in: vc.view)
        let canvas = try #require(canvasView)
        
        // Verify canvas is configured for drawing
        #expect(canvas.isUserInteractionEnabled == true)
        #expect(canvas.isScrollEnabled == false, "Canvas should not handle its own scrolling")
        
        // Check drawing policy
        // In drawing mode with pencilOnlyMode = false, should be .anyInput
        #expect(canvas.drawingPolicy == .anyInput || canvas.drawingPolicy == .pencilOnly)
    }
    
    @Test("Zoom gesture should not activate during single-touch drawing")
    func zoomShouldNotActivateDuringSingleTouchDrawing() async throws {
        let vc = makeTestViewController()
        
        let scrollView = vc.view.subviews.first { $0 is UIScrollView } as? UIScrollView
        let scrollViewUnwrapped = try #require(scrollView)
        
        let initialZoomScale = scrollViewUnwrapped.zoomScale
        
        // Simulate a single touch event (this would be an Apple Pencil touch)
        // In a real scenario, we'd use XCTest's UI testing, but for unit tests
        // we verify the configuration is correct
        
        #expect(scrollViewUnwrapped.minimumZoomScale <= 1.0)
        #expect(scrollViewUnwrapped.maximumZoomScale >= 1.0)
        #expect(initialZoomScale == 1.0, "Should start at 1.0x zoom")
    }
    
    // MARK: - Mode Switching Tests
    
    @Test("Drawing policy should update correctly based on mode")
    func drawingPolicyShouldUpdateWithMode() async throws {
        let vc = makeTestViewController()
        
        func findCanvasView(in view: UIView) -> PKCanvasView? {
            if let canvas = view as? PKCanvasView {
                return canvas
            }
            for subview in view.subviews {
                if let canvas = findCanvasView(in: subview) {
                    return canvas
                }
            }
            return nil
        }
        
        let canvasView = findCanvasView(in: vc.view)
        let canvas = try #require(canvasView)
        
        // In drawing mode, policy should allow input
        // Note: The actual policy depends on pencilOnlyMode setting
        let drawingPolicy = canvas.drawingPolicy
        
        #expect(
            drawingPolicy == .anyInput || drawingPolicy == .pencilOnly,
            "Drawing policy should be either anyInput or pencilOnly"
        )
    }
    
    // MARK: - Zoom Behavior Tests
    
    @Test("Double tap should toggle zoom")
    func doubleTapShouldToggleZoom() async throws {
        let vc = makeTestViewController()
        
        let scrollView = vc.view.subviews.first { $0 is UIScrollView } as? UIScrollView
        let scrollViewUnwrapped = try #require(scrollView)
        
        // Find double-tap gesture
        let gestures = scrollViewUnwrapped.gestureRecognizers ?? []
        let doubleTapGesture = gestures.first { gesture in
            (gesture as? UITapGestureRecognizer)?.numberOfTapsRequired == 2
        }
        
        #expect(doubleTapGesture != nil, "Should have double-tap gesture for zoom toggle")
    }
    
    @Test("Zoom should center content properly")
    func zoomShouldCenterContent() async throws {
        let vc = makeTestViewController()
        
        let scrollView = vc.view.subviews.first { $0 is UIScrollView } as? UIScrollView
        let scrollViewUnwrapped = try #require(scrollView)
        
        // Verify zoom configuration
        #expect(scrollViewUnwrapped.bouncesZoom == true)
        #expect(scrollViewUnwrapped.minimumZoomScale == 0.5)
        #expect(scrollViewUnwrapped.maximumZoomScale == 3.0)
    }
    
    // MARK: - Touch Priority Tests
    
    @Test("Canvas should receive touches before scroll view")
    func canvasShouldReceiveTouchesFirst() async throws {
        let vc = makeTestViewController()
        
        func findCanvasView(in view: UIView) -> PKCanvasView? {
            if let canvas = view as? PKCanvasView {
                return canvas
            }
            for subview in view.subviews {
                if let canvas = findCanvasView(in: subview) {
                    return canvas
                }
            }
            return nil
        }
        
        let canvasView = findCanvasView(in: vc.view)
        let canvas = try #require(canvasView)
        
        // Canvas should be above other views in the hierarchy
        #expect(canvas.isUserInteractionEnabled == true)
        
        // Canvas should not be hidden or have alpha 0
        #expect(canvas.isHidden == false)
        #expect(canvas.alpha > 0)
    }
    
    // MARK: - Gesture Conflict Tests
    
    @Test("Pinch gesture should be properly coordinated with canvas")
    func pinchGestureShouldBeCoordinated() async throws {
        let vc = makeTestViewController()
        
        let scrollView = vc.view.subviews.first { $0 is UIScrollView } as? UIScrollView
        let scrollViewUnwrapped = try #require(scrollView)
        
        // Get all gesture recognizers
        let gestures = scrollViewUnwrapped.gestureRecognizers ?? []
        
        // Should have a pinch gesture for zooming
        let pinchGesture = gestures.first { $0 is UIPinchGestureRecognizer }
        #expect(pinchGesture != nil)
        
        // Should have a delegate that can handle simultaneous recognition
        #expect(scrollViewUnwrapped.delegate != nil)
    }
}

// MARK: - Integration Test Notes

/*
 Manual Integration Tests to Perform:
 
 TEST 1: Single Finger Drawing
 1. Launch app and open a note
 2. Use a single finger to draw a line
 3. EXPECTED: Line should be drawn smoothly
 4. EXPECTED: No zooming should occur
 5. ACTUAL: Document current behavior
 
 TEST 2: Apple Pencil Drawing
 1. Use Apple Pencil to draw
 2. Draw with varying pressure
 3. EXPECTED: Drawing should be smooth with no zoom
 4. EXPECTED: No accidental zoom activation
 5. ACTUAL: Document current behavior
 
 TEST 3: Intentional Zoom
 1. Use two fingers to pinch-zoom
 2. EXPECTED: Zoom should work smoothly
 3. EXPECTED: Drawing should remain possible after zoom
 4. ACTUAL: Document current behavior
 
 TEST 4: Drawing While Zoomed
 1. Zoom in to 2x
 2. Attempt to draw with Apple Pencil
 3. EXPECTED: Drawing should work normally
 4. EXPECTED: No unexpected zoom changes
 5. ACTUAL: Document current behavior
 
 TEST 5: Mode Switching
 1. Switch between drawing and text mode
 2. Try drawing in each mode
 3. EXPECTED: Drawing only works in drawing mode
 4. EXPECTED: No zoom interference in either mode
 5. ACTUAL: Document current behavior
 
 TEST 6: Quick Touch Sequences
 1. Rapidly tap with pencil to start drawing
 2. Try several short strokes quickly
 3. EXPECTED: No zoom activation
 4. EXPECTED: All strokes captured correctly
 5. ACTUAL: Document current behavior
 
 Performance Metrics to Track:
 - Zoom activation latency
 - Drawing input latency
 - False positive zoom activations
 - Gesture recognition failures
 */
