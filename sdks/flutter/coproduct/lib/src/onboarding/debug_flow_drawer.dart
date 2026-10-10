import 'package:flutter/material.dart';

/// A small tab docked to the right edge of the screen that slides out a
/// two-button panel ("Restart flow", "Refresh"), so a developer iterating on
/// a flow's content through the coproduct MCP tools can see the change on a
/// running device without a full app kill/relaunch. [CoproductOnboardingFlow]
/// mounts this only under kDebugMode -- it's never part of a release build,
/// and never part of an author-generated screen's own html: it's chrome the
/// SDK draws over the WebView, not content inside it
class DebugFlowDrawer extends StatefulWidget {
  final Future<void> Function() onRestartFlow;
  final Future<void> Function() onRefresh;

  const DebugFlowDrawer({super.key, required this.onRestartFlow, required this.onRefresh});

  @override
  State<DebugFlowDrawer> createState() => _DebugFlowDrawerState();
}

class _DebugFlowDrawerState extends State<DebugFlowDrawer> {
  bool _open = false;
  bool _busy = false;

  Future<void> _run(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } finally {
      if (mounted) setState(() { _busy = false; _open = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 0,
      top: 0,
      bottom: 0,
      child: Align(
        alignment: Alignment.centerRight,
        child: Material(
          color: Colors.transparent,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            width: _open ? 168 : 28,
            decoration: BoxDecoration(
              color: const Color(0xE6222222),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(10),
                bottomLeft: Radius.circular(10),
              ),
            ),
            child: _open ? _openPanel() : _closedTab(),
          ),
        ),
      ),
    );
  }

  Widget _closedTab() {
    return InkWell(
      onTap: () => setState(() => _open = true),
      child: const SizedBox(
        width: 28,
        height: 56,
        child: Icon(Icons.chevron_left, color: Colors.white, size: 18),
      ),
    );
  }

  Widget _openPanel() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text("DEBUG", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              InkWell(
                onTap: () => setState(() => _open = false),
                child: const Icon(Icons.chevron_right, color: Colors.white70, size: 18),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _actionButton("Restart flow", Icons.restart_alt, () => _run(widget.onRestartFlow)),
          const SizedBox(height: 6),
          _actionButton("Refresh", Icons.refresh, () => _run(widget.onRefresh)),
        ],
      ),
    );
  }

  Widget _actionButton(String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: _busy ? null : onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            _busy
                ? const SizedBox(
                    width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white70),
                  )
                : Icon(icon, color: Colors.white, size: 14),
            const SizedBox(width: 6),
            Expanded(child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 12))),
          ],
        ),
      ),
    );
  }
}
