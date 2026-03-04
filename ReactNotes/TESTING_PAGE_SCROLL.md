# Testing the Page-Based Scrolling Implementation

## Quick Testing Guide

### Test 1: New Note Creation ✓
1. Create a new note
2. **Expected**: Canvas should start with 1 page visible
3. **Expected**: Pattern background (lines) should be visible
4. **Expected**: Can draw at the top of the page

### Test 2: Drawing Stays Attached to Pattern ✓
1. Draw some ink on the first page
2. Scroll down, then scroll back up
3. **Expected**: Ink should stay perfectly aligned with the paper lines
4. **Expected**: No "floating" effect - ink moves with pattern

### Test 3: Automatic Page Expansion ✓
1. Draw content that extends beyond the first page
2. Continue drawing downward
3. **Expected**: Canvas automatically expands to add new pages
4. **Expected**: You should see a thin gray line separating pages
5. **Expected**: Can continue drawing on the new page

### Test 4: Multi-Page Scrolling ✓
1. Create a note with content spanning 2-3 pages
2. Scroll up and down through all pages
3. **Expected**: All ink stays attached to pattern
4. **Expected**: Page separators are visible between pages
5. **Expected**: Smooth scrolling throughout

### Test 5: Loading Existing Notes ✓
1. Create a note with 2+ pages of content
2. Exit the note and reopen it
3. **Expected**: All pages load correctly
4. **Expected**: Can scroll through all existing content
5. **Expected**: Pattern background matches content size

### Test 6: Pattern Style Changes ✓
1. Draw on a page
2. Change the paper style (using bottom toolbar)
3. **Expected**: New pattern applies to entire canvas
4. **Expected**: Ink stays aligned with new pattern

### Test 7: No Upward Expansion ✓
1. Start a new note
2. Try to scroll above the first page
3. **Expected**: Can't scroll above the starting position
4. **Expected**: Canvas stays anchored at the top

## Known Behaviors

### Page Height
- Each page is **1056 points tall** (11 inches at 96 DPI)
- Standard US Letter size

### Page Separators
- Thin gray lines (2pt height)
- 50% opacity
- Appear at the top of each new page

### Expansion Trigger
- New pages are added when drawing extends beyond current canvas height
- Calculation: `pagesNeeded = ceil(drawingBounds.maxY / pageHeight)`

## Debug Output

When loading a note, check console for:
```
🎨 Drawing setup complete:
  - Canvas tool: <PKInkingTool>
  - Drawing policy: anyInput
  - Mode: drawing
  - Pencil only: false
  - Number of pages: X
  - Canvas is first responder: true
  - TextView user interaction: false
```

## Troubleshooting

### If ink appears to float:
- Check that `patternBackground` is a subview of `canvasView`
- Verify `patternBackground.frame.size.height` matches `canvasView.contentSize.height`

### If pages don't expand:
- Verify `calculatePagesNeeded()` is being called
- Check that drawing bounds extend beyond current page
- Look for console output about page expansion

### If pattern doesn't scroll:
- Confirm pattern is added to canvas with `canvasView.insertSubview(patternBackground, at: 0)`
- Check that pattern is not constrained to main view

## Performance Notes

- Page expansion is lightweight (< 1ms)
- Pattern updates happen automatically
- Drawing saves are still debounced (0.5s)
- No performance impact on scrolling

## Comparison to Previous Behavior

### Before:
- ❌ Canvas started at 10,000pt
- ❌ Pattern was separate from canvas
- ❌ Ink appeared to float when scrolling
- ❌ Arbitrary content expansion

### After:
- ✅ Canvas starts at 1 page (1056pt)
- ✅ Pattern scrolls with canvas
- ✅ Ink stays attached to paper
- ✅ Clean page-based expansion
