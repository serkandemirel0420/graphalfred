import AppKit
import Foundation
import SwiftUI

// MARK: – Shared card container

private struct InspectorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxHeight: .infinity)
            .background(Color(red: 0.97, green: 0.97, blue: 0.98))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.10), radius: 20, y: 6)
    }
}

// MARK: – Note viewer

struct NoteViewerPanel: View {
    let note: Note
    let onClose: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(alignment: .top, spacing: 10) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(note.title)
                            .font(.system(size: 20, weight: .bold, design: .rounded))
                            .foregroundStyle(Color(white: 0.08))
                            .lineLimit(2)

                        if !note.subtitle.isEmpty {
                            Text(note.subtitle)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color(white: 0.48))
                        }
                    }

                    Spacer()

                    Button { onClose() } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(GraphSecondaryButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 14)

                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)

                // Content
                ScrollView {
                    RichNoteContentView(content: note.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }

                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)

                // Actions
                HStack(spacing: 8) {
                    Button("Edit") { onEdit() }
                        .buttonStyle(GraphPrimaryButtonStyle())

                    Spacer()

                    Button("Delete", role: .destructive) { onDelete() }
                        .buttonStyle(GraphDangerButtonStyle())
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }
}

// MARK: – Note editor

struct NoteEditorPanel: View {
    @Binding var draft: NoteDraft
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    let onCancel: () -> Void
    let onSave: () -> Void

    @FocusState private var titleFocused: Bool

    private var hasSaveableTitle: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 0) {
                editorHeader
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
                editorFields
                Rectangle().fill(Color.black.opacity(0.06)).frame(height: 1)
                editorFooter
            }
        }
        .onExitCommand { onCancel() }
    }

    // MARK: – Header

    private var editorHeader: some View {
        HStack {
            Text(draft.existingId == nil ? "New Note" : "Edit Note")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(Color(white: 0.12))

            Spacer()

            if let onToggleExpand {
                Button {
                    onToggleExpand()
                } label: {
                    Image(systemName: isExpanded
                        ? "arrow.down.right.and.arrow.up.left"
                        : "arrow.up.left.and.arrow.down.right")
                }
                .buttonStyle(GraphSecondaryButtonStyle())
                .help(isExpanded ? "Exit full editor" : "Open full editor")
            }

            Button { onCancel() } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(GraphSecondaryButtonStyle())
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: – Fields

    private var editorFields: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // Title
                editorFieldRow(label: "Title", required: true) {
                    TextField("", text: $draft.title)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color(white: 0.10))
                        .textFieldStyle(.plain)
                        .focused($titleFocused)
                }

                rowDivider()

                // Subtitle
                editorFieldRow(label: "Subtitle") {
                    TextField("", text: $draft.subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Color(white: 0.38))
                        .textFieldStyle(.plain)
                }

                rowDivider()

                // Content — rich text editor with inline image paste
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        editorLabel("Content")
                        Spacer()
                        Text("⌘V to paste images")
                            .font(.system(size: 11, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.58))
                    }

                    RichTextEditor(content: $draft.content)
                        .frame(minHeight: isExpanded ? 320 : 180)
                        .background(Color.black.opacity(0.03))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.black.opacity(0.07), lineWidth: 1)
                        )
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
        }
    }

    // MARK: – Footer

    private var editorFooter: some View {
        HStack {
            Button("Cancel") { onCancel() }
                .buttonStyle(GraphSecondaryButtonStyle())

            Spacer()

            Text(hasSaveableTitle ? "" : "Title required")
                .font(.system(size: 11, weight: .regular, design: .rounded))
                .foregroundStyle(Color(white: 0.55))

            Button("Save") { onSave() }
                .disabled(!hasSaveableTitle)
                .buttonStyle(GraphPrimaryButtonStyle())
                .keyboardShortcut(.return, modifiers: [.command])
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    // MARK: – Helpers

    @ViewBuilder
    private func editorFieldRow<Content: View>(
        label: String,
        required: Bool = false,
        @ViewBuilder field: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                editorLabel(label)
                if required {
                    Text("*")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Color(red: 0.82, green: 0.18, blue: 0.15).opacity(0.75))
                }
            }
            field()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    @ViewBuilder
    private func editorLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(white: 0.52))
            .textCase(.uppercase)
            .tracking(0.6)
    }

    @ViewBuilder
    private func rowDivider() -> some View {
        Rectangle().fill(Color.black.opacity(0.05)).frame(height: 1)
    }
}

