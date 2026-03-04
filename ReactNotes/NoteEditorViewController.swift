import UIKit
import PencilKit
import PhotosUI

// MARK: - EditorMode

enum EditorMode {
    case drawing
    case text
}

// MARK: - DrawingProtectionGestureRecognizer

/// A custom gesture recognizer that doesn't actually recognize gestures,
/// but uses its delegate methods to block touches from reaching other gestures
final class DrawingProtectionGestureRecognizer: UIGestureRecognizer {
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        // Always fail immediately - we're just here to filter via delegate
        state = .failed
    }
    
    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }
    
    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        state = .failed
    }
}

// MARK: - NoteEditorViewController

final class NoteEditorViewController: UIViewController {
    private let dataStore: DataStore
    private let noteId: String
    private var note: Note?

    // MARK: UI

    private let scrollView = UIScrollView()  // Container for zoom functionality
    private let zoomableContentView = UIView()  // Container that holds everything that should zoom
    private let patternBackground = PatternBackgroundView()
    private let canvasView = PKCanvasView()
    private let pageSeparatorContainer = UIView()  // Container for separators
    private let textView = UITextView()
    private let floatingToolbar = FloatingToolbarView()
    private let bottomToolbar = BottomPaperStyleToolbar()
    private let titleField = UITextField()

    // Layout
    private var floatingToolbarTrailingConstraint: NSLayoutConstraint!
    private var bottomToolbarBottomConstraint: NSLayoutConstraint!
    private var textViewHeightConstraint: NSLayoutConstraint!
    private var contentViewWidthConstraint: NSLayoutConstraint!
    private var contentViewHeightConstraint: NSLayoutConstraint!

    // State
    private var mode: EditorMode = .drawing
    private var numberOfPages: Int = 1
    private var pageSeparatorViews: [UIView] = []
    private var photoImageViews: [DraggableImageView] = []  // Track added photos
    private var isZooming: Bool = false  // Track if we're currently zooming

    // Debounce
    private var canvasSaveWorkItem: DispatchWorkItem?
    private let canvasSaveDelay: TimeInterval = 0.5
    private var textPersistWorkItem: DispatchWorkItem?
    private let textPersistDelay: TimeInterval = 0.5
    
    // Constants
    private let pageHeight: CGFloat = 1056  // Standard letter height at 96 DPI
    private let pageWidth: CGFloat = 816    // Standard letter width at 96 DPI
    
    // Settings
    private var pencilOnlyMode: Bool = false {
        didSet { 
            guard isViewLoaded else { return }
            updateDrawingPolicy() 
        }
    }

    // MARK: Init

    init(dataStore: DataStore, noteId: String) {
        self.dataStore = dataStore
        self.noteId = noteId
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { nil }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black  // Black background to show page boundaries clearly
        configureNavigation()
        configureScrollView()  // New: set up scroll view for zooming
        configureBackground()
        configureCanvas()
        configureTextView()
        configureFloatingToolbar()
        configureBottomToolbar()
        configureGestures()
        configureKeyCommands()
        loadNote()
        observeKeyboard()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        canvasView.becomeFirstResponder()
        
        print("🎨 View appeared - canvas is first responder: \(canvasView.isFirstResponder)")
    }
    
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        super.touchesBegan(touches, with: event)
        if let touch = touches.first {
            let location = touch.location(in: view)
            print("🖐️ Touch detected at: \(location)")
            print("   - Hit test result: \(view.hitTest(location, with: event)?.classForCoder ?? UIView.self)")
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        canvasSaveWorkItem?.cancel()
        canvasSaveWorkItem = nil
        textPersistWorkItem?.cancel()
        textPersistWorkItem = nil
        persistText()
        dataStore.saveNow()
        Task { await ThumbnailCache.shared.invalidate(noteId: noteId) }
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Configuration

    private func configureNavigation() {
        navigationController?.navigationBar.tintColor = .systemBlue
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        navigationController?.navigationBar.standardAppearance = appearance
        navigationController?.navigationBar.scrollEdgeAppearance = appearance

        // Title text field in nav bar
        titleField.placeholder = "Title"
        titleField.font = .systemFont(ofSize: 17, weight: .semibold)
        titleField.textAlignment = .center
        titleField.delegate = self
        titleField.addTarget(self, action: #selector(titleChanged), for: .editingChanged)
        titleField.widthAnchor.constraint(equalToConstant: 220).isActive = true
        navigationItem.titleView = titleField

        // Left side - toggle sidebar button
        let toggleSidebarBtn = UIBarButtonItem(
            image: UIImage(systemName: "sidebar.left"),
            style: .plain,
            target: self,
            action: #selector(handleToggleSidebar)
        )
        navigationItem.leftBarButtonItem = toggleSidebarBtn
        
        let undoBtn = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain,
            target: self,
            action: #selector(undoAction)
        )
        let redoBtn = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.forward"),
            style: .plain,
            target: self,
            action: #selector(redoAction)
        )
        let moreBtn = UIBarButtonItem(
            image: UIImage(systemName: "ellipsis.circle"),
            style: .plain,
            target: self,
            action: #selector(showMoreOptions)
        )
        navigationItem.rightBarButtonItems = [moreBtn, redoBtn, undoBtn]
    }
    
