import 'dart:async';
import 'dart:math';
import 'package:signals/signals.dart';
import 'concurrent_db_client.dart';

/// Email DTO for UI
class EmailDto {
  final int id;
  final String messageId;
  final String fromAddr;
  final String toAddr;
  final String subject;
  final DateTime receivedAt;

  EmailDto({
    required this.id,
    required this.messageId,
    required this.fromAddr,
    required this.toAddr,
    required this.subject,
    required this.receivedAt,
  });

  factory EmailDto.fromMap(Map<String, dynamic> map) {
    return EmailDto(
      id: map['id'] as int,
      messageId: map['messageId'] as String,
      fromAddr: map['fromAddr'] as String,
      toAddr: map['toAddr'] as String,
      subject: map['subject'] as String,
      receivedAt: DateTime.parse(map['receivedAt'] as String),
    );
  }
}

/// Configuration for infinite scroll
class InfiniteScrollConfig {
  final int visibleCount;
  final int bufferCount;
  final double prefetchThresholdFactor;

  const InfiniteScrollConfig({
    this.visibleCount = 50,
    this.bufferCount = 100,
    this.prefetchThresholdFactor = 0.2,
  });
}

/// Controller for infinite scroll with 3-window strategy
class InfiniteScrollController {
  final ConcurrentDbClient db;
  final InfiniteScrollConfig config;

  // Signals
  final Signal<List<EmailDto>> topBuffer = signal(<EmailDto>[]);
  final Signal<List<EmailDto>> visible = signal(<EmailDto>[]);
  final Signal<List<EmailDto>> bottomBuffer = signal(<EmailDto>[]);
  final Signal<bool> isLoading = signal(false);
  final Signal<int> totalCount = signal(0);
  final Signal<int> firstVisibleIndex = signal(0);

  // Internal state
  int _visibleStartIndex = 0;
  final double rowExtent = 60.0; // Fixed row height in pixels
  final Debouncer _scrollDebouncer =
      Debouncer(const Duration(milliseconds: 40));
  final Debouncer _sliderDebouncer =
      Debouncer(const Duration(milliseconds: 120));

  Debouncer get sliderDebouncer => _sliderDebouncer;

  InfiniteScrollController({
    required this.db,
    this.config = const InfiniteScrollConfig(),
  });

  Future<void> init() async {
    isLoading.value = true;
    try {
      final count = await db.getEmailCount();
      totalCount.value = count;
      if (count > 0) {
        await _centerOnIndex(0);
      } else {
        // Empty database - set empty lists
        topBuffer.value = [];
        visible.value = [];
        bottomBuffer.value = [];
      }
    } catch (e) {
      // Handle errors gracefully
      totalCount.value = 0;
      topBuffer.value = [];
      visible.value = [];
      bottomBuffer.value = [];
      print('Error initializing scroll controller: $e');
    } finally {
      isLoading.value = false;
    }
  }