// MARK: – Rich text editor (NSTextView-backed)

private final class ImageTextAttachment: NSTextAttachment {
    /// Original PNG data so we can serialize back to base64 markdown on save.
    var pngData: Data?
}

private final class RichTextNSTextView: NSTextView {
    override func paste(_ sender: Any?) {
        let pb = NSPasteboard.general
        if pb.canReadObject(forClasses: [NSImage.self], options: nil),
           let image = NSImage(pasteboard: pb),
           let data = image.pngData() {
            insertRichImage(image, pngData: data)
        } else if let string = pb.string(forType: .string) {
            insertText(string, replacementRange: selectedRange())
        } else {
            super.paste(sender)
        }
    }

    func insertRichImage(_ image: NSImage, pngData: Data) {
        let attachment = ImageTextAttachment()
        attachment.pngData = pngData
        let maxW: CGFloat = 380
        let sz = image.size
        let scale = sz.width > maxW ? maxW / sz.width : 1.0
        let displaySize = CGSize(width: sz.width * scale, height: sz.height * scale)
        attachment.image = image
        attachment.bounds = CGRect(origin: .zero, size: displaySize)

        let attStr = NSAttributedString(attachment: attachment)
        let nl = NSAttributedString(string: "\n", attributes: typingAttributes)
        guard let storage = textStorage else { return }
        let loc = selectedRange().location
        storage.beginEditing()
        storage.insert(nl, at: loc)
        storage.insert(attStr, at: loc + 1)
        storage.insert(nl, at: loc + 2)
        storage.endEditing()
        setSelectedRange(NSRange(location: loc + 3, length: 0))
        delegate?.textDidChange?(Notification(name: NSText.didChangeNotification, object: self))
    }
}

struct RichTextEditor: NSViewRepresentable {
    @Binding var content: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        let textView = RichTextNSTextView()

        textView.isRichText = true
        textView.isEditable = true
        textView.isSelectable = true
        textView.font = NSFont.systemFont(ofSize: 14)
        textView.textColor = NSColor(white: 0.15, alpha: 1)
        textView.backgroundColor = .clear
        textView.drawsBackground = false
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.allowsImageEditing = false
        textView.importsGraphics = false
        textView.delegate = context.coordinator
        textView.textStorage?.setAttributedString(Self.markdownToAttributed(content))

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.lastSync = content
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? RichTextNSTextView else { return }
        let coordinator = context.coordinator
        guard !coordinator.isEditing, content != coordinator.lastSync else { return }
        textView.textStorage?.setAttributedString(Self.markdownToAttributed(content))
        coordinator.lastSync = content
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    // MARK: Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: RichTextEditor
        fileprivate weak var textView: RichTextNSTextView?
        var isEditing = false
        var lastSync = ""

        init(_ p: RichTextEditor) { parent = p }

