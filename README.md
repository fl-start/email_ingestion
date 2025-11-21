# Email Ingestion Package

A composable email ingestion pipeline: `dio.pipe(kv).pipe(db)` with infinite scroll support.

> **Note**: See the main [README.md](../README.md) in the root directory for complete setup instructions and system overview.

## Features

- **Composable Pipeline**: HTTP → KV Store → Database in a single pipeline
- **Concurrent Database Queries**: Uses multiple isolates for parallel SELECT queries
- **Infinite Scroll**: 3-window strategy (50 visible, 100 top/bottom buffers)
- **Smooth Navigation**: Scroll, drag, click, and keyboard navigation support

## Architecture

### Email Ingestion Pipeline

```
HTTP Request → KV Store (body) → Database (metadata)
```

The pipeline:
1. Fetches email body from server using `parallel_dio_pool`
2. Streams body to `hashed_kv_store` (stored on disk with Message-ID as key)
3. Inserts metadata to SQLite using `multi_identity_drift` (Message-ID, From, To, Subject, Received_at)

### Concurrent Database Queries

Uses multiple worker isolates for parallel SELECT queries:
- Each isolate has its own SQLite connection
- Queries are distributed across workers
- Results use `TransferableTypedData` for efficient transfer

### Infinite Scroll

- **Visible Window**: 50 emails
- **Top Buffer**: 100 emails
- **Bottom Buffer**: 100 emails
- **Memory**: O(1) - only keeps 3 windows in memory
- **Navigation**: Scroll, drag slider, click slider, keyboard (PageUp/Down, Home/End)

## Usage

### 1. Setup NodeJS Server

```bash
cd email_server
npm install
npm start

# In another terminal, populate emails
curl -X POST http://localhost:3000/populate -H "Content-Type: application/json" -d '{"count": 100000}'
```

### 2. Run Flutter App

```bash
cd email_ingestion/example
flutter pub get
flutter run
```

### 3. Use in Your App

```dart
// Initialize pipeline
final pipeline = EmailIngestionPipeline(
  dioClient: dioClient,
  kvStore: kvStore,
  dbHandle: dbHandle,
  baseUrl: 'http://localhost:3000',
);

// Ingest emails
final resultsStream = pipeline.ingestEmails(emails);
await for (final result in resultsStream) {
  if (result.success) {
    print('Ingested: ${result.messageId}');
  }
}

// Initialize infinite scroll
final dbClient = ConcurrentDbClient(
  dbPath: dbPath,
  workerCount: 4,
);
await dbClient.start();

final controller = InfiniteScrollController(db: dbClient);
await controller.init();

// Use in widget
InfiniteEmailScrollView(controller: controller)
```

## Database Schema

```sql
CREATE TABLE emails (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  messageId TEXT UNIQUE NOT NULL,
  fromAddr TEXT NOT NULL,
  toAddr TEXT NOT NULL,
  subject TEXT NOT NULL,
  receivedAt DATETIME NOT NULL
);
```

Note: Email body is stored in KV store, not in database.

## Package Structure

- `email_schema.dart` - Drift database schema
- `email_pipeline.dart` - Composable pipeline (dio → kv → db)
- `concurrent_db_client.dart` - Concurrent SELECT queries using isolates
- `infinite_scroll_controller.dart` - 3-window infinite scroll controller
- `infinite_scroll_widget.dart` - Flutter widget for infinite scroll
- `kv_adapter.dart` - Adapter for hashed_kv_store

## Dependencies

- `hashed_kv_store` - Multi-isolate KV store
- `parallel_dio_pool` - Parallel HTTP requests
- `multi_identity_drift` - Multi-identity database manager
- `signals` - Reactive state management

