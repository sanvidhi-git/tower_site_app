import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/brand.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../services/outbox.dart';
import '../widgets/common.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _logout(BuildContext context) async {
    final s = context.read<Session>();
    try {
      await s.logout();
    } catch (e) {
      if (!context.mounted) return;
      final force = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Unsent reports'),
          content: Text('$e\n\nSigning out now deletes them from this phone.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Stay signed in')),
            TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out anyway')),
          ],
        ),
      );
      if (force == true) await s.logout(force: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final box = context.watch<Outbox>();
    final emp = s.employee;
    return Scaffold(
      appBar: AppBar(title: const Text('Me')),
      body: ListView(children: [
        Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(16)),
          child: Row(children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.white,
              child: Text(s.fullName.isEmpty ? '?' : s.fullName[0],
                  style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: Brand.purple)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(s.fullName, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
                Text(s.user ?? '', style: const TextStyle(color: Colors.white70)),
                if (emp != null) Text('${emp['name']}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
              ]),
            ),
          ]),
        ),
        ListTile(leading: const Icon(Icons.cell_tower), title: const Text('Sites assigned'), trailing: Text('${s.sites.length}')),
        ListTile(
          leading: const Icon(Icons.dns_outlined),
          title: const Text('Server'),
          subtitle: Text(s.serverUrl ?? '-'),
          trailing: s.offline ? const StatusChip('Offline') : const StatusChip('Active'),
        ),
        ListTile(
          leading: const Icon(Icons.cloud_upload_outlined),
          title: const Text('Waiting to send'),
          subtitle: Text(box.lastSync == null ? 'Not synced yet' : 'Last sync ${fmtDateTime(box.lastSync!)}'),
          trailing: Text('${box.pending.length}'),
          onTap: () => box.sync(),
        ),
        if (s.isManager)
          const ListTile(
            leading: Icon(Icons.verified_user_outlined),
            title: Text('Project Manager'),
            subtitle: Text('You see all open sites. Approve reports in ERPNext.'),
          ),
        const Divider(),
        ListTile(
          leading: const Icon(Icons.logout),
          title: const Text('Sign out'),
          onTap: () => _logout(context),
        ),
        const SizedBox(height: 24),
        Center(
          child: Text('${Brand.appName} · ${Brand.company}',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.outline)),
        ),
        const SizedBox(height: 24),
      ]),
    );
  }
}