    private func configureScrollView() {
        // Set up scroll view for zooming with black background
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.delegate = self
        scrollView.minimumZoomScale = 0.5  // Can zoom out to 50%
        scrollView.maximumZoomScale = 3.0  // Can zoom in to 300%
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = true
        scrollView.showsVerticalScrollIndicator = true
        scrollView.backgroundColor = .black  // Black background to show page boundaries
        
        // IMPORTANT: Delay touch handling to allow PKCanvasView to process touches first
        scrollView.delaysContentTouches = false
        
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Set up zoomable content view
        zoomableContentView.translatesAutoresizingMaskIntoConstraints = false
        zoomableContentView.backgroundColor = .white
        
        // Add shadow to make the page stand out against black background
        zoomableContentView.layer.shadowColor = UIColor.black.cgColor
        zoomableContentView.layer.shadowOpacity = 0.5
        zoomableContentView.layer.shadowOffset = CGSize(width: 0, height: 2)
        zoomableContentView.layer.shadowRadius = 8
        
        scrollView.addSubview(zoomableContentView)
        
        // Size the content view to match the page dimensions
        contentViewWidthConstraint = zoomableContentView.widthAnchor.constraint(equalToConstant: pageWidth)
        contentViewHeightConstraint = zoomableContentView.heightAnchor.constraint(equalToConstant: pageHeight)
        
        NSLayoutConstraint.activate([
            zoomableContentView.topAnchor.constraint(equalTo: scrollView.topAnchor),
            zoomableContentView.leadingAnchor.constraint(equalTo: scrollView.leadingAnchor),
            zoomableContentView.trailingAnchor.constraint(equalTo: scrollView.trailingAnchor),
            zoomableContentView.bottomAnchor.constraint(equalTo: scrollView.bottomAnchor),
            contentViewWidthConstraint,
            contentViewHeightConstraint
        ])
    }

    private func configureBackground() {
        patternBackground.translatesAutoresizingMaskIntoConstraints = false
        patternBackground.style = .lined
        patternBackground.isUserInteractionEnabled = false
        
        // Add pattern as a subview of the zoomable content
        zoomableContentView.addSubview(patternBackground)
        
        NSLayoutConstraint.activate([
            patternBackground.topAnchor.constraint(equalTo: zoomableContentView.topAnchor),
            patternBackground.leadingAnchor.constraint(equalTo: zoomableContentView.leadingAnchor),
            patternBackground.trailingAnchor.constraint(equalTo: zoomableContentView.trailingAnchor),
            patternBackground.bottomAnchor.constraint(equalTo: zoomableContentView.bottomAnchor)
        ])
    }

    private func configureCanvas() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.drawingPolicy = .anyInput
        canvasView.delegate = self
        canvasView.isOpaque = false
        
        // Disable canvas's own scrolling - the parent scrollView handles it
        canvasView.isScrollEnabled = false
        
        // Set a default tool to ensure drawing works immediately
        let defaultTool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.tool = defaultTool
        
