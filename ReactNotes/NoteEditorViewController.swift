import UIKit
import PencilKit

// MARK: - EditorMode

enum EditorMode {
    case drawing
    case text
}

// MARK: - NoteEditorViewController

final class NoteEditorViewController: UIViewController {
    private let dataStore: DataStore
    private let noteId: String
    private var note: Note?

    // MARK: UI

    private let patternBackground = PatternBackgroundView()
    private let canvasView = PKCanvasView()
    private let textView = UITextView()
    private let floatingToolbar = FloatingToolbarView()
    private let bottomToolbar = BottomPaperStyleToolbar()
    private let titleField = UITextField()

    // Layout
    private var floatingToolbarTrailingConstraint: NSLayoutConstraint!
    private var bottomToolbarBottomConstraint: NSLayoutConstraint!
    private var textViewHeightConstraint: NSLayoutConstraint!

    // State
    private var mode: EditorMode = .drawing
    private var numberOfPages: Int = 1
    private var pageSeparatorViews: [UIView] = []
    private var pageSeparatorContainer: UIView!  // Container for separators that moves with scroll

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
        view.backgroundColor = .white
        configureNavigation()
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

    private func configureBackground() {
        patternBackground.translatesAutoresizingMaskIntoConstraints = false
        patternBackground.style = .lined
        patternBackground.isUserInteractionEnabled = false
        // Add to main view, behind the canvas
        view.insertSubview(patternBackground, at: 0)
        
        NSLayoutConstraint.activate([
            patternBackground.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            patternBackground.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            patternBackground.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            patternBackground.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }

    private func configureCanvas() {
        canvasView.translatesAutoresizingMaskIntoConstraints = false
        canvasView.backgroundColor = .clear
        canvasView.drawingPolicy = .anyInput
        canvasView.alwaysBounceVertical = true
        canvasView.delegate = self
        canvasView.isOpaque = false
        
        // Enable zooming
        canvasView.minimumZoomScale = 0.5  // Can zoom out to 50%
        canvasView.maximumZoomScale = 3.0  // Can zoom in to 300%
        canvasView.bouncesZoom = true
        
        // Start with one page worth of content
        canvasView.contentSize = CGSize(width: view.bounds.width, height: pageHeight)
        
        // Set a default tool to ensure drawing works immediately
        let defaultTool = PKInkingTool(.pen, color: .black, width: 3)
        canvasView.tool = defaultTool
        
        view.addSubview(canvasView)
        NSLayoutConstraint.activate([
            canvasView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            canvasView.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            canvasView.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            canvasView.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
        
        // Create container for page separators (sits between background and canvas)
        pageSeparatorContainer = UIView()
        pageSeparatorContainer.translatesAutoresizingMaskIntoConstraints = false
        pageSeparatorContainer.isUserInteractionEnabled = false
        pageSeparatorContainer.backgroundColor = .clear
        view.insertSubview(pageSeparatorContainer, aboveSubview: patternBackground)
        
        NSLayoutConstraint.activate([
            pageSeparatorContainer.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            pageSeparatorContainer.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            pageSeparatorContainer.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            pageSeparatorContainer.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor)
        ])
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Pattern background is now a sibling view, no need to add it here
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
        // Update canvas content size
        let newHeight = pageHeight * CGFloat(to)
        canvasView.contentSize.height = newHeight
        
        // Pattern background is now a sibling view and doesn't need resizing
        // It will be updated via transform on scroll
        
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
                width: view.bounds.width,
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
        patternBackground.frame.size = canvasView.contentSize
        patternBackground.setNeedsDisplay()
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
        // Add double-tap gesture to reset zoom
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        canvasView.addGestureRecognizer(doubleTap)
    }
    
    private func configureKeyCommands() {
        // Keyboard commands can be added here if needed
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        if canvasView.zoomScale != 1.0 {
            // Reset to normal zoom
            canvasView.setZoomScale(1.0, animated: true)
        } else {
            // Zoom in to 2x at the tap location
            let tapPoint = gesture.location(in: canvasView)
            let zoomRect = zoomRect(for: 2.0, center: tapPoint)
            canvasView.zoom(to: zoomRect, animated: true)
        }
    }
    
    private func zoomRect(for scale: CGFloat, center: CGPoint) -> CGRect {
        var zoomRect = CGRect.zero
        zoomRect.size.width = canvasView.bounds.width / scale
        zoomRect.size.height = canvasView.bounds.height / scale
        zoomRect.origin.x = center.x - (zoomRect.width / 2.0)
        zoomRect.origin.y = center.y - (zoomRect.height / 2.0)
        return zoomRect
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

// MARK: - PKCanvasViewDelegate

extension NoteEditorViewController: PKCanvasViewDelegate {
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
    
    // Handle scroll events to sync pattern background
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        updatePatternBackgroundTransform()
    }
    
    // Handle zoom events
    func scrollViewDidZoom(_ scrollView: UIScrollView) {
        updatePatternBackgroundTransform()
    }
    
    func scrollViewDidEndZooming(_ scrollView: UIScrollView, with view: UIView?, atScale scale: CGFloat) {
        // Optional: Log zoom level for debugging
        print("🔍 Zoom scale: \(scale)")
    }
    
    private func updatePatternBackgroundTransform() {
        // Move the pattern background and separators to match the canvas scroll offset
        // but without applying zoom scale (so pattern and separators stay at fixed size)
        let offset = canvasView.contentOffset
        let transform = CGAffineTransform(translationX: -offset.x, y: -offset.y)
        patternBackground.transform = transform
        pageSeparatorContainer.transform = transform
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
}
