import SwiftUI
import AppKit

/// The Markdown source editor: a plain-text NSTextView with undo, the
/// standard find bar, and the hooks split view needs to link lines to the
/// preview: it reports the line under the mouse and can paint a band
/// behind a range of lines.
struct SourceEditor: NSViewRepresentable {
    @Binding var text: String
    /// Set to true to show the find bar; reset once shown.
    @Binding var showFind: Bool
    var fontSize: CGFloat = 13
    var lineSpacing: CGFloat = 3
    var inset = CGSize(width: 12, height: 12)
    /// 1-based lines to highlight, or nil for none.
    var highlightedLines: ClosedRange<Int>? = nil
    /// Tint of the highlight band; the theme accent, so it matches the preview.
    var highlightColor: NSColor = .controlAccentColor
    /// Called when the mouse moves to another line, with nil when it leaves the text.
    var onHover: ((Int?) -> Void)? = nil
    /// Called when the user scrolls, with the fractional source line at the top.
    /// Setting it also lets the preview scroll this editor (split view sync).
    var onScroll: ((Double) -> Void)? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        storage.addLayoutManager(layout)
        let container = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        layout.addTextContainer(container)

        let textView = HoverTextView(frame: .zero, textContainer: container)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.backgroundColor = .textBackgroundColor
        textView.textColor = .textColor
        textView.insertionPointColor = .textColor
        textView.textContainerInset = inset
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.minSize = .zero
        textView.maxSize = CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.onHover = onHover
        textView.onScroll = onScroll
        applyTypography(to: textView)
        textView.string = text

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        context.coordinator.textView = textView
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(context.coordinator, selector: #selector(Coordinator.didScroll),
                                               name: NSView.boundsDidChangeNotification, object: scrollView.contentView)
        if onScroll != nil { PreviewController.shared.attachEditor(textView) }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? HoverTextView else { return }
        let coordinator = context.coordinator
        coordinator.parent = self
        textView.onHover = onHover
        textView.onScroll = onScroll
        if textView.string != text {
            coordinator.isSettingText = true
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
            applyTypography(to: textView)
            coordinator.isSettingText = false
        }
        textView.highlightedLines = highlightedLines
        textView.highlightColor = highlightColor
        if showFind {
            let item = NSMenuItem()
            item.tag = Int(NSTextFinder.Action.showFindInterface.rawValue)
            textView.performTextFinderAction(item)
            textView.window?.makeFirstResponder(textView)
            Task { @MainActor in showFind = false }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    private func applyTypography(to textView: NSTextView) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        let font = NSFont.monospacedSystemFont(ofSize: fontSize, weight: .regular)
        textView.font = font
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: font, .paragraphStyle: paragraph, .foregroundColor: NSColor.textColor]
        if let storage = textView.textStorage, storage.length > 0 {
            storage.addAttributes(textView.typingAttributes, range: NSRange(location: 0, length: storage.length))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: SourceEditor
        weak var textView: HoverTextView?
        var isSettingText = false

        init(parent: SourceEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard !isSettingText, let textView else { return }
            parent.text = textView.string
        }

        @objc func didScroll(_ notification: Notification) {
            textView?.reportScroll()
        }
    }
}

/// NSTextView that tracks the line under the mouse and draws a highlight
/// band behind a range of lines.
final class HoverTextView: NSTextView {
    var onHover: ((Int?) -> Void)?
    var highlightedLines: ClosedRange<Int>? {
        didSet { if highlightedLines != oldValue { needsDisplay = true } }
    }
    var highlightColor: NSColor = .controlAccentColor
    var onScroll: ((Double) -> Void)?
    /// Set while the preview drives the scroll, so it isn't echoed back.
    private var isFollowing = false