        // Add canvas to the zoomable content view
        zoomableContentView.addSubview(canvasView)
        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: zoomableContentView.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: zoomableContentView.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: zoomableContentView.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: zoomableContentView.bottomAnchor)
        ])
        
        // Create container for page separators
        pageSeparatorContainer.translatesAutoresizingMaskIntoConstraints = false
        pageSeparatorContainer.isUserInteractionEnabled = false
        pageSeparatorContainer.backgroundColor = .clear
        
        // Add separator container to zoomable content (between pattern and canvas)
        zoomableContentView.insertSubview(pageSeparatorContainer, aboveSubview: patternBackground)
        
        NSLayoutConstraint.activate([
            pageSeparatorContainer.topAnchor.constraint(equalTo: zoomableContentView.topAnchor),
            pageSeparatorContainer.leadingAnchor.constraint(equalTo: zoomableContentView.leadingAnchor),
            pageSeparatorContainer.trailingAnchor.constraint(equalTo: zoomableContentView.trailingAnchor),
            pageSeparatorContainer.bottomAnchor.constraint(equalTo: zoomableContentView.bottomAnchor)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Update content view width to match scroll view if needed
        if contentViewWidthConstraint.constant != scrollView.bounds.width {
            contentViewWidthConstraint.constant = max(pageWidth, scrollView.bounds.width)
        }
        // Center the content after layout changes
        centerContentInScrollView()
    }
    
    private func updateDrawingPolicy() {
        if pencilOnlyMode {
            canvasView.drawingPolicy = .pencilOnly
        } else {
            // Only allow finger input when not in text mode
            canvasView.drawingPolicy = mode == .text ? .pencilOnly : .anyInput
        }
    }
    
    // MARK: - Page Management
    
    private func calculatePagesNeeded() -> Int {
        let drawingBounds = canvasView.drawing.bounds
        // Always have at least 1 page, add more as drawing extends downward
        let pagesNeeded = max(1, Int(ceil(drawingBounds.maxY / pageHeight)))
        return pagesNeeded
    }
    
    private func addPages(from: Int, to: Int) {
        // Update the content view height to accommodate new pages
        let newHeight = pageHeight * CGFloat(to)
        contentViewHeightConstraint.constant = newHeight
        
        // Add visual page separators
        addPageSeparators(from: from, to: to)
    }
    
    private func addPageSeparators(from: Int, to: Int) {
        for pageIndex in from..<to {
            let separator = createPageSeparator()
            let yPosition = pageHeight * CGFloat(pageIndex)
            separator.frame = CGRect(
                x: 0,
                y: yPosition - 1, // Place at top of new page
                width: pageWidth,  // Use pageWidth instead of view.bounds.width
                height: 2
            )
            pageSeparatorContainer.addSubview(separator)
            pageSeparatorViews.append(separator)
        }
    }
    
    private func createPageSeparator() -> UIView {
        let separator = UIView()
        separator.backgroundColor = UIColor.systemGray4.withAlphaComponent(0.5)
        return separator
    }
    
    private func updatePatternBackgroundSize() {
        // Pattern background now sizes itself via constraints, no manual update needed
    }

    private func configureTextView() {
        textView.translatesAutoresizingMaskIntoConstraints = false
        textView.backgroundColor = .clear
        textView.font = .systemFont(ofSize: 16)
        textView.textColor = .label
        textView.isScrollEnabled = false
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 16, bottom: 16, right: 60)
        textView.delegate = self
        // Place text overlay on top of canvas
        view.addSubview(textView)

        textViewHeightConstraint = textView.heightAnchor.constraint(greaterThanOrEqualToConstant: 200)
        NSLayoutConstraint.activate([
            textView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            textView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            textView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            textViewHeightConstraint
        ])
        // Text view is non-interactive in drawing mode initially
        textView.isUserInteractionEnabled = false
    }

    private func configureFloatingToolbar() {
        floatingToolbar.translatesAutoresizingMaskIntoConstraints = false
        floatingToolbar.delegate = self
        view.addSubview(floatingToolbar)

        floatingToolbarTrailingConstraint = floatingToolbar.trailingAnchor.constraint(
            equalTo: view.safeAreaLayoutGuide.trailingAnchor,
            constant: -12
        )
        NSLayoutConstraint.activate([
            floatingToolbarTrailingConstraint,
            floatingToolbar.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            floatingToolbar.widthAnchor.constraint(equalToConstant: 48)
        ])
    }

    private func configureBottomToolbar() {
        bottomToolbar.translatesAutoresizingMaskIntoConstraints = false
        bottomToolbar.delegate = self
        view.addSubview(bottomToolbar)

        bottomToolbarBottomConstraint = bottomToolbar.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        NSLayoutConstraint.activate([
            bottomToolbar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomToolbar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomToolbarBottomConstraint,
            bottomToolbar.heightAnchor.constraint(equalToConstant: 80)
        ])
    }
    
    private func configureGestures() {
        // Add double-tap gesture for quick zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)
        
        // Configure gesture priorities to prevent zoom from interfering with drawing
        configureGesturePriorities()
    }
    
    private func configureGesturePriorities() {
        // Get the scroll view's pinch gesture recognizer
        guard let scrollViewGestures = scrollView.gestureRecognizers else { return }
        
        // Find all canvas gestures (these are internal to PKCanvasView)
        guard let canvasGestures = canvasView.gestureRecognizers else { return }
        
        // Make scroll view gestures wait for canvas gestures to fail
        // This ensures drawing gets priority over zooming
        for scrollGesture in scrollViewGestures {
            // Only affect pinch gesture (zoom) - we still want panning to work
            if scrollGesture is UIPinchGestureRecognizer {
                for canvasGesture in canvasGestures {
                    // The scroll view's pinch should only activate if the canvas doesn't handle the touch
                    scrollGesture.require(toFail: canvasGesture)
                }
                
                // NOTE: We cannot set a custom delegate on UIScrollView's built-in pinch gesture
                // because UIScrollView requires its own gestures to have the scroll view as delegate.
                // Instead, we'll use a custom gesture recognizer that we can control.
                
                print("🎯 Configured pinch gesture to wait for canvas gestures")
            }
        }
        
        // Add a custom gesture recognizer that can intercept touches before the pinch gesture
        addDrawingProtectionGesture()
    }
    
    private func addDrawingProtectionGesture() {
        // Add a custom gesture recognizer that blocks touches from reaching zoom
        // when we're in drawing mode with single touches
        let protectionGesture = DrawingProtectionGestureRecognizer(target: self, action: nil)
        protectionGesture.delegate = self
        protectionGesture.cancelsTouchesInView = false
        protectionGesture.delaysTouchesBegan = false
        protectionGesture.delaysTouchesEnded = false
        scrollView.addGestureRecognizer(protectionGesture)
        
        print("🛡️ Added drawing protection gesture")
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if scrollView.zoomScale != 1.0 {
            // Reset to normal zoom
            scrollView.setZoomScale(1.0, animated: true)
        } else {
            // Zoom in to 2x at the tap location
            let tapPoint = gesture.location(in: zoomableContentView)
            let zoomRect = zoomRect(for: 2.0, center: tapPoint)
            scrollView.zoom(to: zoomRect, animated: true)
        }
    }
    
    private func zoomRect(for scale: CGFloat, center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero
        let scrollViewSize = scrollView.bounds.size
        zoomRect.size.width = scrollViewSize.width / scale
        zoomRect.size.height = scrollViewSize.height / scale
        zoomRect.origin.x = center.x - (zoomRect.width / 2.0)
        zoomRect.origin.y = center.y - (zoomRect.height / 2.0)
        return zoomRect
    }
    
    private func configureKeyCommands() {
        // Keyboard commands can be added here if needed
    }

    // MARK: - Data

    private func loadNote() {
        note = dataStore.appData.notes.first(where: { $0.id == noteId })
        titleField.text = note?.title
        textView.text = note?.body
        
        // Load settings
        let shouldUsePencilOnly = note?.pencilOnlyMode ?? false
        
        // Set value directly without triggering didSet
        pencilOnlyMode = shouldUsePencilOnly
        
        // Load canvas drawing first
        // Temporarily remove delegate so setting the drawing doesn't trigger
        // canvasViewDrawingDidChange (which would re-serialize the drawing,
        // bump updatedAt, and fire unnecessary notifications on the main thread).
        if let data = note?.canvasData,
           let drawing = try? PKDrawing(data: data) {
            canvasView.delegate = nil
            canvasView.drawing = drawing
            
            // Calculate how many pages are needed for existing drawing
            let pagesNeeded = calculatePagesNeeded()
            if pagesNeeded > numberOfPages {
                addPages(from: numberOfPages, to: pagesNeeded)
                numberOfPages = pagesNeeded
            }
            
            canvasView.delegate = self
        }
        
        // Apply tool and ensure we're in drawing mode
        applyTool(floatingToolbar.selectedTool, color: floatingToolbar.selectedColor)
        
        // Ensure drawing policy is correct after everything is set up
        if mode == .drawing {
            updateDrawingPolicy()
        }
        
        // Ensure textView doesn't block touches
        textView.isUserInteractionEnabled = false
        
        // Configure gesture priorities after canvas is fully set up
        // We need to do this after the drawing is loaded because PKCanvasView
        // might recreate its gesture recognizers
        DispatchQueue.main.async { [weak self] in
            self?.configureGesturePriorities()
        }
        
        // Debug: print current state
        print("🎨 Drawing setup complete:")
        print("  - Canvas tool: \(canvasView.tool)")
        print("  - Drawing policy: \(canvasView.drawingPolicy)")
        print("  - Mode: \(mode)")
        print("  - Pencil only: \(pencilOnlyMode)")
        print("  - Number of pages: \(numberOfPages)")
        print("  - Canvas is first responder: \(canvasView.isFirstResponder)")
        print("  - TextView user interaction: \(textView.isUserInteractionEnabled)")
    }

    private func persistText() {
        let title = titleField.text?.trimmingCharacters(in: .whitespacesAndNewlines)
        dataStore.updateNote(
            id: noteId,
            title: title?.isEmpty == false ? title! : "Untitled Note",
            body: textView.text ?? ""
        )
    }

    private func debouncedPersistText() {
        textPersistWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.persistText()
        }
        textPersistWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + textPersistDelay, execute: workItem)
    }

    // MARK: - Mode switching

    private func setMode(_ newMode: EditorMode) {
        let previousMode = mode
        mode = newMode
        switch newMode {
        case .drawing:
            updateDrawingPolicy()
            textView.isUserInteractionEnabled = false
            textView.resignFirstResponder()
        case .text:
            canvasView.drawingPolicy = .pencilOnly
            textView.isUserInteractionEnabled = true
            textView.becomeFirstResponder()
        }
        
        // If we switched to drawing mode, reconfigure gestures
        if previousMode != .drawing && newMode == .drawing {
            // Give canvas a moment to update its state
            DispatchQueue.main.async { [weak self] in
                self?.configureGesturePriorities()
            }
        }
    }

    private func applyTool(_ tool: DrawingTool, color: UIColor) {
        switch tool {
        case .text:
            setMode(.text)
        case .hand:
            setMode(.text)
            canvasView.drawingPolicy = .pencilOnly
        default:
            setMode(.drawing)
            canvasView.tool = tool.pkTool(color: color, width: 3)
        }
    }

    // MARK: - Keyboard

    private func observeKeyboard() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillShow(_:)),
            name: UIResponder.keyboardWillShowNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(keyboardWillHide(_:)),
            name: UIResponder.keyboardWillHideNotification,
            object: nil
        )
    }

    @objc private func keyboardWillShow(_ notification: Notification) {
        guard let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect,
              let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        let keyboardHeight = frame.height
        UIView.animate(withDuration: duration) {
            self.bottomToolbarBottomConstraint.constant = -keyboardHeight
            self.view.layoutIfNeeded()
        }
    }

    @objc private func keyboardWillHide(_ notification: Notification) {
        guard let duration = notification.userInfo?[UIResponder.keyboardAnimationDurationUserInfoKey] as? Double else { return }
        UIView.animate(withDuration: duration) {
            self.bottomToolbarBottomConstraint.constant = 0
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Nav actions

    @objc private func titleChanged() {
        debouncedPersistText()
    }

    @objc private func undoAction() {
        undoManager?.undo()
    }

    @objc private func redoAction() {
        undoManager?.redo()
    }
    
    @objc private func handleToggleSidebar() {
        // Access the split view controller and toggle the sidebar
        if let splitVC = splitViewController {
            UIView.animate(withDuration: 0.3) {
                splitVC.preferredDisplayMode = splitVC.displayMode == .secondaryOnly ? .oneBesideSecondary : .secondaryOnly
            }
        }
    }

    @objc private func showMoreOptions() {
        let alert = UIAlertController(title: "Note Options", message: nil, preferredStyle: .actionSheet)
        
        // Pencil-only mode toggle
        let pencilModeTitle = pencilOnlyMode ? "Allow Finger Drawing" : "Apple Pencil Only"
        let pencilModeAction = UIAlertAction(title: pencilModeTitle, style: .default) { [weak self] _ in
            guard let self = self else { return }
            self.pencilOnlyMode.toggle()
            self.dataStore.togglePencilOnlyMode(id: self.noteId)
        }
        alert.addAction(pencilModeAction)
        
        // Share action
        let shareAction = UIAlertAction(title: "Share", style: .default) { [weak self] _ in
            self?.shareNote()
        }
        alert.addAction(shareAction)
        
        // Cancel
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        
        // iPad popover support
        if let popover = alert.popoverPresentationController {
            popover.barButtonItem = navigationItem.rightBarButtonItems?.first
        }
        
        present(alert, animated: true)
    }
    
    private func shareNote() {
        let text = note?.title ?? "Note"
        let activityVC = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        activityVC.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.first
        present(activityVC, animated: true)
    }
}

// MARK: - PKCanvasViewDelegate & UIScrollViewDelegate

extension NoteEditorViewController: PKCanvasViewDelegate, UIScrollViewDelegate {
    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        // Expand content immediately (cheap)
        expandContentIfNeeded(canvasView)

        // Debounce the expensive serialization
        canvasSaveWorkItem?.cancel()
        let drawing = canvasView.drawing  // PKDrawing is a value type — safe to capture
        let noteId = self.noteId
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.global(qos: .userInitiated).async {
                let data = drawing.dataRepresentation()
                DispatchQueue.main.async {
                    self.dataStore.updateNoteCanvas(id: noteId, canvasData: data)
                }
            }
        }
        canvasSaveWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + canvasSaveDelay, execute: workItem)
    }

    private func expandContentIfNeeded(_ canvasView: PKCanvasView) {
        let pagesNeeded = calculatePagesNeeded()
        
        if pagesNeeded > numberOfPages {
            addPages(from: numberOfPages, to: pagesNeeded)
            numberOfPages = pagesNeeded
        }
    }
    
    // MARK: - Zoom Support
    
    // Return the view that should be zoomed
    func viewForZooming(in scrollView: UIScrollView) -> UIView? {
        return zoomableContentView
    }
    
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        // Don't check for page expansion while zooming
        // Zoom changes scroll position but shouldn't trigger page adds
        guard !isZooming else { return }
        
        // Check if we need to add more pages as user scrolls
        checkAndExpandPages()
    }
    
    func scrollViewWillBeginZooming(_ scrollView: UIScrollView, with view: UIView?) {
        // Mark that we're starting to zoom
        isZooming = true
        print("🔍 Zoom began")
    }
    
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        // Center the content when zoomed
        centerContentInScrollView()
        print("🔍 Current zoom scale: \(scrollView.zoomScale)")
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Mark that zooming is complete
        isZooming = false
        print("🔍 Zoom ended at scale: \(scale)")
    }
    
    private func centerContentInScrollView() {
        let scrollViewSize = scrollView.bounds.size
        let contentSize = zoomableContentView.frame.size
        
        // Calculate horizontal centering
        let horizontalInset: CGFloat
        if contentSize.width < scrollViewSize.width {
            horizontalInset = (scrollViewSize.width - contentSize.width) / 2
        } else {
            horizontalInset = 0
        }
        
        // Calculate vertical centering
        let verticalInset: CGFloat
        if contentSize.height < scrollViewSize.height {
            verticalInset = (scrollViewSize.height - contentSize.height) / 2
        } else {
            verticalInset = 0
        }
        
        // Apply insets to center the content
        scrollView.contentInset = UIEdgeInsets(
            top: verticalInset,
            left: horizontalInset,
            bottom: verticalInset,
            right: horizontalInset
        )
    }
    
    // Check if user is near bottom and add new page if needed
    private func checkAndExpandPages() {
        // Additional safety check - don't expand during zoom
        // (Should already be blocked by scrollViewDidScroll guard, but be defensive)
        guard !isZooming else { return }
        
        let scrollOffset = scrollView.contentOffset.y
        let scrollViewHeight = scrollView.bounds.height
        let contentHeight = contentViewHeightConstraint.constant
        
        // Trigger when user scrolls to within 300 points of the bottom
        let threshold: CGFloat = 300
        if scrollOffset + scrollViewHeight >= contentHeight - threshold {
            // Add a new page
            let newPageCount = numberOfPages + 1
            addPages(from: numberOfPages, to: newPageCount)
            numberOfPages = newPageCount
            print("📄 Added page \(newPageCount), total pages: \(numberOfPages)")
        }
    }
}

