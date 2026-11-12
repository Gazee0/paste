# Paste UI contract

The app is a menu-bar clipboard palette. The window is a custom borderless `NSPanel`; the
SwiftUI root fills it. The panel is **560×456 collapsed** and **844×540 with preview open**. A 36pt tab bar
(剪贴板 / 快贴) sits above the search field.
When the preview opens the extra width/height goes to the right and bottom; the top-left stays
put. The left history column is always 560pt wide.

Reference screenshots (read-only, copy first if editing):
- `/Users/edy/.dsh/attachments/v1/objects/04/040b3832c5c1ac3fb41bab69376150071617be492aade231f5894e95df9129da`
- `/Users/edy/.dsh/attachments/v1/objects/29/29930b23909d9fcf604087927da8036d06958e4ef81cc705fd5c5c7eef8a409a`

## File ownership

The UI teammate owns only `Sources/PasteKit/Views/**`. The Lead owns everything else
including `AppModel.swift`. Do not edit any other file. Don't add a second `@main`.

## Root layout

```
VStack(spacing: 0) {
  PaletteTabBar(height: 36)       // 剪贴板 / 快贴 left; eye/pin/close right; Tab switches
  TopBarView(height: 48)         // search field only, spans full width
  Divider (1px)
  HStack(spacing: 0) {
    VStack(spacing: 0) {          // width: 560
      Filter bar: 全部 / 文本 / 图片 / 文件 (31pt)
      HistoryListView (flex)
      FooterView (40pt)
    }
    if model.isPreviewOpen {
      Divider (vertical)
      PreviewPane(width: 284)
    }
  }
}
.frame(maxWidth: .infinity, maxHeight: .infinity)
.background(app background)
.clipShape(RoundedRectangle(cornerRadius: 12))
.overlay(RoundedRectangle... stroke 1px)
```

Expose `struct RootView: View { @ObservedObject var model: AppModel }` — this is the only
type the Lead's `PanelController` constructs.

## Theme

- Light background near `#FAF9F6` / dark near `#1C1C1E`; adapt with `NSColor` dynamic provider.
- Top/footer same background; selected row `Color.primary.opacity(0.065)`.
- Accent is system accent for the primary "拷贝" button and focus ring.
- Use system fonts. Main content 12pt, meta 10pt, search 12pt, section header 10.5pt.
- Window has rounded 12pt corners; no title bar is drawn by the panel.

## Top bar

- Search field: rounded rect, 7pt radius, 32pt height, 12pt inset. Placeholder
  `搜索拷贝的文本`. Focused state shows a 2pt accent stroke; otherwise 1pt
  `primary.opacity(0.10)`. White/light fill in light mode. Always focus on appear and whenever
  `model.focusRequestNonce` changes. A small clear `xmark.circle.fill` appears when query isn't
  empty.
- 预览 button: eye icon + "预览", 28–30pt height, subtle rounded background when open. Calls
  `model.togglePreview()`. Disabled/opacity 0.45 when no selected item.
- Pin button: `pin` / `pin.fill` icon; accent when `model.isWindowPinned`; calls
  `model.toggleWindowPin()`. Help `窗口置顶`.
- Close button: `xmark`, calls `model.requestHide()`. Help `关闭`.
- Layout: search takes all remaining width; controls on trailing side with 8pt gaps, 12pt
  horizontal outer padding. Don't put search inside a section that shrinks when preview opens:
  the field should widen with the window.

## History list

- Filter bar chips 全部 / 文本 / 图片 / 文件, 10.5pt medium; selected chip has a subtle
  primary-tint background. Clicking a chip filters by `ClipboardKind`; ←/→ do the same while
  the search query is empty.
- ScrollView + LazyVStack so a 200-item history does not materialize every row at once.
  Rows touch full width with 6pt horizontal inset and 4pt vertical gap; native overlay
  scrollers preferred. Preview-height padding keeps the list offset stable while the preview
  window animates.
- Image rows use a 256px downsampled thumbnail; the preview uses at most 640px; the
  full-resolution image is loaded only by the large-image viewer and is not cached: closing
  the viewer releases it. The small decoded caches are cleared when the palette hides.
- Row (`HistoryRowView`), about 54–64pt tall, dynamic up to 2 lines:
  - Leading type icon (14pt) in a 26×26 tinted rounded square: text = `doc.text` blue,
    image = `photo` purple, files = `folder` orange.
  - Content: item.displayText, 12pt, up to 2 lines, truncation tail. For text preserve newlines.
  - Trailing meta stack (right aligned): item time `model.timeText(for:)` at 10pt secondary;
    below it the shortcut badge `⌘N` if `model.shortcutIndex(for:)` is non-nil (10pt, tertiary).
  - If item.isPinned: a tiny orange `pin.fill` (9pt) next to time.
  - Background: selected or hovered row `primary.opacity(0.065)`, rounded 7pt. In multi-select
    mode show a leading 15pt checkbox instead of/in addition to the icon; checked state uses
    accent. Multi-select rows use accent tint when checked.
  - Separator 1px inset 44pt leading, 12pt trailing, only between rows.
  - `.contentShape(Rectangle())`, hover sets `model.select(item)` only when not multi-select
    and not `model.isEditingPreview`. This is required for hover-to-preview.
  - Single click: in multi-select toggles check; otherwise selects and calls
    `model.refocusSearch()`. Double click (non-multi-select) calls `model.paste(item)`.
  - Right-click menu: `拷贝` -> `model.copy(item)`, `粘贴` -> `model.paste(item)`,
    `固定项目`/`取消固定` -> `model.togglePin(item)`, divider, `删除` -> `model.delete(item)`.
  - Scroll to selected row when `model.keyboardScrollNonce` changes; use ScrollViewReader and
    `scrollTo(selectedID, anchor: .center)` with a short ease-out animation.