    private var trackingArea: NSTrackingArea?
    private var hoveredLine: Int?
    /// UTF-16 offset where each line starts; rebuilt after edits.
    private var lineStarts: [Int]?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func didChangeText() {
        super.didChangeText()
        lineStarts = nil
    }

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        report(line(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        report(nil)
    }

    private func report(_ line: Int?) {
        guard line != hoveredLine else { return }
        hoveredLine = line
        onHover?(line)
    }

    /// 1-based line at a point in view coordinates, or nil below the text.
    private func line(at point: NSPoint) -> Int? {
        guard let layoutManager, let textContainer else { return nil }
        let used = layoutManager.usedRect(for: textContainer)
        let y = point.y - textContainerOrigin.y
        guard y >= used.minY, y <= used.maxY else { return nil }
        let index = characterIndexForInsertion(at: point)
        return lineNumber(forCharacter: index)
    }

    // MARK: Scroll sync

    func reportScroll() {
        guard !isFollowing, let onScroll, let line = topLine() else { return }
        onScroll(line)
    }

    /// Scrolls so that fractional source `line` sits at the top.
    func scroll(toLine line: Double) {
        guard let scrollView = enclosingScrollView, !string.isEmpty else { return }
        let whole = min(max(Int(line), 1), starts().count)
        let rect = lineRect(whole)
        let y = rect.minY + rect.height * min(max(line - Double(whole), 0), 1) + textContainerOrigin.y
        // The clip view scrolls in its own coordinates, where this view's
        // origin isn't necessarily zero, so convert and clamp to the text.
        let clip = scrollView.contentView
        let target = convert(NSPoint(x: 0, y: y), to: clip).y
        let top = convert(NSPoint.zero, to: clip).y
        let bottom = max(top, top + frame.height - clip.bounds.height)
        isFollowing = true
        clip.scroll(to: NSPoint(x: clip.bounds.minX, y: min(max(target, top), bottom)))
        scrollView.reflectScrolledClipView(scrollView.contentView)
        isFollowing = false
    }

    /// Fractional 1-based source line at the top of the visible area.
    private func topLine() -> Double? {
        guard let layoutManager, let textContainer, !string.isEmpty else { return nil }
        let y = visibleRect.minY - textContainerOrigin.y
        guard y > 0 else { return 1 }
        let glyph = layoutManager.glyphIndex(for: NSPoint(x: 0, y: y), in: textContainer)
        let line = lineNumber(forCharacter: layoutManager.characterIndexForGlyph(at: glyph))
        let rect = lineRect(line)
        guard rect.height > 0 else { return Double(line) }
        return Double(line) + min(max((y - rect.minY) / rect.height, 0), 1)
    }

    /// Bounds of a 1-based source line (all its wrapped fragments), in
    /// text container coordinates.
    private func lineRect(_ line: Int) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let starts = starts()
        let location = starts[line - 1]
        let end = line < starts.count ? starts[line] : (string as NSString).length
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: location, length: end - location), actualCharacterRange: nil)
        guard glyphs.length > 0 else { return layoutManager.extraLineFragmentRect }
        return layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
    }

    private func starts() -> [Int] {
        if let lineStarts { return lineStarts }
        let text = string as NSString
        var result = [0]
        var searchRange = NSRange(location: 0, length: text.length)
        while true {
            let found = text.range(of: "\n", options: [], range: searchRange)
            guard found.location != NSNotFound else { break }
            result.append(found.location + 1)
            searchRange = NSRange(location: found.location + 1, length: text.length - found.location - 1)
        }
        lineStarts = result
        return result
    }

    private func lineNumber(forCharacter index: Int) -> Int {
        let starts = starts()
        var low = 0, high = starts.count - 1
        while low < high {
            let mid = (low + high + 1) / 2
            if starts[mid] <= index { low = mid } else { high = mid - 1 }
        }
        return low + 1
    }

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard let highlightedLines, let layoutManager, let textContainer else { return }
        let starts = starts()
        let length = (string as NSString).length
        let first = max(highlightedLines.lowerBound, 1), last = min(highlightedLines.upperBound, starts.count)
        guard first <= last else { return }
        let location = starts[first - 1]
        let end = last < starts.count ? starts[last] : length
        let glyphs = layoutManager.glyphRange(forCharacterRange: NSRange(location: location, length: max(end - location, 0)), actualCharacterRange: nil)
        var band: NSRect
        if glyphs.length > 0 {
            band = layoutManager.boundingRect(forGlyphRange: glyphs, in: textContainer)
        } else {
            // An empty trailing line still has a fragment rect.
            band = layoutManager.extraLineFragmentRect
            if band.isEmpty { return }
        }
        band.origin.y += textContainerOrigin.y
        band.origin.x = 4
        band.size.width = bounds.width - 8
        guard band.intersects(rect) else { return }
        highlightColor.withAlphaComponent(0.16).setFill()
        NSBezierPath(roundedRect: band.insetBy(dx: 0, dy: -1), xRadius: 4, yRadius: 4).fill()
    }
}