// MARK: - UITextViewDelegate

extension NoteEditorViewController: UITextViewDelegate {
    func textViewDidChange(_ textView: UITextView) {
        debouncedPersistText()
    }
}

// MARK: - UITextFieldDelegate

extension NoteEditorViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}

// MARK: - FloatingToolbarDelegate

extension NoteEditorViewController: FloatingToolbarDelegate {
    func toolbar(_ toolbar: FloatingToolbarView, didSelectTool tool: DrawingTool) {
        applyTool(tool, color: toolbar.selectedColor)
    }

    func toolbar(_ toolbar: FloatingToolbarView, didSelectColor color: UIColor) {
        if case .drawing = mode {
            canvasView.tool = floatingToolbar.selectedTool.pkTool(color: color, width: 3)
        }
    }
}

// MARK: - BottomPaperStyleToolbarDelegate

extension NoteEditorViewController: BottomPaperStyleToolbarDelegate {
    func toolbar(_ toolbar: BottomPaperStyleToolbar, didSelectStyle style: PaperStyle) {
        patternBackground.style = style
    }
    
    func toolbarDidTapAddPhoto(_ toolbar: BottomPaperStyleToolbar) {
        presentPhotoPicker()
    }
    
    private func presentPhotoPicker() {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: configuration)
        picker.delegate = self
        present(picker, animated: true)
    }
}
// MARK: - PHPickerViewControllerDelegate

