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

  Future<void> _fetchAndIngestEmails() async {
    if (_pipeline == null) return;

    setState(() {
      _ingestedCount = 0;
    });

    try {
      // Fetch email list from server
      final dio = Dio(BaseOptions(baseUrl: 'http://localhost:3000'));
      final response = await dio.get('/emails', queryParameters: {
        'page': 1,
        'limit': 100000, // Fetch first 1000 for demo
      });

      final emailsData = response.data['emails'] as List;
      final emails = emailsData
          .map((e) => EmailMetadata.fromJson(e as Map<String, dynamic>))
          .toList();

      // Ingest emails
      final resultsStream = _pipeline!.ingestEmails(emails);
      await for (final result in resultsStream) {
        if (result.success) {
          setState(() {
            _ingestedCount++;
          });
        }
      }

      // Refresh scroll controller
      await _scrollController?.init();
      setState(() {
        _totalEmails = _scrollController?.totalCount.value ?? 0;
      });
    } catch (e) {
      setState(() {
        _error = 'Ingestion failed: $e';
      });
    }
  }

  @override
  void dispose() {
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
                            onPressed: _fetchAndIngestEmails,
                            child: const Text('Fetch & Ingest Emails'),
                          ),
                          Text('Ingested: $_ingestedCount'),
                          Text('Total: $_totalEmails'),
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
