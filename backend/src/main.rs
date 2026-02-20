use anyhow::{anyhow, Context};
use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    response::{IntoResponse, Response},
    routing::{get, post, put},
    Json, Router,
};
use rusqlite::{params, Connection, OptionalExtension};
use serde::{Deserialize, Serialize};
use std::{
    cmp::Reverse,
    collections::HashSet,
    env,
    net::SocketAddr,
    path::{Path as FsPath, PathBuf},
    sync::{Arc, Mutex, MutexGuard},
};
use tantivy::{
    collector::TopDocs,
    doc,
    query::QueryParser,
    schema::{Field, Schema, Value, INDEXED, STORED, TEXT},
    Index, IndexReader, IndexWriter, TantivyDocument, Term,
};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    let config = Config::from_args()?;

    std::fs::create_dir_all(&config.data_dir)
        .with_context(|| format!("failed to create data dir {}", config.data_dir.display()))?;

    let db_path = config.data_dir.join("graphalfred.db");
    let index_dir = config.data_dir.join("search-index");
    let store = Store::open(&db_path, &index_dir)?;

    let state = Arc::new(Mutex::new(store));

    let app = Router::new()
        .route("/health", get(health))
        .route("/graph", get(get_graph))
        .route("/notes", post(create_note))
        .route(
            "/notes/{id}",
            get(get_note).put(update_note).delete(delete_note_handler),
        )
        .route("/notes/{id}/position", put(update_note_position))
        .route("/links", post(create_link).delete(delete_link_handler))
        .route("/search", get(search_notes))
        .route("/layout/auto", post(auto_layout))
        .with_state(state);

    let addr: SocketAddr = format!("{}:{}", config.host, config.port)
        .parse()
        .context("failed to parse bind address")?;

    println!("GraphAlfred backend listening on http://{addr}");

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .context("failed to bind backend listener")?;

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown_signal())
        .await
        .context("backend server error")?;

    Ok(())
}

async fn shutdown_signal() {
    if let Err(err) = tokio::signal::ctrl_c().await {
        eprintln!("ctrl-c listener error: {err}");
    }
    println!("Shutting down backend...");
}

#[derive(Debug)]
struct Config {
    host: String,
    port: u16,
    data_dir: PathBuf,
}

impl Config {
    fn from_args() -> anyhow::Result<Self> {
        let mut host = String::from("127.0.0.1");
        let mut port = 8787;
        let mut data_dir = default_data_dir()?;

        let mut args = env::args().skip(1);
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "--host" => {
                    host = args
                        .next()
                        .ok_or_else(|| anyhow!("missing value for --host"))?;
                }
                "--port" => {
                    let raw = args
                        .next()
                        .ok_or_else(|| anyhow!("missing value for --port"))?;
                    port = raw
                        .parse::<u16>()
                        .with_context(|| format!("invalid port: {raw}"))?;
                }
                "--data-dir" => {
                    let raw = args
                        .next()
                        .ok_or_else(|| anyhow!("missing value for --data-dir"))?;
                    data_dir = PathBuf::from(raw);
                }
                _ => {}
            }
        }

        Ok(Self {
            host,
            port,
            data_dir,
        })
    }
}

fn default_data_dir() -> anyhow::Result<PathBuf> {
    let home = env::var("HOME").context("HOME not set")?;
    Ok(PathBuf::from(home)
        .join("Library")
        .join("Application Support")
        .join("GraphAlfred"))
}

#[derive(Debug)]
enum ApiError {
    BadRequest(String),
    NotFound(String),
    Internal(anyhow::Error),
}

