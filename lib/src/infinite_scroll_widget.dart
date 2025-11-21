import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'infinite_scroll_controller.dart';

/// Infinite scroll widget with 3-window strategy
class InfiniteEmailScrollView extends StatefulWidget {
  final InfiniteScrollController controller;

  const InfiniteEmailScrollView({
    super.key,
    required this.controller,
  });

  @override
  State<InfiniteEmailScrollView> createState() =>
      _InfiniteEmailScrollViewState();
}

class _InfiniteEmailScrollViewState extends State<InfiniteEmailScrollView> {
  final ScrollController _scrollController = ScrollController();
  double _currentSliderFraction = 0.0;
  Timer? _signalWatcher;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _startSignalWatcher();
  }

  void _startSignalWatcher() {
    // Poll signals periodically to trigger rebuilds
    _signalWatcher = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (mounted) {
        setState(() {
          // Access signal values to check for changes
          widget.controller.visible.value;
          widget.controller.totalCount.value;
          widget.controller.isLoading.value;
          widget.controller.firstVisibleIndex.value;
        });
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final viewportExtent = position.viewportDimension;
    final scrollOffset = position.pixels;
    
    widget.controller.onScrollPixels(
      scrollOffset: scrollOffset,
      viewportExtent: viewportExtent,
    );
  }

  @override
  void dispose() {
    _signalWatcher?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.pageDown) {
      widget.controller.pageDown();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      widget.controller.pageUp();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      widget.controller.jumpToFraction(0);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      widget.controller.jumpToFraction(1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    // Access signal values - widget rebuilds via timer
    final visible = widget.controller.visible.value;
    final total = widget.controller.totalCount.value;
    final loading = widget.controller.isLoading.value;

    return Column(
      children: [
        if (total > 0) _buildGlobalSlider(total),
        if (loading && visible.isEmpty)
          const Expanded(
            child: Center(child: CircularProgressIndicator()),
          )
        else
          Expanded(
            child: Focus(
              autofocus: true,
              onKeyEvent: _handleKey,
              child: Scrollbar(
                controller: _scrollController,
                thumbVisibility: true,
                child: ListView.builder(
                  controller: _scrollController,
                  itemCount: visible.length,
                  itemExtent: widget.controller.rowExtent,
                  itemBuilder: (context, index) {
                    final email = visible[index];
                    final globalIndex =
                        widget.controller.globalIndexForVisible(index);
                    return _buildEmailRow(context, email, globalIndex);
                  },
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildGlobalSlider(int total) {
    final firstIndex = widget.controller.firstVisibleIndex.value;
    final maxStart =
        (total - widget.controller.config.visibleCount).clamp(1, total);
    final fraction = maxStart <= 0 ? 0.0 : firstIndex / maxStart.toDouble();

    _currentSliderFraction = fraction.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Text('$firstIndex / $total'),
          const SizedBox(width: 8),
          Expanded(
            child: Slider(
              value: _currentSliderFraction,
              onChangeStart: (_) async {
                widget.controller.topBuffer.value = [];
                widget.controller.bottomBuffer.value = [];
              },
              onChanged: (value) {
                _currentSliderFraction = value;
                widget.controller.sliderDebouncer.run(() async {
                  await widget.controller.jumpToFraction(
                    _currentSliderFraction,
                  );
                });
              },
              onChangeEnd: (value) {
                widget.controller.sliderDebouncer.cancel();
                widget.controller.jumpToFraction(value);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmailRow(BuildContext context, EmailDto email, int globalIndex) {
    return ListTile(
      title: Text(
        email.subject,
        style: const TextStyle(fontWeight: FontWeight.bold),
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('From: ${email.fromAddr}'),
          Text('To: ${email.toAddr}'),
          Text(
            'Received: ${email.receivedAt.toString().substring(0, 19)}',
            style: TextStyle(fontSize: 12, color: Colors.grey[600]),
          ),
        ],
      ),
      leading: CircleAvatar(
        child: Text('#$globalIndex'),
      ),
      dense: true,
    );
  }
}
