import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/session.dart';
import '../services/outbox.dart';
import 'common.dart';

/// Offline / unsent-reports banner shown on top of the main tabs.
class SyncBanner extends StatelessWidget {
  const SyncBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final box = context.watch<Outbox>();
    final offline = context.watch<Session>().offline;
    final n = box.pending.length;
    if (n == 0 && !offline) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final rejected = box.pending.where((e) => e.error != null).length;
    return Material(
      color: rejected > 0 ? scheme.errorContainer : scheme.tertiaryContainer,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(children: [
          Icon(offline ? Icons.cloud_off : Icons.cloud_upload_outlined, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              n == 0
                  ? 'Offline - showing saved data. Reports will be queued.'
                  : rejected > 0
                      ? '$rejected report(s) need attention, ${n - rejected} waiting to send'
                      : '$n report(s) waiting to send${offline ? ' (offline)' : ''}',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (n > 0)
            box.syncing
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)))
                : TextButton(
                    onPressed: () async {
                      final sent = await box.sync();
                      if (context.mounted) {
                        showSnack(context, sent > 0 ? '$sent report(s) sent' : 'Still offline - will retry automatically');
                        if (sent > 0) context.read<Session>().refresh().catchError((_) {});
                      }
                    },
                    child: const Text('Sync now'),
                  ),
        ]),
      ),
    );
  }
}
