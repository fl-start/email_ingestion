# Email Ingestion System with Infinite Scroll

A complete email ingestion and display system built with Flutter, Node.js, and Dart. Fetches emails from a server, stores them efficiently, and displays them in a smooth infinite scroll interface.

## What This System Does

1. **Fetches emails** from a Node.js server (supports 100K+ emails)
2. **Stores email bodies** on disk using a key-value store (Message-ID as key)
3. **Stores email metadata** in SQLite database (From, To, Subject, Received date)
4. **Displays emails** in a smooth infinite scroll with 3-window buffering strategy
5. **Queries database concurrently** using multiple isolates for performance

## Architecture Overview

```
┌─────────────────┐
│  NodeJS Server  │  (100K emails, REST API)
└────────┬────────┘
         │ HTTP GET /emails/:id/body
         ▼
┌─────────────────┐
│ parallel_dio    │  (Parallel HTTP downloads using all isolates)
│ _pool           │
└────────┬────────┘
         │ Stream body
         ▼
┌─────────────────┐
│ hashed_kv_store │  (Body stored on disk, Message-ID as key)
└────────┬────────┘
         │ If storage succeeds
         ▼
┌─────────────────┐
│ multi_identity  │  (Metadata: Message-ID, From, To, Subject, Received_at)
│ _drift          │
└─────────────────┘

┌─────────────────┐
│ ConcurrentDb    │  (4 worker isolates, parallel SELECT queries)
│ Client          │
└────────┬────────┘
         │ Query results
         ▼
┌─────────────────┐
│ Infinite Scroll │  (50 visible + 100 top + 100 bottom = O(1) memory)
│ Widget          │
└─────────────────┘
```

### Key Components

#### 1. Email Ingestion Pipeline (`dio.pipe(kv).pipe(db)`)
- **HTTP Fetch**: Uses `parallel_dio_pool` to download email bodies in parallel across all available isolates
- **KV Storage**: Streams body to `hashed_kv_store` on disk (SHA256-based, Message-ID as key)
- **Database Insert**: If KV storage succeeds, inserts metadata to SQLite via `multi_identity_drift`
- **Composable**: Each step is independent and can be swapped/reused

#### 2. Concurrent Database Queries
- **4 Worker Isolates**: Each has its own SQLite connection
- **Parallel SELECTs**: Queries distributed across workers using round-robin
- **TransferableTypedData**: Results transferred efficiently between isolates
- **Read-Only**: Query workers use read-only connections

#### 3. Infinite Scroll (3-Window Strategy)
- **Visible Window**: 50 emails currently shown
- **Top Buffer**: 100 emails above visible (pre-loaded)
- **Bottom Buffer**: 100 emails below visible (pre-loaded)
- **Memory**: O(1) - only 250 emails in memory at any time
- **Navigation**:
  - **Scroll**: Mouse wheel (debounced)
  - **Drag**: Slider drag (debounced)
  - **Click**: Slider click (instant jump)
  - **Keyboard**: PageUp/Down, Home/End

## Setup Instructions

### Prerequisites
- Node.js (v14+)
- Flutter SDK
- Dart SDK

### Step 1: Start Email Server

```bash
cd email_server
npm install
npm start
```

Server runs on `http://localhost:3000`

**Verify**: Open `http://localhost:3000/emails/count` in browser

### Step 2: Populate Emails

**Option A: In-Memory (Quick)**
```bash
curl -X POST http://localhost:3000/populate \
  -H "Content-Type: application/json" \
  -d '{"count": 100000}'
```

**Option B: PostgreSQL**
```bash
# Setup database
createdb emails

# Set environment
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=emails
export DB_USER=postgres
export DB_PASSWORD=postgres

# Populate
cd email_server
npm run populate
```

### Step 3: Generate Drift Schema

```bash
cd email_ingestion
dart pub get
dart run build_runner build --delete-conflicting-outputs
```

This generates `lib/src/email_schema.g.dart` required by Drift.

### Step 4: Run Flutter App

```bash
cd email_ingestion/example
flutter pub get
flutter run
```

## How It Works

### Email Ingestion Flow

1. **Fetch Email List**: App requests email metadata from server
2. **Parallel Downloads**: For each email, downloads body in parallel using all available isolates
3. **Stream to KV**: As body arrives, streams directly to disk storage (no memory buffering)
4. **Store Metadata**: If KV storage succeeds, inserts metadata row to SQLite
5. **Result Stream**: Returns results as they complete (not waiting for all)

