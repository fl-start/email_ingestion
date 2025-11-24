import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:email_ingestion/email_ingestion.dart';
import 'package:hashed_kv_store/hashed_kv_store.dart';
import 'package:parallel_dio_pool/parallel_dio_pool.dart';
import 'package:multi_identity_drift/multi_identity_drift.dart';
import 'package:dio/dio.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const EmailApp());
}

class EmailApp extends StatelessWidget {
  const EmailApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Email Ingestion Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const EmailIngestionScreen(),
    );
  }
}

class EmailIngestionScreen extends StatefulWidget {
  const EmailIngestionScreen({super.key});

  @override
  State<EmailIngestionScreen> createState() => _EmailIngestionScreenState();
}

class _EmailIngestionScreenState extends State<EmailIngestionScreen> {
  EmailIngestionPipeline? _pipeline;
  InfiniteScrollController? _scrollController;
  IdentityDbHandle<EmailDatabase>? _dbHandle;
  ConcurrentDbClient? _dbClient;
  bool _initialized = false;
  String? _error;
  int _ingestedCount = 0;
  int _totalEmails = 0;
  bool _isIngesting = false;
  Timer? _countRefreshTimer;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    try {
      print('Starting initialization...');
      final appDir = await getApplicationDocumentsDirectory();
      print('App dir: ${appDir.path}');

      final dbRoot = Directory('${appDir.path}/email_db');
      final kvRoot = Directory('${appDir.path}/email_kv');
      await kvRoot.create(recursive: true);
      print('KV root created');

      // Initialize KV store
      print('Initializing KV store...');
      final kvStore = await MultiIsolateKvStoreClient.spawn(
        rootDirPath: kvRoot.path,
        numWorkers: 4,
      ).timeout(const Duration(seconds: 10));
      print('KV store initialized');

      // Initialize database
      print('Initializing database...');
      final secureStorage = FileSecureStorage(
        File('${appDir.path}/email_secure_storage.json'),
      );
      final multiDb = MultiIdentityDrift(
        rootDir: dbRoot,
        secureStorage: secureStorage,
      );

      // Create identity if needed
      try {
        await multiDb
            .createIdentity(
              identityId: 'email-user',
              label: 'Email User',
            )
            .timeout(const Duration(seconds: 5));
        print('Identity created');
      } catch (e) {
        // Identity might already exist - that's fine
        print('Identity already exists or error: $e');
      }

      // Close existing database handle if any
      if (_dbHandle != null) {
        try {
          await _dbHandle!.close();
        } catch (e) {
          print('Error closing existing db handle: $e');
        }
      }

      // Open database FIRST to ensure it's created and schema is initialized
      print('Opening database...');
      _dbHandle = await multiDb
          .openIdentity<EmailDatabase>(
            identityId: 'email-user',
            dbFactory: (conn) => EmailDatabase(conn),
          )
          .timeout(const Duration(seconds: 10));
      print('Database opened');

      // Enable WAL mode for better concurrency (allows multiple readers + one writer)
      try {
        await _dbHandle!.db.customStatement('PRAGMA journal_mode=WAL;');
        print('WAL mode enabled');
      } catch (e) {
        // If WAL mode fails, continue anyway - database will still work
        print('Warning: Could not enable WAL mode: $e');
      }

      // Ensure schema is created by running a simple query
      try {
        await _dbHandle!.db.getEmailCount().timeout(const Duration(seconds: 5));
        print('Schema check passed');
      } catch (e) {
        // Schema will be created on first insert, that's fine
        print('Schema check: $e');
      }

      // Get the database file path
      final dbFilePath =
          File(dbRoot.path).uri.resolve('email-user.sqlite').toFilePath();
      print('DB file path: $dbFilePath');

      // Wait a moment for database to be fully ready
      await Future.delayed(const Duration(milliseconds: 200));

      // Initialize scroll controller with concurrent DB client
      print('Initializing ConcurrentDbClient...');
      _dbClient = ConcurrentDbClient(
        dbPath: dbFilePath,
        workerCount: 4,
      );
      await _dbClient!.start().timeout(const Duration(seconds: 15));
      print('ConcurrentDbClient started');

      print('Initializing InfiniteScrollController...');
      _scrollController = InfiniteScrollController(db: _dbClient!);
      await _scrollController!.init().timeout(const Duration(seconds: 10));
      print('InfiniteScrollController initialized');

      // Initialize Dio client
      print('Initializing Dio client...');
      final dioClient = ParallelDioClient(
        config: const ParallelDioConfig(
          baseUrl: 'http://localhost:3000',
          initialParallelism: 8,
          maxParallelism: 32,
        ),
      );
      print('Dio client initialized');

      // Create pipeline
      _pipeline = EmailIngestionPipeline(
        dioClient: dioClient,
        kvStore: kvStore,
        dbHandle: _dbHandle!,
        baseUrl: 'http://localhost:3000',
      );
      print('Pipeline created');

      if (mounted) {
        setState(() {
          _initialized = true;
          _totalEmails = _scrollController!.totalCount.value;
        });
        print('Initialization complete! Total emails: $_totalEmails');
        
        // Start periodic count refresh to update UI as emails are ingested
        _startCountRefreshTimer();
      }
    } catch (e, st) {
      print('Initialization error: $e');
      print('Stack trace: $st');
      if (mounted) {
        setState(() {
          _error = 'Initialization failed: $e\n\nStack trace:\n$st';
        });
      }
    }
  }

  void _startCountRefreshTimer() {
    // Refresh count periodically to update UI as emails are ingested
    // Use longer interval during active ingestion to reduce lock contention
    _countRefreshTimer?.cancel();
    _countRefreshTimer = Timer.periodic(
      _isIngesting 
        ? const Duration(milliseconds: 2000) // Slower during ingestion
        : const Duration(milliseconds: 1000), // Normal speed otherwise
      (_) async {
        if (_scrollController != null && _dbClient != null && mounted) {
          try {
            final oldCount = _scrollController!.totalCount.value;
            // Always refresh during ingestion to show new emails as they appear
            // Also refresh if not ingesting and user is at end
            await _scrollController!.refreshCount(refreshIfAtEnd: true);
            final newCount = _scrollController!.totalCount.value;
            
            if (newCount != oldCount && mounted) {
              setState(() {
                _totalEmails = newCount;
              });
            }
          } catch (e) {
            // Silently handle errors - refreshCount already handles retries internally
            // Only log unexpected errors
            if (!e.toString().contains('locked')) {
              print('Error refreshing count: $e');
            }
          }
        }
      },
    );
  }

  Future<void> _fetchAndIngestEmails() async {
    if (_pipeline == null || _isIngesting) return;

    setState(() {
      _isIngesting = true;
      _ingestedCount = 0;
      _error = null;
    });

    // Restart timer with slower refresh rate during ingestion
    _startCountRefreshTimer();

    // Run ingestion in background - don't await, let it run asynchronously
    _ingestEmailsInBackground();
  }

  Future<void> _ingestEmailsInBackground() async {
    try {
      // Fetch email list from server
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      final response = await dio.get('/emails', queryParameters: {
        'page': 1,
        'limit': 100000, // Fetch all emails for demo
      });

      final emailsData = response.data['emails'] as List;
      final emails = emailsData
          .map((e) => EmailMetadata.fromJson(e as Map<String, dynamic>))
          .toList();

      print('Starting background ingestion of ${emails.length} emails...');

      // Ingest emails in background - stream results
      final resultsStream = _pipeline!.ingestEmails(emails);
      int successCount = 0;
      
      await for (final result in resultsStream) {
        if (result.success) {
          successCount++;
          // Update UI periodically (every 10 emails) to avoid too many rebuilds
          if (successCount % 10 == 0 || successCount == emails.length) {
            if (mounted) {
              setState(() {
                _ingestedCount = successCount;
              });
            }
          }
        }
      }

      // Final update
      if (mounted) {
        setState(() {
          _ingestedCount = successCount;
          _isIngesting = false;
        });
      }

      // Restart timer with normal refresh rate after ingestion
      _startCountRefreshTimer();

      // Refresh scroll controller to show new emails (with retry for locks)
      if (_scrollController != null) {
        const maxRetries = 3;
        for (int attempt = 0; attempt < maxRetries; attempt++) {
          try {
            await _scrollController!.init();
            if (mounted) {
              setState(() {
                _totalEmails = _scrollController!.totalCount.value;
              });
            }
            break; // Success
          } catch (e) {
            final errorStr = e.toString();
            if (errorStr.contains('database is locked') && attempt < maxRetries - 1) {
              // Wait and retry
              await Future.delayed(Duration(milliseconds: 100 * (attempt + 1)));
              continue;
            }
            // Log non-lock errors or final failure
            print('Error refreshing scroll controller: $e');
            break;
          }
        }
      }

      print('Background ingestion complete! Ingested: $successCount / ${emails.length}');
    } catch (e, st) {
      print('Background ingestion error: $e\n$st');
      if (mounted) {
        setState(() {
          _error = 'Ingestion failed: $e';
          _isIngesting = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _countRefreshTimer?.cancel();
    _dbClient?.dispose();
    _dbHandle?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Email Ingestion Demo'),
      ),
      body: _initialized
          ? Column(
              children: [
                // Control panel
                Padding(
                  padding: const EdgeInsets.all(0),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          ElevatedButton(
                            onPressed: _isIngesting ? null : _fetchAndIngestEmails,
                            child: _isIngesting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('Fetch & Ingest Emails'),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Ingested: $_ingestedCount'),
                              Text('Total: $_totalEmails'),
                              if (_isIngesting)
                                const Text(
                                  'Ingesting in background...',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic,
                                    color: Colors.blue,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            _error!,
                            style: const TextStyle(color: Colors.red),
                          ),
                        ),
                    ],
                  ),
                ),
                // Infinite scroll view
                if (_scrollController != null)
                  Expanded(
                    child: InfiniteEmailScrollView(
                      controller: _scrollController!,
                    ),
                  ),
              ],
            )
          : Center(
              child: _error != null
                  ? Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(_error!),
                        ElevatedButton(
                          onPressed: _initialize,
                          child: const Text('Retry'),
                        ),
                      ],
                    )
                  : const CircularProgressIndicator(),
            ),
    );
  }
}