impl From<anyhow::Error> for ApiError {
    fn from(value: anyhow::Error) -> Self {
        Self::Internal(value)
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        #[derive(Serialize)]
        struct ErrorBody {
            error: String,
        }

        match self {
            ApiError::BadRequest(message) => {
                (StatusCode::BAD_REQUEST, Json(ErrorBody { error: message })).into_response()
            }
            ApiError::NotFound(message) => {
                (StatusCode::NOT_FOUND, Json(ErrorBody { error: message })).into_response()
            }
            ApiError::Internal(err) => {
                eprintln!("internal error: {err:#}");
                (
                    StatusCode::INTERNAL_SERVER_ERROR,
                    Json(ErrorBody {
                        error: "internal server error".to_string(),
                    }),
                )
                    .into_response()
            }
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Note {
    id: i64,
    title: String,
    subtitle: String,
    content: String,
    x: f64,
    y: f64,
    updated_at: String,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
struct Link {
    source_id: i64,
    target_id: i64,
}

#[derive(Debug, Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct GraphResponse {
    notes: Vec<Note>,
    links: Vec<Link>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateNoteRequest {
    title: String,
    subtitle: Option<String>,
    content: Option<String>,
    x: Option<f64>,
    y: Option<f64>,
    related_ids: Option<Vec<i64>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateNoteRequest {
    title: String,
    subtitle: String,
    content: String,
    x: f64,
    y: f64,
    related_ids: Option<Vec<i64>>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdatePositionRequest {
    x: f64,
    y: f64,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LinkRequest {
    source_id: i64,
    target_id: i64,
}

#[derive(Debug, Deserialize)]
struct SearchQuery {
    q: String,
    limit: Option<usize>,
}

#[derive(Debug, Serialize)]
struct SearchResponse {
    results: Vec<Note>,
}

struct Store {
    conn: Connection,
    search: SearchIndex,
}

impl Store {
    fn open(db_path: &FsPath, index_dir: &FsPath) -> anyhow::Result<Self> {
        let conn = Connection::open(db_path)
            .with_context(|| format!("failed to open sqlite db {}", db_path.display()))?;
        conn.pragma_update(None, "foreign_keys", "ON")?;

        let mut store = Self {
            conn,
            search: SearchIndex::open(index_dir)?,
        };

        store.init_schema()?;

        let notes = store.list_notes()?;
        store.search.rebuild(&notes)?;

        Ok(store)
    }

    fn init_schema(&self) -> anyhow::Result<()> {
        self.conn.execute_batch(
            r#"
            CREATE TABLE IF NOT EXISTS notes (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT NOT NULL,
                subtitle TEXT NOT NULL DEFAULT '',
                content TEXT NOT NULL DEFAULT '',
                x REAL NOT NULL DEFAULT 0,
                y REAL NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL DEFAULT (datetime('now')),
                updated_at TEXT NOT NULL DEFAULT (datetime('now'))
            );

            CREATE TABLE IF NOT EXISTS links (
                source_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                target_id INTEGER NOT NULL REFERENCES notes(id) ON DELETE CASCADE,
                PRIMARY KEY(source_id, target_id),
                CHECK(source_id != target_id)
            );

            CREATE TRIGGER IF NOT EXISTS notes_touch_updated_at
            AFTER UPDATE OF title, subtitle, content, x, y ON notes
            BEGIN
                UPDATE notes
                SET updated_at = datetime('now')
                WHERE id = NEW.id;
            END;
            "#,
        )?;

        Ok(())
    }

    fn list_notes(&self) -> anyhow::Result<Vec<Note>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, title, subtitle, content, x, y, updated_at
            FROM notes
            ORDER BY updated_at DESC
            "#,
        )?;

        let rows = stmt.query_map([], map_note_row)?;
        let notes = rows.collect::<Result<Vec<_>, _>>()?;

        Ok(notes)
    }

    fn get_note(&self, id: i64) -> anyhow::Result<Option<Note>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT id, title, subtitle, content, x, y, updated_at
            FROM notes
            WHERE id = ?1
            "#,
        )?;

        stmt.query_row([id], map_note_row)
            .optional()
            .map_err(Into::into)
    }

    fn note_exists(&self, id: i64) -> anyhow::Result<bool> {
        let exists = self.conn.query_row(
            "SELECT EXISTS(SELECT 1 FROM notes WHERE id = ?1)",
            [id],
            |row| row.get::<_, i64>(0),
        )? == 1;

        Ok(exists)
    }

    fn list_links(&self) -> anyhow::Result<Vec<Link>> {
        let mut stmt = self.conn.prepare(
            r#"
            SELECT source_id, target_id
            FROM links
            ORDER BY source_id ASC, target_id ASC
            "#,
        )?;

        let rows = stmt.query_map([], |row| {
            Ok(Link {
                source_id: row.get(0)?,
                target_id: row.get(1)?,
            })
        })?;

        let links = rows.collect::<Result<Vec<_>, _>>()?;
        Ok(links)
    }

    fn graph(&self) -> anyhow::Result<GraphResponse> {
        Ok(GraphResponse {
            notes: self.list_notes()?,
            links: self.list_links()?,
        })
    }

    fn create_note(&mut self, payload: CreateNoteRequest) -> anyhow::Result<Note> {
        let title = payload.title.trim();
        if title.is_empty() {
            return Err(anyhow!("title cannot be empty"));
        }

        let subtitle = payload.subtitle.unwrap_or_default();
        let content = payload.content.unwrap_or_default();

        let (x, y) = match (payload.x, payload.y) {
            (Some(x), Some(y)) => (x, y),
            _ => self.default_spawn_position()?,
        };

        self.conn.execute(
            r#"
            INSERT INTO notes (title, subtitle, content, x, y)
            VALUES (?1, ?2, ?3, ?4, ?5)
            "#,
            params![title, subtitle, content, x, y],
        )?;

        let id = self.conn.last_insert_rowid();
        let note = self
            .get_note(id)?
            .ok_or_else(|| anyhow!("inserted note could not be read"))?;

        if let Some(related_ids) = payload.related_ids {
            for related_id in related_ids {
                if related_id != id {
                    self.upsert_link_raw(id, related_id)?;
                }
            }
        }

        self.search.upsert_note(&note)?;

        Ok(note)
    }

    fn default_spawn_position(&self) -> anyhow::Result<(f64, f64)> {
        let count = self
            .conn
            .query_row("SELECT COUNT(*) FROM notes", [], |row| row.get::<_, i64>(0))?
            as usize;

        let ring = (count / 8) + 1;
        let slot = count % 8;
        let angle = (slot as f64 / 8.0) * std::f64::consts::TAU;
        let radius = (ring as f64) * 140.0;

        Ok((radius * angle.cos(), radius * angle.sin()))
    }

    fn update_note(&mut self, id: i64, payload: UpdateNoteRequest) -> anyhow::Result<Note> {
        if payload.title.trim().is_empty() {
            return Err(anyhow!("title cannot be empty"));
        }

        let updated = self.conn.execute(
            r#"
            UPDATE notes
            SET title = ?1,
                subtitle = ?2,
                content = ?3,
                x = ?4,
                y = ?5
            WHERE id = ?6
            "#,
            params![
                payload.title.trim(),
                payload.subtitle,
                payload.content,
                payload.x,
                payload.y,
                id
            ],
        )?;

        if updated == 0 {
            return Err(anyhow!("note {id} not found"));
        }

        if let Some(related_ids) = payload.related_ids {
            self.sync_related_links(id, &related_ids)?;
        }

        let note = self
            .get_note(id)?
            .ok_or_else(|| anyhow!("updated note {id} not found"))?;

        self.search.upsert_note(&note)?;

        Ok(note)
    }

    fn update_note_position(
        &mut self,
        id: i64,
        payload: UpdatePositionRequest,
    ) -> anyhow::Result<Note> {
        let updated = self.conn.execute(
            r#"
            UPDATE notes
            SET x = ?1,
                y = ?2
            WHERE id = ?3
            "#,
            params![payload.x, payload.y, id],
        )?;

        if updated == 0 {
            return Err(anyhow!("note {id} not found"));
        }

        let note = self
            .get_note(id)?
            .ok_or_else(|| anyhow!("updated note {id} not found"))?;
        Ok(note)
    }

    fn delete_note(&mut self, id: i64) -> anyhow::Result<bool> {
        let affected = self.conn.execute("DELETE FROM notes WHERE id = ?1", [id])?;
        if affected > 0 {
            self.search.delete_note(id)?;
            Ok(true)
        } else {
            Ok(false)
        }
    }

    fn create_link(&mut self, payload: LinkRequest) -> anyhow::Result<Link> {
        self.upsert_link_raw(payload.source_id, payload.target_id)
    }

    fn delete_link(&mut self, payload: LinkRequest) -> anyhow::Result<bool> {
        let (source_id, target_id) = normalize_edge(payload.source_id, payload.target_id)?;
        let deleted = self.conn.execute(
            "DELETE FROM links WHERE source_id = ?1 AND target_id = ?2",
            params![source_id, target_id],
        )?;

        Ok(deleted > 0)
    }

    fn upsert_link_raw(&self, a: i64, b: i64) -> anyhow::Result<Link> {
        let (source_id, target_id) = normalize_edge(a, b)?;

        if !self.note_exists(source_id)? || !self.note_exists(target_id)? {
            return Err(anyhow!("both notes must exist before linking"));
        }

        self.conn.execute(
            r#"
            INSERT OR IGNORE INTO links (source_id, target_id)
            VALUES (?1, ?2)
            "#,
            params![source_id, target_id],
        )?;

        Ok(Link {
            source_id,
            target_id,
        })
    }

    fn sync_related_links(&mut self, note_id: i64, related_ids: &[i64]) -> anyhow::Result<()> {
        let mut desired = HashSet::new();
        for related_id in related_ids {
            if *related_id == note_id {
                continue;
            }
            if self.note_exists(*related_id)? {
                desired.insert(normalize_edge(note_id, *related_id)?);
            }
        }

        let mut stmt = self.conn.prepare(
            r#"
            SELECT source_id, target_id
            FROM links
            WHERE source_id = ?1 OR target_id = ?1
            "#,
        )?;

        let current_rows = stmt.query_map([note_id], |row| {
            Ok((row.get::<_, i64>(0)?, row.get::<_, i64>(1)?))
        })?;

        let current = current_rows.collect::<Result<HashSet<_>, _>>()?;

        for edge in current.difference(&desired) {
            self.conn.execute(
                "DELETE FROM links WHERE source_id = ?1 AND target_id = ?2",
                params![edge.0, edge.1],
            )?;
        }

        for edge in desired.difference(&current) {
            self.conn.execute(
                "INSERT OR IGNORE INTO links (source_id, target_id) VALUES (?1, ?2)",
                params![edge.0, edge.1],
            )?;
        }

        Ok(())
    }

    fn search_notes(&self, query: &str, limit: usize) -> anyhow::Result<Vec<Note>> {
        let query = query.trim();
        if query.is_empty() {
            return Ok(Vec::new());
        }

        let ids = self.search.search_ids(query, limit)?;
        if !ids.is_empty() {
            let mut results = Vec::with_capacity(ids.len());
            for id in ids {
                if let Some(note) = self.get_note(id)? {
                    results.push(note);
                }
            }
            return Ok(results);
        }

        let sql = r#"
            SELECT id, title, subtitle, content, x, y, updated_at
            FROM notes
            WHERE title LIKE ?1 OR subtitle LIKE ?1 OR content LIKE ?1
            ORDER BY updated_at DESC
            LIMIT ?2
        "#;
        let term = format!("%{query}%");

        let mut stmt = self.conn.prepare(sql)?;
        let rows = stmt.query_map(params![term, limit as i64], map_note_row)?;
        Ok(rows.collect::<Result<Vec<_>, _>>()?)
    }

    fn auto_layout(&mut self) -> anyhow::Result<GraphResponse> {
        let notes = self.list_notes()?;
        if notes.is_empty() {
            return self.graph();
        }

        let links = self.list_links()?;

        let mut ids = notes.iter().map(|n| n.id).collect::<Vec<_>>();
        ids.sort_by_key(|id| {
            let degree = links
                .iter()
                .filter(|edge| edge.source_id == *id || edge.target_id == *id)
                .count();
            Reverse(degree)
        });

        let tx = self.conn.transaction()?;

        let mut cursor = 0usize;
        let mut ring = 0usize;

        while cursor < ids.len() {
            if ring == 0 {
                let id = ids[cursor];
                tx.execute("UPDATE notes SET x = 0, y = 0 WHERE id = ?1", params![id])?;
                cursor += 1;
                ring += 1;
                continue;
            }

            let slots = ring * 6;
            let radius = ring as f64 * 180.0;

            for slot in 0..slots {
                if cursor >= ids.len() {
                    break;
                }

                let angle = (slot as f64 / slots as f64) * std::f64::consts::TAU;
                let x = radius * angle.cos();
                let y = radius * angle.sin();

                tx.execute(
                    "UPDATE notes SET x = ?1, y = ?2 WHERE id = ?3",
                    params![x, y, ids[cursor]],
                )?;

                cursor += 1;
            }

            ring += 1;
        }

        tx.commit()?;

        self.graph()
    }
}

fn map_note_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<Note> {
    Ok(Note {
        id: row.get(0)?,
        title: row.get(1)?,
        subtitle: row.get(2)?,
        content: row.get(3)?,
        x: row.get(4)?,
        y: row.get(5)?,
        updated_at: row.get(6)?,
    })
}

fn normalize_edge(a: i64, b: i64) -> anyhow::Result<(i64, i64)> {
    if a == b {
        return Err(anyhow!("a note cannot link to itself"));
    }

    if a < b {
        Ok((a, b))
    } else {
        Ok((b, a))
    }
}

struct SearchIndex {
    index: Index,
    writer: IndexWriter,
    reader: IndexReader,
    id_field: Field,
    title_field: Field,
    subtitle_field: Field,
    content_field: Field,
}

impl SearchIndex {
    fn open(index_dir: &FsPath) -> anyhow::Result<Self> {
        std::fs::create_dir_all(index_dir)?;

        let schema = Self::build_schema();
        let index = if index_dir.join("meta.json").exists() {
            Index::open_in_dir(index_dir)?
        } else {
            Index::create_in_dir(index_dir, schema)?
        };

        let schema = index.schema();
        let id_field = schema
            .get_field("id")
            .map_err(|_| anyhow!("search schema missing id field"))?;
        let title_field = schema
            .get_field("title")
            .map_err(|_| anyhow!("search schema missing title field"))?;
        let subtitle_field = schema
            .get_field("subtitle")
            .map_err(|_| anyhow!("search schema missing subtitle field"))?;
        let content_field = schema
            .get_field("content")
            .map_err(|_| anyhow!("search schema missing content field"))?;

        let writer = index.writer(25_000_000)?;
        let reader = index.reader()?;

        Ok(Self {
            index,
            writer,
            reader,
            id_field,
            title_field,
            subtitle_field,
            content_field,
        })
    }

    fn build_schema() -> Schema {
        let mut schema_builder = Schema::builder();
        schema_builder.add_u64_field("id", STORED | INDEXED);
        schema_builder.add_text_field("title", TEXT | STORED);
        schema_builder.add_text_field("subtitle", TEXT | STORED);
        schema_builder.add_text_field("content", TEXT | STORED);
        schema_builder.build()
    }

    fn rebuild(&mut self, notes: &[Note]) -> anyhow::Result<()> {
        self.writer.delete_all_documents()?;
        for note in notes {
            self.writer.add_document(doc!(
                self.id_field => note.id as u64,
                self.title_field => note.title.clone(),
                self.subtitle_field => note.subtitle.clone(),
                self.content_field => note.content.clone(),
            ))?;
        }
        self.writer.commit()?;
        self.reader.reload()?;
        Ok(())
    }

    fn upsert_note(&mut self, note: &Note) -> anyhow::Result<()> {
        self.writer
            .delete_term(Term::from_field_u64(self.id_field, note.id as u64));
        self.writer.add_document(doc!(
            self.id_field => note.id as u64,
            self.title_field => note.title.clone(),
            self.subtitle_field => note.subtitle.clone(),
            self.content_field => note.content.clone(),
        ))?;
        self.writer.commit()?;
        self.reader.reload()?;
        Ok(())
    }

    fn delete_note(&mut self, id: i64) -> anyhow::Result<()> {
        self.writer
            .delete_term(Term::from_field_u64(self.id_field, id as u64));
        self.writer.commit()?;
        self.reader.reload()?;
        Ok(())
    }

    fn search_ids(&self, raw_query: &str, limit: usize) -> anyhow::Result<Vec<i64>> {
        let query = raw_query.trim();
        if query.is_empty() {
            return Ok(Vec::new());
        }

        let parser = QueryParser::for_index(
            &self.index,
            vec![self.title_field, self.subtitle_field, self.content_field],
        );

        let escaped = query.replace('"', " ");
        let tantivy_query = parser
            .parse_query(query)
            .or_else(|_| parser.parse_query(&format!("\"{escaped}\"")))?;

        let searcher = self.reader.searcher();
        let docs = searcher.search(&tantivy_query, &TopDocs::with_limit(limit))?;

        let mut ids = Vec::with_capacity(docs.len());
        for (_score, address) in docs {
            let doc: TantivyDocument = searcher.doc(address)?;
            if let Some(value) = doc
                .get_first(self.id_field)
                .and_then(|field| field.as_u64())
            {
                ids.push(value as i64);
            }
        }

        Ok(ids)
    }
}

fn lock_store<'a>(state: &'a Arc<Mutex<Store>>) -> Result<MutexGuard<'a, Store>, ApiError> {
    state
        .lock()
        .map_err(|_| ApiError::Internal(anyhow!("store mutex poisoned")))
}

async fn health() -> StatusCode {
    StatusCode::OK
}

async fn get_graph(
    State(state): State<Arc<Mutex<Store>>>,
) -> Result<Json<GraphResponse>, ApiError> {
    let store = lock_store(&state)?;
    Ok(Json(store.graph()?))
}

async fn get_note(
    Path(id): Path<i64>,
    State(state): State<Arc<Mutex<Store>>>,
) -> Result<Json<Note>, ApiError> {
    let store = lock_store(&state)?;
    match store.get_note(id)? {
        Some(note) => Ok(Json(note)),
        None => Err(ApiError::NotFound(format!("note {id} not found"))),
    }
}

async fn create_note(
    State(state): State<Arc<Mutex<Store>>>,
    Json(payload): Json<CreateNoteRequest>,
) -> Result<(StatusCode, Json<Note>), ApiError> {
    let mut store = lock_store(&state)?;
    let note = store.create_note(payload).map_err(map_store_error)?;
    Ok((StatusCode::CREATED, Json(note)))
}

async fn update_note(
    Path(id): Path<i64>,
    State(state): State<Arc<Mutex<Store>>>,
    Json(payload): Json<UpdateNoteRequest>,
) -> Result<Json<Note>, ApiError> {
    let mut store = lock_store(&state)?;
    let note = store.update_note(id, payload).map_err(map_store_error)?;
    Ok(Json(note))
}

async fn update_note_position(
    Path(id): Path<i64>,
    State(state): State<Arc<Mutex<Store>>>,
    Json(payload): Json<UpdatePositionRequest>,
) -> Result<Json<Note>, ApiError> {
    let mut store = lock_store(&state)?;
    let note = store
        .update_note_position(id, payload)
        .map_err(map_store_error)?;
    Ok(Json(note))
}

async fn delete_note_handler(
    Path(id): Path<i64>,
    State(state): State<Arc<Mutex<Store>>>,
) -> Result<StatusCode, ApiError> {
    let mut store = lock_store(&state)?;
    if store.delete_note(id)? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound(format!("note {id} not found")))
    }
}