### Database Query Flow

1. **Concurrent Workers**: 4 isolates each with own SQLite connection
2. **Query Distribution**: Queries sent to least-busy worker
3. **Parallel Execution**: Multiple SELECT queries run simultaneously
4. **Result Transfer**: Results serialized to JSON, wrapped in `TransferableTypedData`
5. **Main Isolate**: Receives fully parsed data (no JSON parsing on main thread)

### Infinite Scroll Flow

1. **Initial Load**: Fetches count, then loads first window (top + visible + bottom)
2. **Scroll Detection**: Monitors scroll position, calculates approximate index
3. **Window Shift**: When near top/bottom, shifts window and fetches new buffer
4. **Memory Management**: Only keeps 3 windows, purges old data
5. **Debouncing**: Scroll and drag actions debounced for smooth performance

## Usage

### In Your Flutter App

```dart
import 'package:email_ingestion/email_ingestion.dart';

// 1. Initialize pipeline
final pipeline = EmailIngestionPipeline(
  dioClient: dioClient,
  kvStore: kvStore,
  dbHandle: dbHandle,
  baseUrl: 'http://localhost:3000',
);

// 2. Fetch and ingest emails
final emails = await fetchEmailList(); // Your function
final resultsStream = pipeline.ingestEmails(emails);
await for (final result in resultsStream) {
  if (result.success) {
    print('Ingested: ${result.messageId}');
  }
}

// 3. Initialize infinite scroll
final dbClient = ConcurrentDbClient(
  dbPath: dbPath,
  workerCount: 4,
);
await dbClient.start();

final controller = InfiniteScrollController(db: dbClient);
await controller.init();

// 4. Use in widget
InfiniteEmailScrollView(controller: controller)
```

### Database Schema

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

**Note**: Email body is stored in KV store (on disk), not in database.

## Package Structure

### `email_ingestion/` Package

- **`email_schema.dart`** - Drift database schema definition
- **`email_pipeline.dart`** - Composable pipeline (HTTP → KV → DB)
- **`concurrent_db_client.dart`** - Concurrent SELECT queries using isolates
- **`infinite_scroll_controller.dart`** - 3-window infinite scroll logic
- **`infinite_scroll_widget.dart`** - Flutter widget for display
- **`kv_adapter.dart`** - Adapter for hashed_kv_store integration

### Dependencies

- **`hashed_kv_store`** - Multi-isolate key-value store for email bodies
- **`parallel_dio_pool`** - Parallel HTTP requests using all isolates
- **`multi_identity_drift`** - Multi-identity database manager
- **`signals`** - Reactive state management for UI

## Troubleshooting

### App Shows Infinite Loading

1. **Check Error Message**: App displays error if initialization fails
2. **Verify Server**: `curl http://localhost:3000/emails/count`
3. **Check Database**: Ensure database file is created
4. **Console Logs**: Check Flutter console for detailed errors

### Database Schema Errors

```bash
# Regenerate schema
cd email_ingestion
dart run build_runner build --delete-conflicting-outputs
```

### Server Not Starting

```bash
# Check port 3000
lsof -i :3000

# Verify Node.js
node --version
```

### Flutter Build Errors

```bash
# Clean and rebuild
cd email_ingestion/example
flutter clean
flutter pub get
flutter run
```

## Performance Characteristics

- **HTTP Downloads**: Parallel across all isolates (8-32 concurrent)
- **KV Storage**: Multi-isolate (4 workers)
- **Database Queries**: Concurrent SELECTs (4 isolates)
- **Memory Usage**: O(1) - only 250 emails in memory
- **Scrolling**: Smooth 60fps with debouncing
- **Query Cancellation**: In-flight queries cancelled on jump/drag

## Design Principles

1. **Composable**: `dio.pipe(kv).pipe(db)` - each component independent
2. **Concurrent**: All operations use isolates for parallelism
3. **Efficient**: Streaming I/O, O(1) memory, TransferableTypedData
4. **Type-Safe**: Full Drift type safety
5. **Self-Contained**: Each package is independent and reusable

## Next Steps

- Add email body preview from KV store
- Implement search/filtering
- Add email deletion
- Support pagination in server
- Add email attachments
- Implement email threading

## License

See individual package licenses.

