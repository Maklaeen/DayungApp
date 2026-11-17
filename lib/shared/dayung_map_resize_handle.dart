import 'package:flutter/material.dart';

class DayungMapResizeHandle extends StatelessWidget {
  const DayungMapResizeHandle({
    super.key,
    required this.onResize,
    this.tooltip = 'Drag to resize map',
  });

  final ValueChanged<double> onResize;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) => onResize(details.delta.dy),
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeUpDown,
          child: Tooltip(
            message: tooltip,
            child: SizedBox(
              width: 96,
              height: 40,
              child: Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(30),
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
