import 'dart:async';
import 'package:flutter/material.dart';

enum ToastType {
  success,
  error,
  warning,
  info,
}

/// A luxury floating capsule toast (Top-Center pill) with smooth slide/fade animations.
/// Designed for 11/10 ergonomics to avoid occluding bottom POS & cart action buttons.
class AppFloatingToast {
  static OverlayEntry? _currentEntry;

  /// Displays a floating pill toast at the top center of the screen.
  static void show(
    BuildContext context, {
    required String message,
    ToastType type = ToastType.success,
    Duration duration = const Duration(milliseconds: 2500),
    VoidCallback? onDismissed,
  }) {
    dismissCurrent();

    final overlay =
        Overlay.maybeOf(context, rootOverlay: true) ?? Overlay.maybeOf(context);
    if (overlay == null) return;

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _AppFloatingToastWidget(
        message: message,
        type: type,
        duration: duration,
        onClose: () {
          _removeEntry(entry);
          onDismissed?.call();
        },
      ),
    );

    _currentEntry = entry;
    overlay.insert(entry);
  }

  /// Immediately dismisses any active toast.
  static void dismissCurrent() {
    if (_currentEntry != null) {
      final entry = _currentEntry!;
      _currentEntry = null;
      try {
        if (entry.mounted) {
          entry.remove();
        }
      } catch (_) {}
    }
  }

  static void _removeEntry(OverlayEntry entry) {
    if (_currentEntry == entry) {
      _currentEntry = null;
    }
    try {
      if (entry.mounted) {
        entry.remove();
      }
    } catch (_) {}
  }
}

class _AppFloatingToastWidget extends StatefulWidget {
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onClose;

  const _AppFloatingToastWidget({
    required this.message,
    required this.type,
    required this.duration,
    required this.onClose,
  });

  @override
  State<_AppFloatingToastWidget> createState() =>
      _AppFloatingToastWidgetState();
}

class _AppFloatingToastWidgetState extends State<_AppFloatingToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnim;
  late final Animation<double> _fadeAnim;
  Timer? _localTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );

    _slideAnim = Tween<Offset>(
      begin: const Offset(0, -0.65),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _controller.forward();

    _localTimer = Timer(widget.duration, () {
      if (mounted) {
        _controller.reverse().then((_) {
          if (mounted) {
            widget.onClose();
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _localTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Color _getTypeColor(ToastType type) {
    switch (type) {
      case ToastType.success:
        return const Color(0xFF10B981); // Emerald
      case ToastType.error:
        return const Color(0xFFF43F5E); // Rose
      case ToastType.warning:
        return const Color(0xFFF59E0B); // Amber
      case ToastType.info:
        return const Color(0xFF38BDF8); // Sky
    }
  }

  IconData _getTypeIcon(ToastType type) {
    switch (type) {
      case ToastType.success:
        return Icons.check_circle_rounded;
      case ToastType.error:
        return Icons.error_rounded;
      case ToastType.warning:
        return Icons.warning_amber_rounded;
      case ToastType.info:
        return Icons.info_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final typeColor = _getTypeColor(widget.type);
    final typeIcon = _getTypeIcon(widget.type);

    return SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 20.0, left: 16.0, right: 16.0),
          child: SlideTransition(
            position: _slideAnim,
            child: FadeTransition(
              opacity: _fadeAnim,
              child: Material(
                color: Colors.transparent,
                child: Container(
                  key: const Key('app_floating_toast'),
                  constraints: const BoxConstraints(maxWidth: 520),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: typeColor.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.35),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                      BoxShadow(
                        color: typeColor.withValues(alpha: 0.15),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(5),
                        decoration: BoxDecoration(
                          color: typeColor.withValues(alpha: 0.15),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(typeIcon, color: typeColor, size: 18),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
                        child: Text(
                          widget.message,
                          key: const Key('app_floating_toast_message'),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      InkWell(
                        onTap: () {
                          _controller.reverse().then((_) {
                            if (mounted) {
                              widget.onClose();
                            }
                          });
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: const Padding(
                          padding: EdgeInsets.all(2.0),
                          child: Icon(
                            Icons.close_rounded,
                            size: 15,
                            color: Colors.white54,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
