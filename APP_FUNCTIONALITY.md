# App Overview

## What This App Does

This is a **note-taking app for iPad** that combines handwritten drawing with typed text, designed for students, professionals, and anyone who wants to take rich, visual notes.

## Core Features

### 📝 Drawing & Writing

**Apple Pencil Drawing**
- Smooth, natural drawing with full Apple Pencil support
- Multiple drawing tools: pen, pencil, marker, highlighter, eraser
- Color picker with customizable colors
- Pressure-sensitive strokes for realistic writing feel
- Automatic page expansion as you draw

**Text Entry**
- Switch between drawing and text modes
- Full keyboard support for typed notes
- Mix handwritten and typed content

### 🎨 Customization

**Paper Styles**
- Multiple paper backgrounds: blank, lined, grid, dot grid
- Change paper style anytime without losing content
- Pattern backgrounds scale with zoom

**Drawing Tools**
- Pen (clean, consistent lines)
- Pencil (textured, natural feel)
- Marker (bold, thick strokes)
- Highlighter (transparent overlay)
- Eraser (precise or broad)

### 🔍 Navigation & Viewing

**Zoom Controls**
- Pinch-to-zoom (0.5x to 3x)
- Double-tap to toggle zoom
- Smooth zoom with centered content
- Draw at any zoom level

**Page Management**
- Automatic page expansion when drawing extends beyond current page
- Scroll-triggered page addition when reaching bottom
- Visual page separators
- Standard letter-size pages (8.5" × 11")

**Scrolling**
- Smooth vertical scrolling through multiple pages
- Page boundaries clearly marked
- Content stays aligned with paper pattern

### 📷 Photo Integration

**Add Photos**
- Import photos from photo library
- Photos appear as draggable, resizable stickers
- Pinch to scale photos
- Rotate with two-finger gesture
- Long-press to delete

**Photo Manipulation**
- Drag anywhere on the page
- Resize proportionally
- Rotate to any angle
- Layer on top of drawings

### 📚 Organization

**Notebooks**
- Create multiple notebooks for different subjects
- Color-code notebooks
- Sidebar navigation for quick access

**Notes**
- Multiple notes per notebook
- Titled notes with timestamps
- Thumbnail previews
- Favorite important notes

**Sidebar**
- Collapsible sidebar (tap icon to toggle)
- Browse all notebooks and notes
- Quick note switching
- Create new notes and notebooks

### ⚙️ Settings & Modes

**Drawing Modes**
- **Any Input**: Draw with finger or Apple Pencil
- **Pencil Only**: Only Apple Pencil can draw (prevents accidental marks)

**Tool Selection**
- Floating toolbar for quick tool switching
- Color picker always accessible
- Undo/redo buttons in navigation bar

**Keyboard**
- Keyboard shortcuts for common actions
- Smooth keyboard appearance/disappearance
- Toolbar adjusts when keyboard is visible

## User Interface

### Navigation Bar (Top)
```
[Sidebar] [← →]           Title Field           [Undo] [Redo] [•••]
```

- **Left**: Toggle sidebar, undo, redo
- **Center**: Note title (tap to edit)
- **Right**: More options menu

### Floating Toolbar (Right Edge)
- Drawing tool selection
- Color picker
- Always visible for quick access
- Automatically positioned

### Bottom Toolbar
- Paper style selection (blank, lined, grid, dots)
- Add photo button
- Keyboard-aware positioning

### Canvas Area (Center)
- Drawing surface with selected paper style
- Zoomable and scrollable
- Page separators between pages
- Centered in view with black background

## Technical Features

### Performance
- Debounced saving (0.5s delay) to reduce disk writes
- Background serialization of canvas data
- Thumbnail caching with automatic invalidation
- Smooth 60fps drawing and zooming

### Gesture Recognition
- Smart gesture coordination prevents conflicts
- Apple Pencil always triggers drawing (never zoom)
- Two-finger pinch for zoom
- Single-finger drawing (in any-input mode)
- Separate gestures for photos vs. canvas

### Data Management
- JSON-based data storage
- Automatic save on changes
- PencilKit canvas data serialization
- Schema versioning for future compatibility

### State Management
- Mode tracking (drawing vs. text)
- Zoom state prevents unwanted page expansion
- Page count dynamically adjusts
- Settings persist per note

## User Workflows

### Creating a Note
1. Tap sidebar icon
2. Select or create notebook
3. Tap "+" to create new note
4. Start drawing or typing

### Drawing
1. Select tool from floating toolbar
2. Choose color
3. Draw with Apple Pencil or finger
4. Canvas automatically expands as needed

### Switching Paper Style
1. Tap paper style icon in bottom toolbar
2. Select desired style (blank, lined, grid, dots)
3. Existing drawing remains intact

### Adding Photos
1. Tap photo icon in bottom toolbar
2. Select photo from library
3. Photo appears in center
4. Drag, resize, or rotate as needed
5. Long-press to delete

### Zooming
1. **Zoom in**: Pinch out with two fingers
2. **Zoom out**: Pinch in with two fingers
3. **Quick toggle**: Double-tap canvas
4. Draw or scroll while zoomed

### Switching Modes
1. **Drawing → Text**: Tap text tool
2. **Text → Drawing**: Tap any drawing tool
3. Modes are mutually exclusive

### Managing Settings
1. Tap "•••" in top-right
2. Toggle "Apple Pencil Only" mode
3. Share note
4. Other options as available

## Architecture Highlights

### View Controllers
- **SidebarViewController**: Notebook and note navigation
- **NoteEditorViewController**: Main drawing/editing interface
- **NoteGridViewController**: Grid view of notes (if applicable)

### Key Components
- **PKCanvasView**: Apple's PencilKit canvas for drawing
- **UIScrollView**: Handles zooming and scrolling
- **FloatingToolbarView**: Tool and color selection
- **BottomPaperStyleToolbar**: Paper styles and photo button
- **PatternBackgroundView**: Rendered paper patterns
- **DraggableImageView**: Interactive photo views

### Data Models
- **Note**: Title, body, canvas data, timestamps, settings
- **Notebook**: Title, color, order, timestamps
- **AppData**: Top-level container with schema version

### Gesture System
- **UIScrollViewDelegate**: Zoom and scroll coordination
- **PKCanvasViewDelegate**: Drawing change detection
- **UIGestureRecognizerDelegate**: Touch filtering and priority
- **Custom DrawingProtectionGestureRecognizer**: Prevents zoom conflicts

## Platform

- **Platform**: iPadOS
- **Minimum Version**: iOS 14+ (PencilKit requirement)
- **Orientation**: Portrait and landscape
- **Split View**: Supports iPad multitasking
- **Apple Pencil**: Full support for 1st and 2nd generation

## Key Design Decisions

1. **PencilKit Integration**: Uses Apple's native drawing framework for best performance and feel
2. **Page-Based Layout**: Standard letter-size pages for familiar note-taking experience
3. **Zoom + Scroll**: Allows detailed work while maintaining document overview
4. **Floating Toolbar**: Always accessible without obscuring content
5. **Smart Gesture Filtering**: Prevents zoom from interfering with drawing
6. **Automatic Expansion**: No manual page management needed
7. **Instant Feedback**: Immediate visual response to all interactions

## Future Enhancement Areas

- Export to PDF
- Cloud sync
- Handwriting recognition
- Shape detection and cleanup
- Multiple page layouts
- Custom paper templates
- Collaboration features
- Audio recording
- Search functionality

---

**Summary**: A powerful, intuitive note-taking app that combines the flexibility of handwritten notes with modern digital features, optimized for iPad and Apple Pencil.