        func textDidChange(_ notification: Notification) {
            guard let tv = notification.object as? NSTextView else { return }
            isEditing = true
            let markdown = RichTextEditor.attributedToMarkdown(tv.attributedString())
            parent.content = markdown
            lastSync = markdown
            isEditing = false
        }
    }

    // MARK: Conversions

    static func markdownToAttributed(_ content: String) -> NSAttributedString {
        let defaultAttrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 14),
            .foregroundColor: NSColor(white: 0.15, alpha: 1)
        ]

        let pattern = #"!\[[^\]]*\]\(([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return NSAttributedString(string: content, attributes: defaultAttrs)
        }

        let nsContent = content as NSString
        let fullRange = NSRange(location: 0, length: nsContent.length)
        let matches = regex.matches(in: content, options: [], range: fullRange)

        guard !matches.isEmpty else {
            return NSAttributedString(string: content, attributes: defaultAttrs)
        }

        let result = NSMutableAttributedString()
        var cursor = 0

        for match in matches {
            let fullMatch = match.range(at: 0)
            let pathRange = match.range(at: 1)

            if fullMatch.location > cursor {
                let textPart = nsContent.substring(with: NSRange(location: cursor, length: fullMatch.location - cursor))
                result.append(NSAttributedString(string: textPart, attributes: defaultAttrs))
            }

            if pathRange.location != NSNotFound,
               let data = imageData(from: nsContent.substring(with: pathRange)),
               let img = NSImage(data: data) {
                let attachment = ImageTextAttachment()
                attachment.pngData = data
                let maxW: CGFloat = 380
                let sz = img.size
                let scale = sz.width > maxW ? maxW / sz.width : 1.0
                attachment.image = img
                attachment.bounds = CGRect(origin: .zero, size: CGSize(width: sz.width * scale, height: sz.height * scale))
                result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
                result.append(NSAttributedString(attachment: attachment))
                result.append(NSAttributedString(string: "\n", attributes: defaultAttrs))
            }

            cursor = fullMatch.location + fullMatch.length
        }

        if cursor < nsContent.length {
            result.append(NSAttributedString(string: nsContent.substring(from: cursor), attributes: defaultAttrs))
        }

        return result
    }

    static func attributedToMarkdown(_ attributed: NSAttributedString) -> String {
        var result = ""
        let fullRange = NSRange(location: 0, length: attributed.length)

        attributed.enumerateAttributes(in: fullRange, options: []) { attrs, range, _ in
            if let attachment = attrs[.attachment] as? ImageTextAttachment, let data = attachment.pngData {
                let b64 = data.base64EncodedString()
                result += "\n![Image](data:image/png;base64,\(b64))\n"
            } else if let attachment = attrs[.attachment] as? NSTextAttachment,
                      let img = attachment.image, let data = img.pngData() {
                let b64 = data.base64EncodedString()
                result += "\n![Image](data:image/png;base64,\(b64))\n"
            } else {
                let text = attributed.attributedSubstring(from: range).string
                result += text.filter { $0 != "\u{FFFC}" }
            }
        }

        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func imageData(from path: String) -> Data? {
        if path.hasPrefix("data:image"), let commaIdx = path.firstIndex(of: ",") {
            return Data(base64Encoded: String(path[path.index(after: commaIdx)...]))
        }
        if let url = URL(string: path), url.isFileURL { return try? Data(contentsOf: url) }
        if path.hasPrefix("/") { return try? Data(contentsOf: URL(fileURLWithPath: path)) }
        return nil
    }
}

// MARK: – Rich content viewer

private struct RichNoteContentView: View {
    let content: String

    var body: some View {
        let blocks = parseRichBlocks(from: content)

        VStack(alignment: .leading, spacing: 12) {
            if blocks.isEmpty {
                Text("No content yet.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(Color(white: 0.65))
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .text(text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color(white: 0.15))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                case let .image(path):
                    if let image = loadImage(from: path) {
                        Image(nsImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        Text("Image could not be loaded.")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.orange.opacity(0.85))
                    }
                }
            }
        }
    }
}

// MARK: – Block parsing

private enum RichBlock {
    case text(String)
    case image(String)
}

private func parseRichBlocks(from content: String) -> [RichBlock] {
    guard !content.isEmpty else { return [] }

    let pattern = #"!\[[^\]]*\]\(([^)]+)\)"#
    guard let regex = try? NSRegularExpression(pattern: pattern) else {
        return [.text(content)]
    }

    let nsContent = content as NSString
    let fullRange = NSRange(location: 0, length: nsContent.length)
    let matches = regex.matches(in: content, options: [], range: fullRange)

    if matches.isEmpty { return [.text(content)] }

    var blocks: [RichBlock] = []
    var cursor = 0

    for match in matches {
        let fullMatch = match.range(at: 0)
        let imagePathRange = match.range(at: 1)

        if fullMatch.location > cursor {
            let textRange = NSRange(location: cursor, length: fullMatch.location - cursor)
            blocks.append(.text(nsContent.substring(with: textRange)))
        }

        if imagePathRange.location != NSNotFound {
            blocks.append(.image(nsContent.substring(with: imagePathRange)))
        }

        cursor = fullMatch.location + fullMatch.length
    }

    if cursor < nsContent.length {
        blocks.append(.text(nsContent.substring(from: cursor)))
    }

    return blocks
}

