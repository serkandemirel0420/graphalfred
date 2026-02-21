import AppKit
import Foundation
import SwiftUI

// MARK: – Shared card container

private struct InspectorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxHeight: .infinity)
            .background(
                ZStack {
                    Color(red: 0.08, green: 0.08, blue: 0.10)
                    LinearGradient(
                        colors: [Color.white.opacity(0.03), Color.clear],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.white.opacity(0.11), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.45), radius: 24, y: 8)
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
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(2)

                        if !note.subtitle.isEmpty {
                            Text(note.subtitle)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.58))
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

                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

                // Content
                ScrollView {
                    RichNoteContentView(content: note.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 16)
                }

                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)

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
    let allNotes: [Note]
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    let onToggleRelation: (Int64, Bool) -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var attachedImages: [Data] = []
    @State private var pasteStatus: String?
    @State private var relatedExpanded = false
    @FocusState private var focusedField: EditorField?

    private enum EditorField: Hashable {
        case title, subtitle, content
    }

    private var hasSaveableTitle: Bool {
        !draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 0) {
                editorHeader
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                editorFields
                Rectangle().fill(Color.white.opacity(0.07)).frame(height: 1)
                editorFooter
            }
        }
        .onExitCommand { onCancel() }
        .onAppear { loadAttachedImages() }
    }

    // MARK: – Header

    private var editorHeader: some View {
        HStack {
            Text(draft.existingId == nil ? "New Note" : "Edit Note")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(.white)

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
                        .font(.system(size: 19, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .title)
                        .onSubmit { focusedField = .subtitle }
                }

                rowDivider()

                // Subtitle
                editorFieldRow(label: "Subtitle") {
                    TextField("", text: $draft.subtitle)
                        .font(.system(size: 14, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))
                        .textFieldStyle(.plain)
                        .focused($focusedField, equals: .subtitle)
                        .onSubmit { focusedField = .content }
                }

                rowDivider()

                // Content
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        editorLabel("Content")
                        Spacer()
                        if let pasteStatus {
                            Text(pasteStatus)
                                .font(.system(size: 11, weight: .regular, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.55))
                        }
                        Button("Paste Image") { pasteImageFromClipboard() }
                            .buttonStyle(GraphSecondaryButtonStyle())
                    }

                    TextEditor(text: $draft.content)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.9))
                        .scrollContentBackground(.hidden)
                        .padding(10)
                        .background(Color.black.opacity(0.22))
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(Color.white.opacity(0.08), lineWidth: 1)
                        )
                        .focused($focusedField, equals: .content)
                        .frame(minHeight: isExpanded ? 280 : 160)

                    // Inline image attachments
                    if !attachedImages.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(Array(attachedImages.enumerated()), id: \.offset) { index, data in
                                    if let image = NSImage(data: data) {
                                        ZStack(alignment: .topTrailing) {
                                            Image(nsImage: image)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 100, height: 80)
                                                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                                                )

                                            Button {
                                                attachedImages.remove(at: index)
                                            } label: {
                                                Image(systemName: "xmark.circle.fill")
                                                    .font(.system(size: 16, weight: .bold))
                                                    .foregroundStyle(Color.white)
                                                    .shadow(color: .black.opacity(0.6), radius: 2)
                                            }
                                            .buttonStyle(.plain)
                                            .offset(x: 6, y: -6)
                                        }
                                    }
                                }
                            }
                            .padding(.top, 4)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)

                // Related notes (collapsible)
                if !allNotes.isEmpty {
                    rowDivider()
                    relatedNotesSection
                }
            }
        }
    }

    // MARK: – Related notes

    private var relatedNotesSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    relatedExpanded.toggle()
                }
            } label: {
                HStack {
                    editorLabel("Related Notes")

                    let selectedCount = allNotes.filter { draft.relatedIds.contains($0.id) }.count
                    if selectedCount > 0 {
                        Text("\(selectedCount)")
                            .font(.system(size: 10, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.cyan.opacity(0.72))
                            .clipShape(Capsule())
                    }

                    Spacer()

                    Image(systemName: relatedExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
            }
            .buttonStyle(.plain)

            if relatedExpanded {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(allNotes.filter { $0.id != draft.existingId }) { note in
                        Button {
                            onToggleRelation(note.id, !draft.relatedIds.contains(note.id))
                        } label: {
                            HStack(spacing: 10) {
                                Image(systemName: draft.relatedIds.contains(note.id)
                                      ? "checkmark.circle.fill"
                                      : "circle")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(draft.relatedIds.contains(note.id)
                                                     ? Color.cyan.opacity(0.85) : Color.white.opacity(0.35))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title)
                                        .font(.system(size: 13, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                    if !note.subtitle.isEmpty {
                                        Text(note.subtitle)
                                            .font(.system(size: 11, weight: .regular, design: .rounded))
                                            .foregroundStyle(Color.white.opacity(0.45))
                                    }
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 9)
                        }
                        .buttonStyle(.plain)

                        Rectangle().fill(Color.white.opacity(0.05)).frame(height: 1)
                            .padding(.horizontal, 20)
                    }
                }
                .frame(maxHeight: 200)
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
                .foregroundStyle(Color.white.opacity(0.35))

            Button("Save") { commitAndSave() }
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
                        .foregroundStyle(Color.red.opacity(0.75))
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
            .foregroundStyle(Color.white.opacity(0.38))
            .textCase(.uppercase)
            .tracking(0.6)
    }

    @ViewBuilder
    private func rowDivider() -> some View {
        Rectangle().fill(Color.white.opacity(0.06)).frame(height: 1)
    }

    private func pasteImageFromClipboard() {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            pasteStatus = "No image in clipboard."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { pasteStatus = nil }
            return
        }

        guard let pngData = image.pngData() else {
            pasteStatus = "Could not convert image."
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { pasteStatus = nil }
            return
        }

        attachedImages.append(pngData)
        pasteStatus = "Image attached."
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { pasteStatus = nil }
    }

    private func loadAttachedImages() {
        let pattern = #"!\[[^\]]*\]\(data:image/[^;]+;base64,([^)]+)\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }

        let ns = draft.content as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let matches = regex.matches(in: draft.content, range: fullRange)

        var extracted: [Data] = []
        var strippedContent = draft.content

        for match in matches.reversed() {
            let base64Range = match.range(at: 1)
            if base64Range.location != NSNotFound,
               let b64 = ns.substring(with: base64Range) as String?,
               let data = Data(base64Encoded: b64) {
                extracted.insert(data, at: 0)
            }
            let fullMatchRange = Range(match.range(at: 0), in: strippedContent)
            if let range = fullMatchRange {
                strippedContent.removeSubrange(range)
            }
        }

        attachedImages = extracted
        draft.content = strippedContent.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func commitAndSave() {
        var combined = draft.content.trimmingCharacters(in: .whitespacesAndNewlines)
        for data in attachedImages {
            let b64 = data.base64EncodedString()
            combined += "\n\n![Pasted image](data:image/png;base64,\(b64))"
        }
        draft.content = combined
        onSave()
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
                    .foregroundStyle(Color.white.opacity(0.35))
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .text(text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.88))
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
                            .foregroundStyle(Color.orange.opacity(0.9))
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

    var body: some View {
        ZStack {
            Color.black.opacity(0.22)
                .ignoresSafeArea()
                .onTapGesture { onClose() }

            VStack {
                VStack(spacing: 0) {
                    HStack(spacing: 10) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 17, weight: .medium))
                        TextField("Search notes...", text: $query)
                            .textFieldStyle(.plain)
                            .focused($isFocused)
                            .font(.system(size: 24, weight: .medium, design: .rounded))
                            .onSubmit {
                                if let first = results.first {
                                    onPick(first)
                                }
                            }

                        Spacer()

                        Text("esc")
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.white.opacity(0.75))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Color.white.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    }
                    .padding(16)

                    Divider()

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            if results.isEmpty {
                                Text(query.isEmpty ? "Type to search notes" : "No results")
                                    .foregroundStyle(.secondary)
                                    .padding(18)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }

                            ForEach(results) { note in
                                Button {
                                    onPick(note)
                                } label: {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(note.title)
                                            .font(.system(size: 17, weight: .semibold, design: .rounded))
                                        if !note.subtitle.isEmpty {
                                            Text(note.subtitle)
                                                .font(.system(size: 13, weight: .regular, design: .rounded))
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(note.content)
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
                                            .lineLimit(2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .padding(14)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .buttonStyle(.plain)

                                Divider()
                            }
                        }
                    }
                }
                .frame(width: 760, height: 430)
                .background(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.24), lineWidth: 1)
                )
                .shadow(color: Color.black.opacity(0.35), radius: 26, y: 10)
                .padding(.top, 84)

                Spacer()
            }
            .onAppear {
                DispatchQueue.main.async {
                    isFocused = true
                }
            }
            .onExitCommand(perform: onClose)
        }
    }
}
