import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/brand.dart';
import '../core/format.dart';
import '../core/session.dart';
import '../widgets/common.dart';
import '../widgets/sync_banner.dart';
import 'site_screen.dart';

const siteStatusColors = {
  'Work Not Started': Colors.grey,
  'Work In Progress': Colors.orange,
  'Work Completed': Colors.blue,
  'RFI Pending': Colors.amber,
  'RFI Done': Colors.green,
  'On Hold': Colors.red,
};

class SitesScreen extends StatefulWidget {
  const SitesScreen({super.key});

  @override
  State<SitesScreen> createState() => _SitesScreenState();
}

class _SitesScreenState extends State<SitesScreen> {
  String _q = '';

  Future<void> _refresh() async {
    try {
      await context.read<Session>().refresh();
    } catch (e) {
      if (mounted) showErrorDialog(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    final sites = s.sites.where((x) {
      final q = _q.toLowerCase();
      return q.isEmpty ||
          '${x['name']} ${x['nominal_name']} ${x['zone']} ${x['district']}'.toLowerCase().contains(q);
    }).toList();
    final first = s.fullName.split(' ').first;
    return Scaffold(
      appBar: AppBar(
        title: Text('Hi $first'),
        actions: [IconButton(onPressed: _refresh, icon: const Icon(Icons.refresh), tooltip: 'Refresh')],
      ),
      body: Column(children: [
        const SyncBanner(),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: TextField(
            decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search site ID, name, zone', isDense: true),
            onChanged: (v) => setState(() => _q = v),
          ),
        ),
        Expanded(
          child: RefreshIndicator(
            onRefresh: _refresh,
            child: s.sites.isEmpty
                ? ListView(children: const [
                    SizedBox(height: 120),
                    Icon(Icons.cell_tower, size: 56),
                    SizedBox(height: 12),
                    Center(child: Text('No sites assigned to you yet.\nAsk your Project Manager to add you to the site team.', textAlign: TextAlign.center)),
                  ])
                : ListView.builder(
                    padding: const EdgeInsets.only(top: 4, bottom: 24),
                    itemCount: sites.length,
                    itemBuilder: (_, i) => _SiteCard(site: sites[i]),
                  ),
          ),
        ),
      ]),
    );
  }
}

class _SiteCard extends StatelessWidget {
  const _SiteCard({required this.site});
  final Map<String, dynamic> site;

  @override
  Widget build(BuildContext context) {
    final status = (site['status'] ?? '').toString();
    final color = siteStatusColors[status] ?? Colors.grey;
    final progress = toDouble(site['overall_progress']) / 100;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => SiteScreen(site: site))),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Brand.orange.withValues(alpha: 0.15),
                child: const Icon(Icons.cell_tower, color: Brand.orange, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(site['name'].toString(), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                  Text('${site['nominal_name'] ?? ''}', style: TextStyle(color: scheme.onSurfaceVariant)),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(20)),
                child: Text(status, style: TextStyle(color: color.shade800, fontWeight: FontWeight.w600, fontSize: 12)),
              ),
            ]),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: LinearProgressIndicator(value: progress.clamp(0.0, 1.0).toDouble(), minHeight: 8),
                ),
              ),
              const SizedBox(width: 10),
              Text('${(progress * 100).toStringAsFixed(0)}%', style: const TextStyle(fontWeight: FontWeight.w600)),
            ]),
            const SizedBox(height: 8),
            Text(
              [site['zone'], site['district'], site['principal_opco'], site['tower_type']]
                  .where((e) => e != null && '$e'.isNotEmpty)
                  .join(' · '),
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ]),
        ),
      ),
    );
  }
}