async fn create_link(
    State(state): State<Arc<Mutex<Store>>>,
    Json(payload): Json<LinkRequest>,
) -> Result<(StatusCode, Json<Link>), ApiError> {
    let mut store = lock_store(&state)?;
    let link = store.create_link(payload).map_err(map_store_error)?;
    Ok((StatusCode::CREATED, Json(link)))
}

async fn delete_link_handler(
    State(state): State<Arc<Mutex<Store>>>,
    Json(payload): Json<LinkRequest>,
) -> Result<StatusCode, ApiError> {
    let mut store = lock_store(&state)?;
    if store.delete_link(payload)? {
        Ok(StatusCode::NO_CONTENT)
    } else {
        Err(ApiError::NotFound("link not found".to_string()))
    }
}

async fn search_notes(
    State(state): State<Arc<Mutex<Store>>>,
    Query(query): Query<SearchQuery>,
) -> Result<Json<SearchResponse>, ApiError> {
    let limit = query.limit.unwrap_or(20).clamp(1, 100);
    let store = lock_store(&state)?;
    let results = store
        .search_notes(&query.q, limit)
        .map_err(map_store_error)?;
    Ok(Json(SearchResponse { results }))
}

async fn auto_layout(
    State(state): State<Arc<Mutex<Store>>>,
) -> Result<Json<GraphResponse>, ApiError> {
    let mut store = lock_store(&state)?;
    Ok(Json(store.auto_layout()?))
}

fn map_store_error(err: anyhow::Error) -> ApiError {
    let message = format!("{err:#}");
    if message.contains("not found") {
        ApiError::NotFound(message)
    } else if message.contains("cannot") || message.contains("must") || message.contains("invalid")
    {
        ApiError::BadRequest(message)
    } else {
        ApiError::Internal(err)
    }
}
