import AppKit
import Foundation
import SwiftUI

private struct InspectorCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxHeight: .infinity)
            .background(.regularMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.35), radius: 20, y: 6)
    }
}

struct NoteViewerPanel: View {
    let note: Note
    let onClose: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(note.title)
                            .font(.system(size: 24, weight: .bold, design: .rounded))
                            .foregroundStyle(.white)

                        if !note.subtitle.isEmpty {
                            Text(note.subtitle)
                                .font(.system(size: 13, weight: .medium, design: .rounded))
                                .foregroundStyle(Color.white.opacity(0.75))
                        }
                    }

                    Spacer()

                    Button {
                        onClose()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(GraphSecondaryButtonStyle())
                }

                HStack(spacing: 8) {
                    Button("Edit") {
                        onEdit()
                    }
                    .buttonStyle(GraphPrimaryButtonStyle())

                    Button("Delete", role: .destructive) {
                        onDelete()
                    }
                    .buttonStyle(GraphDangerButtonStyle())
                }

                ScrollView {
                    RichNoteContentView(content: note.content)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct NoteEditorPanel: View {
    @Binding var draft: NoteDraft
    let allNotes: [Note]
    let isExpanded: Bool
    let onToggleExpand: (() -> Void)?
    let onToggleRelation: (Int64, Bool) -> Void
    let onCancel: () -> Void
    let onSave: () -> Void

    @State private var pasteStatus: String?

    var body: some View {
        InspectorCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(draft.existingId == nil ? "New Note" : "Edit Note")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Spacer()

                    if let onToggleExpand {
                        Button {
                            onToggleExpand()
                        } label: {
                            Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        }
                        .buttonStyle(GraphSecondaryButtonStyle())
                        .help(isExpanded ? "Exit full editor" : "Open full editor")
                    }

                    Button {
                        onCancel()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(GraphSecondaryButtonStyle())
                }

                TextField("Title", text: $draft.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .controlSize(.large)
                    .textFieldStyle(.roundedBorder)

                TextField("Subtitle", text: $draft.subtitle)
                    .font(.system(size: 16, weight: .medium, design: .rounded))
                    .controlSize(.large)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    Text("Content")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.82))

                    Spacer()

                    Button("Paste Image") {
                        pasteImageFromClipboard()
                    }
                    .buttonStyle(GraphSecondaryButtonStyle())
                }

                if let pasteStatus {
                    Text(pasteStatus)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                TextEditor(text: $draft.content)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .padding(10)
                    .background(Color.black.opacity(0.28))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .frame(minHeight: isExpanded ? 430 : 260)

                Text("Related Notes")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.82))

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(allNotes.filter { $0.id != draft.existingId }) { note in
                            Toggle(isOn: relationBinding(for: note.id)) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(note.title)
                                        .font(.system(size: 15, weight: .medium, design: .rounded))
                                        .foregroundStyle(.white)
                                    if !note.subtitle.isEmpty {
                                        Text(note.subtitle)
                                            .font(.system(size: 12, weight: .regular, design: .rounded))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
                .frame(maxHeight: 160)

                HStack {
                    Button("Cancel") {
                        onCancel()
                    }
                    .buttonStyle(GraphSecondaryButtonStyle())

                    Spacer()

                    Button("Save") {
                        onSave()
                    }
                    .disabled(draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(GraphPrimaryButtonStyle())
                    .keyboardShortcut(.return, modifiers: [.command])
                }
            }
        }
    }

    private func relationBinding(for noteID: Int64) -> Binding<Bool> {
        Binding {
            draft.relatedIds.contains(noteID)
        } set: { enabled in
            onToggleRelation(noteID, enabled)
        }
    }

    private func pasteImageFromClipboard() {
        guard let image = NSImage(pasteboard: NSPasteboard.general) else {
            pasteStatus = "Clipboard does not contain an image."
            return
        }

        guard let pngData = image.pngData() else {
            pasteStatus = "Could not convert clipboard image to PNG."
            return
        }

        let encoded = pngData.base64EncodedString()
        let markdownImage = "![Pasted image](data:image/png;base64,\(encoded))"
        if draft.content.isEmpty {
            draft.content = markdownImage
        } else {
            draft.content += "\n\n\(markdownImage)\n"
        }
        pasteStatus = "Image embedded into note content."
    }
}

private struct RichNoteContentView: View {
    let content: String

    var body: some View {
        let blocks = parseRichBlocks(from: content)

        VStack(alignment: .leading, spacing: 10) {
            if blocks.isEmpty {
                Text("No content yet.")
                    .font(.system(size: 14, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.75))
            }

            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case let .text(text):
                    if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text(text)
                            .font(.system(size: 14, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.92))
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
                        Text("Image could not be loaded: \(path)")
                            .font(.system(size: 12, weight: .regular, design: .rounded))
                            .foregroundStyle(Color.orange.opacity(0.95))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black.opacity(0.28))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

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

    if matches.isEmpty {
        return [.text(content)]
    }

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
        else {
            return nil
        }

        return bitmap.representation(using: .png, properties: [:])
    }
}

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
