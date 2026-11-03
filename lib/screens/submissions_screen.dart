import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../services/outbox.dart';
import '../services/site_api.dart';
import '../widgets/common.dart';
import '../widgets/sync_banner.dart';
import 'submission_screen.dart';

class SubmissionsScreen extends StatefulWidget {
  const SubmissionsScreen({super.key});

  @override
  State<SubmissionsScreen> createState() => _SubmissionsScreenState();
}

class _SubmissionsScreenState extends State<SubmissionsScreen> {
  final _list = GlobalKey<AsyncListState<List<Map<String, dynamic>>>>();

  @override
  Widget build(BuildContext context) {
    final box = context.watch<Outbox>();
    return Scaffold(
      appBar: AppBar(title: const Text('Submissions')),
      body: Column(children: [
        const SyncBanner(),
        if (box.pending.isNotEmpty) ...[
          const SectionTitle('On this phone'),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: ListView(shrinkWrap: true, children: [for (final item in box.pending) _OutboxTile(item: item)]),
          ),
        ],
        const SectionTitle('Sent to office'),
        Expanded(
          child: AsyncList<List<Map<String, dynamic>>>(
            key: _list,
            load: () async {
              await Outbox.instance.sync();
              return SiteApi.mySubmissions();
            },
            empty: 'Nothing sent yet',
            builder: (context, rows, reload) => ListView.builder(
              itemCount: rows.length,
              itemBuilder: (_, i) {
                final r = rows[i];
                final dsr = r['kind'] == 'Daily Report';
                return ListTile(
                  leading: CircleAvatar(child: Icon(dsr ? Icons.assignment_outlined : Icons.local_shipping_outlined)),
                  title: Text('${r['tower_site']} · ${r['kind']}'),
                  subtitle: Text('${r['name']} · ${fmtDate(r['date'])}\n${r['summary'] ?? ''}',
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  isThreeLine: true,
                  trailing: StatusChip(r['status'].toString()),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => SubmissionScreen(doctype: SiteApi.doctypeFor(r), name: r['name'].toString()),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

class _OutboxTile extends StatelessWidget {
  const _OutboxTile({required this.item});
  final OutboxItem item;

  @override
  Widget build(BuildContext context) {
    final failed = item.error != null;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: failed ? scheme.errorContainer.withValues(alpha: 0.5) : null,
      child: ListTile(
        leading: Icon(failed ? Icons.error_outline : Icons.cloud_queue, color: failed ? scheme.error : Colors.orange),
        title: Text('${item.site} · ${item.kindLabel}'),
        subtitle: Text(
          failed ? 'Rejected: ${item.error}' : '${item.title}\nSaved ${fmtDateTime(item.created)} · waiting for network',
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
        ),
        isThreeLine: true,
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SubmissionScreen.local(item: item))),
        trailing: PopupMenuButton<String>(
          onSelected: (v) async {
            if (v == 'retry') {
              final n = await Outbox.instance.sync();
              if (context.mounted) showSnack(context, n > 0 ? 'Sent' : 'Not sent yet');
            } else if (v == 'discard') {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Discard this report?'),
                  content: const Text('It has not reached the office. This cannot be undone.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
                  ],
                ),
              );
              if (ok == true) await Outbox.instance.discard(item);
            }
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'retry', child: Text('Retry now')),
            PopupMenuItem(value: 'discard', child: Text('Discard')),
          ],
        ),
      ),
    );
  }
}
