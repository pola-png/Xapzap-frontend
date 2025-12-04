import 'package:flutter/material.dart';

/// Simple wrapper that keeps the tab subtree alive when switching
/// between TabBarView pages.
class KeepAliveTab extends StatefulWidget {
  final Widget Function(BuildContext) builder;

  const KeepAliveTab({super.key, required this.builder});

  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}

class _KeepAliveTabState extends State<KeepAliveTab>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.builder(context);
  }
}