private func loadImage(from path: String) -> NSImage? {
    if path.hasPrefix("data:image"),
       let commaIndex = path.firstIndex(of: ",") {
        let encoded = String(path[path.index(after: commaIndex)...])
        if let data = Data(base64Encoded: encoded), let image = NSImage(data: data) {
            return image
        }
    }

    if let url = URL(string: path), url.isFileURL {
        return NSImage(contentsOf: url)
    }

    if path.hasPrefix("/") {
        return NSImage(contentsOfFile: path)
    }

    return nil
}

private extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiffData)
        else { return nil }
        return bitmap.representation(using: .png, properties: [:])
    }
}

// MARK: – Quick search overlay

struct QuickSearchOverlay: View {
    @Binding var query: String
    let results: [Note]
    let onClose: () -> Void
    let onPick: (Note) -> Void

    @FocusState private var isFocused: Bool
    @State private var selectedIndex: Int = 0

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(Color(white: 0.55))
                            .font(.system(size: 17, weight: .medium))
                        TextField("Search notes…", text: $query)
                            .textFieldStyle(.plain)
                            .focused($isFocused)
                            .font(.system(size: 22, weight: .medium, design: .rounded))
                            .foregroundStyle(Color(white: 0.10))
                            .onSubmit {
                                if results.indices.contains(selectedIndex) {
                                    onPick(results[selectedIndex])
                                } else if let first = results.first {
                                    onPick(first)
                                }
                            }
                            .onKeyPress(.upArrow) {
                                selectedIndex = max(0, selectedIndex - 1)
                                return .handled
                            }
                            .onKeyPress(.downArrow) {
                                selectedIndex = min(results.count - 1, selectedIndex + 1)
                                return .handled
                            }

                        Spacer()

                        Text("esc")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color(white: 0.45))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.black.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .padding(16)

                    Divider()

                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if results.isEmpty {
                                    Text(query.isEmpty ? "Type to search notes" : "No results")
                                        .foregroundStyle(Color(white: 0.55))
                                        .font(.system(size: 14, weight: .regular, design: .rounded))
                                        .padding(18)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }

                                ForEach(Array(results.enumerated()), id: \.element.id) { idx, note in
                                    Button {
                                        onPick(note)
                                    } label: {
                                        VStack(alignment: .leading, spacing: 4) {
                                            HStack(spacing: 6) {
                                                if note.parentId != nil {
                                                    Image(systemName: "arrow.turn.down.right")
                                                        .font(.system(size: 10, weight: .semibold))
                                                        .foregroundStyle(Color(white: 0.55))
                                                }
                                                Text(note.title)
                                                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                                                    .foregroundStyle(Color(white: 0.10))
                                            }
                                            if !note.subtitle.isEmpty {
                                                Text(note.subtitle)
                                                    .font(.system(size: 13, weight: .regular, design: .rounded))
                                                    .foregroundStyle(Color(white: 0.48))
                                            }
                                            let preview = contentPreview(note.content)
                                            if !preview.isEmpty {
                                                Text(preview)
                                                    .font(.system(size: 12, weight: .regular, design: .rounded))
                                                    .lineLimit(2)
                                                    .foregroundStyle(Color(white: 0.55))
                                            }
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(idx == selectedIndex
                                            ? Color(white: 0.12).opacity(0.06)
                                            : Color.clear)
                                    }
                                    .buttonStyle(.plain)
                                    .id(idx)

                                    Divider()
                                }
                            }
                        }
                        .onChange(of: selectedIndex) { idx in
                            withAnimation { proxy.scrollTo(idx, anchor: .center) }
                        }
                    }
                }
                .frame(width: 720, height: 420)
                .background(Color(red: 0.97, green: 0.97, blue: 0.98))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.black.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.14), radius: 24, y: 10)
                .padding(.top, 80)

                Spacer()
            }
            .onAppear {
                DispatchQueue.main.async { isFocused = true }
            }
            .onExitCommand(perform: onClose)
        }
        .onChange(of: results) { _ in selectedIndex = 0 }
    }

    /// Strips base64 image markdown from content for a clean preview.
    private func contentPreview(_ content: String) -> String {
        let stripped = content.replacingOccurrences(
            of: #"!\[[^\]]*\]\(data:image[^)]+\)"#,
            with: "",
            options: .regularExpression
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return stripped
    }
}