extension NoteEditorViewController: PHPickerViewControllerDelegate {
    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        
        guard let result = results.first else { return }
        
        result.itemProvider.loadObject(ofClass: UIImage.self) { [weak self] object, error in
            guard let self = self, let image = object as? UIImage else { return }
            
            DispatchQueue.main.async {
                self.addDraggableImage(image)
            }
        }
    }
    
    private func addDraggableImage(_ image: UIImage) {
        // Create draggable image view
        let imageView = DraggableImageView(image: image)
        
        // Add to zoomable content view (on top of canvas) - but don't use auto layout
        imageView.translatesAutoresizingMaskIntoConstraints = true
        zoomableContentView.addSubview(imageView)
        
        // Position in center of visible content area (accounting for scroll offset)
        let contentOffset = scrollView.contentOffset
        let visibleWidth = scrollView.bounds.width
        let visibleHeight = scrollView.bounds.height
        
        // Account for current zoom scale
        let currentScale = scrollView.zoomScale
        
        // Center in the visible area (in content coordinates)
        let centerX = (contentOffset.x + visibleWidth / 2) / currentScale
        let centerY = (contentOffset.y + visibleHeight / 2) / currentScale
        
        // Size the image (max 300x300, maintaining aspect ratio)
        let maxSize: CGFloat = 300
        let scale = min(maxSize / image.size.width, maxSize / image.size.height, 1.0)
        let width = image.size.width * scale
        let height = image.size.height * scale
        
        imageView.frame = CGRect(
            x: centerX - width / 2,
            y: centerY - height / 2,
            width: width,
            height: height
        )
        
        photoImageViews.append(imageView)
        
        print("📸 Image added at frame: \(imageView.frame)")
        print("   - Scroll offset: \(contentOffset)")
        print("   - Zoom scale: \(currentScale)")
    }
}

