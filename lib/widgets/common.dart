import 'package:flutter/material.dart';

import '../core/api.dart';

Future<void> showErrorDialog(BuildContext context, Object e) {
  final title = e is ApiException ? e.title : 'Error';
  final msg = e is ApiException ? e.message : e.toString();
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: const Icon(Icons.error_outline),
      title: Text(title),
      content: Text(msg),
      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}

void showSnack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
}

/// Shows a blocking progress dialog while [task] runs. Updates the label via the
/// callback passed to [task].
Future<T> withProgress<T>(BuildContext context, String label,
    Future<T> Function(void Function(String) setLabel) task) async {
  final notifier = ValueNotifier<String>(label);
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          const SizedBox(width: 28, height: 28, child: CircularProgressIndicator(strokeWidth: 3)),
          const SizedBox(width: 20),
          Expanded(child: ValueListenableBuilder<String>(valueListenable: notifier, builder: (_, v, __) => Text(v))),
        ]),
      ),
    ),
  );
  try {
    return await task((s) => notifier.value = s);
  } finally {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    notifier.dispose();
  }
}

/// FutureBuilder with loading / error+retry / pull-to-refresh baked in.
class AsyncList<T> extends StatefulWidget {
  const AsyncList({super.key, required this.load, required this.builder, this.empty = 'Nothing here yet'});

  final Future<T> Function() load;
  final Widget Function(BuildContext, T, Future<void> Function() reload) builder;
  final String empty;

  @override
  State<AsyncList<T>> createState() => AsyncListState<T>();
}

class AsyncListState<T> extends State<AsyncList<T>> {
  late Future<T> _future = widget.load();

  Future<void> reload() async {
    final f = widget.load();
    setState(() => _future = f);
    try {
      await f;
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return ErrorRetry(error: snap.error!, onRetry: reload);
        }
        final data = snap.data as T;
        if (data is List && data.isEmpty) {
          return RefreshIndicator(
            onRefresh: reload,
            child: ListView(children: [
              const SizedBox(height: 120),
              Icon(Icons.inbox_outlined, size: 56, color: Theme.of(context).colorScheme.outline),
              const SizedBox(height: 12),
              Center(child: Text(widget.empty)),
            ]),
          );
        }
        return RefreshIndicator(onRefresh: reload, child: widget.builder(context, data, reload));
      },
    );
  }
}

class ErrorRetry extends StatelessWidget {
  const ErrorRetry({super.key, required this.error, required this.onRetry});
  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final msg = error is ApiException ? (error as ApiException).message : '$error';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.cloud_off, size: 48, color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          Text(msg, textAlign: TextAlign.center),
          const SizedBox(height: 16),
          FilledButton.tonal(onPressed: onRetry, child: const Text('Retry')),
        ]),
      ),
    );
  }
}

class StatusChip extends StatelessWidget {
  const StatusChip(this.status, {super.key});
  final String status;

  @override
  Widget build(BuildContext context) {
    final s = status.toLowerCase();
    final Color c = switch (s) {
      'approved' || 'paid' || 'present' || 'completed' || 'submitted' || 'claimed' || 'active' => Colors.green,
      'rejected' || 'cancelled' || 'absent' || 'offline' => Colors.red,
      'open' || 'draft' || 'pending' || 'pending approval' || 'unpaid' => Colors.orange,
      'on leave' || 'half day' || 'work from home' => Colors.blue,
      _ => Colors.grey,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Text(status, style: TextStyle(color: c, fontWeight: FontWeight.w600, fontSize: 12)),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.text, {super.key, this.trailing});
  final String text;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Row(children: [
          Expanded(child: Text(text, style: Theme.of(context).textTheme.titleMedium)),
          if (trailing != null) trailing!,
        ]),
      );
}
