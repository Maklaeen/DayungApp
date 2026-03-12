import 'package:capstone_app/ui/theme/branding.dart';
import 'package:flutter/material.dart';

enum DayungSkeletonLayout { list, detail, dashboard, profile }

class DayungPageSkeleton extends StatefulWidget {
  final DayungSkeletonLayout layout;
  final EdgeInsetsGeometry padding;
  final int itemCount;

  const DayungPageSkeleton({
    super.key,
    this.layout = DayungSkeletonLayout.list,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
    this.itemCount = 5,
  });

  @override
  State<DayungPageSkeleton> createState() => _DayungPageSkeletonState();
}

class _DayungPageSkeletonState extends State<DayungPageSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment(-1.0 + (2.0 * _controller.value), -0.3),
              end: Alignment(0.0 + (2.0 * _controller.value), 0.3),
              colors: const [
                Color(0xFFE9EEF5),
                Color(0xFFF8FBFF),
                Color(0xFFE9EEF5),
              ],
              stops: const [0.15, 0.50, 0.85],
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: SingleChildScrollView(
        physics: const NeverScrollableScrollPhysics(),
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: _buildLayout(context),
        ),
      ),
    );
  }

  List<Widget> _buildLayout(BuildContext context) {
    switch (widget.layout) {
      case DayungSkeletonLayout.profile:
        return _buildProfileLayout();
      case DayungSkeletonLayout.dashboard:
        return _buildDashboardLayout();
      case DayungSkeletonLayout.detail:
        return _buildDetailLayout();
      case DayungSkeletonLayout.list:
        return _buildListLayout();
    }
  }

  List<Widget> _buildListLayout() {
    return [
      _bone(height: 54, radius: 18),
      const SizedBox(height: 16),
      Row(
        children: [
          Expanded(child: _bone(height: 76, radius: 20)),
          const SizedBox(width: 12),
          Expanded(child: _bone(height: 76, radius: 20)),
        ],
      ),
      const SizedBox(height: 18),
      ...List.generate(
        widget.itemCount,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _listCard(),
        ),
      ),
    ];
  }

  List<Widget> _buildDetailLayout() {
    return [
      _bone(height: 180, radius: 28),
      const SizedBox(height: 18),
      _bone(height: 26, width: 180, radius: 10),
      const SizedBox(height: 10),
      _bone(height: 16, width: 240),
      const SizedBox(height: 26),
      _detailSection(),
      const SizedBox(height: 18),
      _detailSection(lines: 4),
    ];
  }

  List<Widget> _buildDashboardLayout() {
    return [
      _bone(height: 140, radius: 28),
      const SizedBox(height: 18),
      Wrap(
        spacing: 12,
        runSpacing: 12,
        children: List.generate(
          4,
          (_) => SizedBox(width: 160, child: _bone(height: 92, radius: 20)),
        ),
      ),
      const SizedBox(height: 18),
      _detailSection(lines: 3),
      const SizedBox(height: 18),
      ...List.generate(
        3,
        (_) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _listCard(),
        ),
      ),
    ];
  }

  List<Widget> _buildProfileLayout() {
    return [
      _bone(height: 128, radius: 28),
      const SizedBox(height: 18),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFE6ECF5)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                _bone(height: 76, width: 76, radius: 38),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _bone(height: 20, width: 170),
                      const SizedBox(height: 10),
                      _bone(height: 14, width: 130),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            ...List.generate(
              4,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _bone(height: 62, radius: 16),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 18),
      _detailSection(lines: 4),
    ];
  }

  Widget _listCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE6ECF5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bone(height: 52, width: 52, radius: 16),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _bone(height: 16, width: 90, radius: 999),
                const SizedBox(height: 12),
                _bone(height: 20, width: 180),
                const SizedBox(height: 8),
                _bone(height: 14),
                const SizedBox(height: 6),
                _bone(height: 14, width: 220),
                const SizedBox(height: 12),
                _bone(height: 14, width: 110),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _detailSection({int lines = 3}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFE6ECF5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _bone(height: 18, width: 120),
          const SizedBox(height: 18),
          ...List.generate(lines, (index) {
            return Padding(
              padding: EdgeInsets.only(bottom: index == lines - 1 ? 0 : 14),
              child: _bone(height: 56, radius: 16),
            );
          }),
        ],
      ),
    );
  }

  Widget _bone({required double height, double? width, double radius = 12}) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: const Color(0xFFE3EAF3),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}

class DayungLoadingScaffold extends StatelessWidget {
  final DayungSkeletonLayout layout;
  final Color backgroundColor;

  const DayungLoadingScaffold({
    super.key,
    this.layout = DayungSkeletonLayout.list,
    this.backgroundColor = kBg,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(child: DayungPageSkeleton(layout: layout)),
    );
  }
}