// MARK: - DraggableImageView

final class DraggableImageView: UIImageView {
    private var panGesture: UIPanGestureRecognizer!
    private var pinchGesture: UIPinchGestureRecognizer!
    private var rotationGesture: UIRotationGestureRecognizer!
    
    override init(image: UIImage?) {
        super.init(image: image)
        setup()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }
    
    private func setup() {
        isUserInteractionEnabled = true
        contentMode = .scaleAspectFit
        
        // Add border to make it clear it's selected/draggable
        layer.borderColor = UIColor.systemBlue.cgColor
        layer.borderWidth = 2
        layer.cornerRadius = 4
        clipsToBounds = true
        
        // Add gestures
        panGesture = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        panGesture.minimumNumberOfTouches = 1
        panGesture.maximumNumberOfTouches = 1
        addGestureRecognizer(panGesture)
        
        pinchGesture = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        addGestureRecognizer(pinchGesture)
        
        rotationGesture = UIRotationGestureRecognizer(target: self, action: #selector(handleRotation(_:)))
        addGestureRecognizer(rotationGesture)
        
        // Add long press gesture to delete
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        addGestureRecognizer(longPress)
        
        // Enable simultaneous gestures for pinch and rotate
        pinchGesture.delegate = self
        rotationGesture.delegate = self
    }
    
    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let superview = superview else { return }
        let translation = gesture.translation(in: superview)
        center = CGPoint(x: center.x + translation.x, y: center.y + translation.y)
        gesture.setTranslation(.zero, in: superview)
        
        if gesture.state == .ended {
            print("📸 Image moved to: \(frame)")
        }
    }
    
    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        if gesture.state == .began || gesture.state == .changed {
            transform = transform.scaledBy(x: gesture.scale, y: gesture.scale)
            gesture.scale = 1.0
        }
    }
    
    @objc private func handleRotation(_ gesture: UIRotationGestureRecognizer) {
        if gesture.state == .began || gesture.state == .changed {
            transform = transform.rotated(by: gesture.rotation)
            gesture.rotation = 0
        }
    }
    
    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        if gesture.state == .began {
            // Show delete option
            let alert = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
            alert.addAction(UIAlertAction(title: "Delete Photo", style: .destructive) { [weak self] _ in
                self?.removeFromSuperview()
            })
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
            
            // Find the view controller
            var responder: UIResponder? = self
            while responder != nil {
                responder = responder?.next
                if let viewController = responder as? UIViewController {
                    if let popover = alert.popoverPresentationController {
                        popover.sourceView = self
                        popover.sourceRect = self.bounds
                    }
                    viewController.present(alert, animated: true)
                    break
                }
            }
        }
    }
    
    // Override point(inside:with:) to only respond to touches on opaque pixels
    override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        // Always respond if we have gestures active
        return super.point(inside: point, with: event)
    }
}