  /// Refresh the total count and optionally refresh visible window if at end
  /// Uses retry logic with exponential backoff to handle database locks
  Future<void> refreshCount({bool refreshIfAtEnd = false}) async {
    const maxRetries = 3;
    const initialDelay = Duration(milliseconds: 50);
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        final newCount = await db.getEmailCount();
        final oldCount = totalCount.value;
        totalCount.value = newCount;
        
        // If we went from 0 to having emails, or visible list is empty, refresh to show emails
        final shouldRefreshForNewEmails = (oldCount == 0 && newCount > 0) || 
                                          (visible.value.isEmpty && newCount > 0);
        
        // If count increased and user is at the end, refresh visible window
        final shouldRefreshAtEnd = refreshIfAtEnd && newCount > oldCount && oldCount > 0;
        
        if (shouldRefreshForNewEmails) {
          // First emails are being added - show them by centering on index 0
          try {
            await _centerOnIndex(0);
          } catch (e) {
            // Silently ignore errors when refreshing window - user can scroll manually
          }
        } else if (shouldRefreshAtEnd) {
          final lastVisibleIndex = _visibleStartIndex + visible.value.length;
          final isNearEnd = lastVisibleIndex >= oldCount - 5; // Within 5 items of end
          
          if (isNearEnd && newCount > oldCount) {
            // User is at end and new emails were added - refresh to show them
            // Use retry logic for this too
            try {
              await _centerOnIndex(_visibleStartIndex);
            } catch (e) {
              // Silently ignore errors when refreshing window - user can scroll manually
            }
          }
        }
        return; // Success, exit retry loop
      } catch (e) {
        final errorStr = e.toString();
        // Check if it's a database lock error
        if (errorStr.contains('database is locked') || errorStr.contains('locked')) {
          if (attempt < maxRetries - 1) {
            // Exponential backoff: 50ms, 100ms, 200ms
            final delay = Duration(milliseconds: initialDelay.inMilliseconds * (1 << attempt));
            await Future.delayed(delay);
            continue; // Retry
          }
          // Max retries reached, silently fail
          return;
        }
        // Not a lock error, rethrow
        print('Error refreshing count: $e');
        return;
      }
    }
  }

  int approximateIndexFromScroll({required double scrollOffset}) {
    return (scrollOffset / rowExtent)
        .floor()
        .clamp(0, max(0, totalCount.value - 1));
  }

  void onScrollPixels({
    required double scrollOffset,
    required double viewportExtent,
  }) {
    if (totalCount.value == 0) return;
    _scrollDebouncer.run(() async {
      await _handleScroll(scrollOffset: scrollOffset);
    });
  }

  Future<void> _handleScroll({required double scrollOffset}) async {
    if (totalCount.value == 0) return;

    // Calculate which item in the visible list we're currently viewing
    // scrollOffset is relative to the ListView (which shows only the visible window)
    final scrollIndex = (scrollOffset / rowExtent).floor();
    final clampedScrollIndex =
        scrollIndex.clamp(0, config.visibleCount - 1).toInt();

    // Calculate the global index
    final globalIndex = _visibleStartIndex + clampedScrollIndex;
    final clampedGlobalIndex =
        globalIndex.clamp(0, max(0, totalCount.value - 1)).toInt();
    firstVisibleIndex.value = clampedGlobalIndex;

    // Check if we need to shift the window
    // Shift when we're near the edges of the visible window
    final visibleShiftThreshold =
        config.visibleCount ~/ 3; // Shift at 1/3 from edges

    // Check if near top of visible window (scrolled up)
    if (clampedScrollIndex < visibleShiftThreshold && _visibleStartIndex > 0) {
      // Need to shift window up - center on a position above current
      final targetCenterIndex =
          max(0, _visibleStartIndex - config.bufferCount ~/ 2);
      await _centerOnIndex(targetCenterIndex);
      return;
    }

    // Check if near bottom of visible window (scrolled down)
    final itemsFromBottom = config.visibleCount - clampedScrollIndex;
    if (itemsFromBottom < visibleShiftThreshold &&
        _visibleStartIndex + config.visibleCount < totalCount.value) {
      // Need to shift window down - center on a position below current
      final targetCenterIndex = min(
        totalCount.value - 1,
        _visibleStartIndex + config.visibleCount + config.bufferCount ~/ 2,
      );
      await _centerOnIndex(targetCenterIndex);
      return;
    }
  }

  Future<void> jumpToFraction(double fraction) async {
    if (totalCount.value == 0) return;
    fraction = fraction.clamp(0.0, 1.0);
    final maxStart = max(0, totalCount.value - config.visibleCount);
    final index = (fraction * maxStart).round().clamp(0, maxStart);
    await _jumpToIndex(index);
  }

  Future<void> pageUp() async {
    final newIndex = max(0, firstVisibleIndex.value - config.visibleCount);
    await _jumpToIndex(newIndex);
  }

  Future<void> pageDown() async {
    final newIndex = min(
      max(0, totalCount.value - config.visibleCount),
      firstVisibleIndex.value + config.visibleCount,
    );
    await _jumpToIndex(newIndex);
  }

  Future<void> _jumpToIndex(int index) async {
    topBuffer.value = [];
    visible.value = [];
    bottomBuffer.value = [];
    await _centerOnIndex(index + config.visibleCount ~/ 2);
  }

  Future<void> _centerOnIndex(int centerIndex) async {
    if (totalCount.value == 0) return;

    isLoading.value = true;
    final total = totalCount.value;
    final halfVisible = config.visibleCount ~/ 2;

    int visibleStart = max(0, centerIndex - halfVisible);
    visibleStart = min(visibleStart, max(0, total - config.visibleCount));

    final topStart = max(0, visibleStart - config.bufferCount);
    final bottomStart = visibleStart + config.visibleCount;
    final bottomCount = min(config.bufferCount, total - bottomStart);
    final topCount = visibleStart - topStart;
    final visibleCount = min(config.visibleCount, total - visibleStart);

    final globalOffset = topStart;
    final globalLimit = topCount + visibleCount + bottomCount;

    // Fetch in a single query (concurrent via isolate) with retry for locks
    const maxRetries = 3;
    List<Map<String, dynamic>> maps = [];
    
    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        maps = await db.fetchEmailWindow(
          offset: globalOffset,
          limit: globalLimit,
        );
        break; // Success
      } catch (e) {
        final errorStr = e.toString();
        if ((errorStr.contains('database is locked') || errorStr.contains('locked')) 
            && attempt < maxRetries - 1) {
          // Exponential backoff: 50ms, 100ms, 200ms
          final delay = Duration(milliseconds: 50 * (1 << attempt));
          await Future.delayed(delay);
          continue; // Retry
        }
        // Max retries or non-lock error
        isLoading.value = false;
        print('Error fetching email window: $e');
        return;
      }
    }

    final items = maps.map(EmailDto.fromMap).toList(growable: false);

    // Slice into three buffers
    final topSlice = items.sublist(0, topCount);
    final visibleSlice = items.sublist(topCount, topCount + visibleCount);
    final bottomSlice = items.sublist(topCount + visibleCount, items.length);

    _visibleStartIndex = visibleStart;

    topBuffer.value = topSlice;
    visible.value = visibleSlice;
    bottomBuffer.value = bottomSlice;
    firstVisibleIndex.value = visibleStart;

    isLoading.value = false;
  }

  int globalIndexForVisible(int localIndex) {
    return _visibleStartIndex + localIndex;
  }

  void dispose() {
    _scrollDebouncer.dispose();
    _sliderDebouncer.dispose();
    // Signals don't need explicit disposal in signals package
  }
}

/// Simple debouncer utility
class Debouncer {
  final Duration duration;
  Timer? _timer;

  Debouncer(this.duration);

  void run(Future<void> Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, () {
      action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _timer?.cancel();
  }
}