- Empty states: no history -> clipboard icon, "暂无剪贴板记录", "复制任意内容后会自动出现在这里";
  search with no match -> magnifying glass, "没有找到匹配的内容", "换个关键词试试".
- Rows should be efficient: use a separate `HistoryRowView: View, Equatable` if practical.

## Footer (left column)

- 40pt tall, top divider, 12pt horizontal padding.
- Left: 多选 button (`checkmark.circle` + "多选", or `checkmark.circle.fill` + "完成") calling
  `model.toggleMultiSelect()`.
- When multi-select is on: destructive `删除 N` button appears (trash icon, red), calls
  `model.deleteChecked()`; disabled when count is 0.
- Right: clipboard icon + total `model.historyCount` (not filtered count), 10.5pt secondary.
  When searching, optionally show `filtered/total` but total must remain visible.
- All controls styled flat, secondary; no default bordered buttons.

## Preview pane (right, 284pt)

```
VStack(spacing: 0) {
  content (text / image / files), padding 14
  Spacer
  Divider
  footer: time + source app ... 编辑 拷贝 buttons // 40pt
}
```
The preview column has no header: its close action is the top-bar eye toggle (Space/⇧Space).
`Esc` never closes the preview.

- Content for `.text`: a read-only `NSTextView` in a scroll view, 12.5pt, preserving newlines.
  Text is selectable for drag-selection and `⌘C`; clicking it focuses the text view, so the search
  field only owns the keyboard until the user interacts with the preview text. If
  `model.editingID == item.id`,
  show a `TextEditor` seeded with the current text and focus it; footer replaces 编辑 with
  `取消` + `保存` (accent).
- Image: `Image(nsImage:)` from `model.image(for:)`, aspect-fit in available area, rounded
  6pt, subtle border; caption `图片 · W×H` and source. Hovering the image shows a 查看大图
  affordance; clicking it, or the footer 查看大图 button, calls
  `model.showLargeImagePreview()`.
- Files: list each file name with `doc` icon, secondary path underneath, max width truncation.
- Footer: left time `model.timeText(for: item.createdAt)` and optional source app (truncated);
  right `编辑` (only text, hidden while editing), `查看大图` (only image), and primary blue
  `拷贝` calling `model.copy(item)`. `拷贝` disabled while editing.
- Editing: `model.beginEditing()`, local draft string, `model.saveEditing(text:)` (returns
  Bool; if false keep editing), `model.cancelEditing()`.
- Empty state when selected item is nil: "选择一条记录以预览".
- Preview is not a separate window; it is the right column of the same root.

## Large image viewer (separate panel)

`ImagePreviewController` owns a borderless floating `NSPanel` opened by
`AppModel.showLargeImagePreview()`:

- ~78% of the parent screen's visible frame (760–1500 × 520–940), centered, dark appearance.
- Top bar: image dimensions/source, zoom out/in, percentage, 适应, 100%, close.
- Canvas: aspect-fit on open, trackpad pinch zoom, drag to pan when zoomed, double-click toggles
  fit/100%, footer hint. `Esc` or `⌘W` closes; focus returns to the search field.
- Implementation: `Sources/PasteKit/App/ImagePreviewController.swift` and
  `Sources/PasteKit/Views/LargeImagePreviewView.swift`.

## Keyboard

The Lead installs the NSEvent monitor; the UI need not install one. The model supplies
`moveSelection(by:)`, `togglePreview()`, `pasteSelected()`, etc. UI must accept focus via
`focusRequestNonce` and show focus ring.

## Toast

Overlay at bottom center of the left column (above footer) when `model.toast != nil`: dark
capsule or material with white/primary text, 11pt; optional action button if
`toast.actionTitle != nil` calling `model.performToastAction()`; tap/close dismisses via
`model.dismissToast()`. Animate with opacity/offset. Don't let it block row interaction.

## Settings window

A separate 620×700 borderless settings panel is opened from the menu-bar menu, the app menu, or
`⌘,`. It contains a grouped shortcut reference (global, window/search, clipboard, quick tab,
text editing, preview/large image, menu bar) plus the data-directory footer. It is not part of
the palette and does not affect palette geometry.

## Quick tab

- Tab bar switches between clipboard history and quick snippets with Tab / ⇧Tab.
- Quick tab: 148pt folder sidebar (全部 / 未分类 / custom folders) + snippet list + 40pt
  footer. The search field is shared and clears when switching tabs.
- Snippets have content, optional note, and folder. Footer 新建 opens the editor sheet;
  context menu supports edit/copy/paste/delete; double-click/Return paste.
- Keyboard focus has two zones. Up/down move list selection by default; `←` enters the folder
  sidebar and `→` returns to the list. In the folder zone up/down change the selected folder.
  The focused zone is indicated by an accent outline.
- The right preview pane is the same size and shares the same show/hide state as the clipboard
  preview. Quick snippet copy uses the same paste-target flow as clipboard text.

## Rules

- No extra windows, popovers, settings, or top-level modes beyond the palette's two tabs
  (剪贴板 / 快贴), inline filters, and the large image viewer.
- Chinese UI copy only.
- SwiftUI only for views; AppKit allowed for color helpers.
- macOS 14+ APIs only.
- No external dependencies.
- Keep `RootView` constructible as `RootView(model: model)`.
- Compile and fix your own view errors when the Lead's shell is available; do not modify core files.