// MARK: - UIGestureRecognizerDelegate
extension DraggableImageView: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow pinch and rotation to work together
        if (gestureRecognizer == pinchGesture && otherGestureRecognizer == rotationGesture) ||
           (gestureRecognizer == rotationGesture && otherGestureRecognizer == pinchGesture) {
            return true
        }
        return false
    }
}

// MARK: - UIGestureRecognizerDelegate (Scroll View)
extension NoteEditorViewController: UIGestureRecognizerDelegate {
    
    /// Determines whether a gesture recognizer should begin
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Only handle our custom protection gesture
        // We cannot interfere with UIScrollView's built-in gestures via shouldBegin
        return true
    }
    
    /// Determines whether two gesture recognizers can recognize simultaneously
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Allow our protection gesture to run with everything (it always fails anyway)
        if gestureRecognizer is DrawingProtectionGestureRecognizer ||
           otherGestureRecognizer is DrawingProtectionGestureRecognizer {
            return true
        }
        
        return false
    }
    
    /// Determines if gesture should receive a touch - THIS IS THE KEY METHOD
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Only filter for our custom protection gesture
        if gestureRecognizer is DrawingProtectionGestureRecognizer {
            // This method's return value doesn't matter for our protection gesture
            // (it always fails), but we use it to block the scroll view's pinch gesture
            return true
        }
        
        // For scroll view's built-in gestures, we need to check if we should allow them
        if gestureRecognizer.view == scrollView {
            
            // Check if this is a pinch gesture (zoom)
            if gestureRecognizer is UIPinchGestureRecognizer {
                
                // Check if the touch is from Apple Pencil
                if touch.type == .pencil {
                    // Always block zoom for Apple Pencil touches - these are for drawing
                    print("✏️ Blocking zoom for Apple Pencil touch")
                    return false
                }
                
                // If we're in drawing mode with finger drawing enabled
                if mode == .drawing && canvasView.drawingPolicy == .anyInput {
                    // Check if touch is on the canvas area
                    let touchLocation = touch.location(in: canvasView)
                    if canvasView.bounds.contains(touchLocation) {
                        // This might be a drawing touch, be conservative
                        // Only allow if there's already another touch (two-finger zoom)
                        
                        // Count how many touches are currently active on the scroll view
                        // We need to check all gesture recognizers to count active touches
                        var touchCount = 0
                        if let gestures = scrollView.gestureRecognizers {
                            for gesture in gestures {
                                touchCount = max(touchCount, gesture.numberOfTouches)
                            }
                        }
                        
                        // If this is the first touch, block zoom (likely drawing)
                        if touchCount < 2 {
                            print("🖐️ Blocking zoom for single finger touch on canvas")
                            return false
                        }
                    }
                }
            }
        }
        
        return true
    }
    
    /// Alternative approach: Check if we should require failure
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRequireFailureOf otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        // Make scroll view's pinch gesture wait for canvas gestures
        if gestureRecognizer.view == scrollView,
           gestureRecognizer is UIPinchGestureRecognizer,
           otherGestureRecognizer.view == canvasView {
            print("🎯 Pinch gesture should wait for canvas gesture to fail")
            return true
        }
        
        return false
    }
}


