import 'package:flutter/material.dart';

class TopNotificationModal extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color textColor;

  const TopNotificationModal({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    this.onTap,
    this.backgroundColor = const Color(0xFF8CA6C7),
    this.textColor = Colors.white,
  });

  @override
  State<TopNotificationModal> createState() => _TopNotificationModalState();
}

// ...existing code...
class _TopNotificationModalState extends State<TopNotificationModal> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );
    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _offsetAnimation,
      child: GestureDetector(
        onTap: widget.onTap,
        child: Material(
          color: Colors.transparent,
          child: Container(
            width: double.infinity,
            margin: const EdgeInsets.symmetric(horizontal: 18, vertical: 36),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: widget.backgroundColor,
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(.12),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Icon(widget.icon, color: Colors.amber, size: 38),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                          color: widget.textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        widget.message,
                        style: TextStyle(
                          fontSize: 16,
                          color: widget.textColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Helper to show/hide the top overlay
class TopNotificationBanner {
  static OverlayEntry? _entry;

  static void show(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    Color backgroundColor = const Color(0xFF8CA6C7),
    Duration duration = const Duration(seconds: 4),
    VoidCallback? onTap,
  }) {
    hide();
    final overlay = Overlay.of(context);
    _entry = OverlayEntry(
      builder: (_) => SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: TopNotificationModal(
            title: title,
            message: message,
            icon: icon,
            backgroundColor: backgroundColor,
            onTap: () {
              hide();
              onTap?.call();
            },
          ),
        ),
      ),
    );
    overlay.insert(_entry!);
    Future.delayed(duration, () => hide());
  }

  static void hide() {
    _entry?.remove();
    _entry = null;
  }
}