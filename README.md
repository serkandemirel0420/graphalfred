# GraphAlfred

Native macOS graph note app with:

- SwiftUI desktop UI (single large graph canvas)
- Rust backend (local data + API)
- Local graph storage (SQLite `notes` + `links`)
- Local Lucene-like full-text search (Tantivy)
- Draggable nodes, modal note viewer/editor, double-click edit
- `Cmd+K` quick search overlay (Alfred-like)
- Global hotkey `Option+Space` (Spotlight-style launcher)
- Auto-layout endpoint to re-align graph positions

## Project Layout

- `backend/`: Rust server (`axum`) + SQLite + Tantivy
- `macos/`: SwiftUI native app (`swift build` / `swift run`)

## Run

### 1. Build backend

```bash
cd backend
cargo build
```

### 2. Run macOS app

```bash
cd macos
swift run
```

The app auto-starts the backend if it finds one of these binaries:

- `backend/target/debug/graphalfred-backend`
- `backend/target/release/graphalfred-backend`
- `target/debug/graphalfred-backend`
- `target/release/graphalfred-backend`

You can also force a path:

```bash
export GRAPHALFRED_BACKEND_PATH=/absolute/path/to/graphalfred-backend
swift run --package-path macos
```

## Features Mapped To Your Request

- One big screen graph view with note titles/subtitles
- Click note: open note content in modal
- Double click note: open edit modal directly
- Drag nodes to move graph content
- Lines between related notes
- Auto-align positions
- `Cmd+K` global-like quick search window
- `Option+Space` global quick search hotkey
- Full-text search powered by Tantivy

## Backend Endpoints

- `GET /health`
- `GET /graph`
- `POST /notes`
- `GET /notes/{id}`
- `PUT /notes/{id}`
- `DELETE /notes/{id}`
- `PUT /notes/{id}/position`
- `POST /links`
- `DELETE /links`
- `GET /search?q=...&limit=...`
- `POST /layout/auto`

## Notes

- Backend data directory defaults to:
  - `~/Library/Application Support/GraphAlfred`
- On first empty launch, app seeds a few demo nodes so graph UI is visible immediately.
