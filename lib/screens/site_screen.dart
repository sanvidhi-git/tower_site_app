import 'package:flutter/material.dart';

import '../core/brand.dart';
import '../core/format.dart';
import '../services/site_api.dart';
import '../widgets/common.dart';
import 'daily_report_screen.dart';
import 'receipt_screen.dart';
import 'submission_screen.dart';

class SiteScreen extends StatefulWidget {
  const SiteScreen({super.key, required this.site});
  final Map<String, dynamic> site;

  @override
  State<SiteScreen> createState() => _SiteScreenState();
}

class _SiteScreenState extends State<SiteScreen> {
  final _list = GlobalKey<AsyncListState<Map<String, dynamic>>>();

  String get _id => widget.site['name'].toString();

  Future<void> _open(Widget screen) async {
    final changed = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => screen));
    if (changed == true) _list.currentState?.reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_id)),
      body: AsyncList<Map<String, dynamic>>(
        key: _list,
        load: () => SiteApi.siteDetail(_id),
        builder: (context, d, reload) {
          final site = Map<String, dynamic>.from(d['site'] as Map);
          final boq = List<Map<String, dynamic>>.from((d['boq'] as List).map((e) => Map<String, dynamic>.from(e)));
          final ms = List<Map<String, dynamic>>.from((d['milestones'] as List).map((e) => Map<String, dynamic>.from(e)));
          final recent = List<Map<String, dynamic>>.from((d['recent'] as List).map((e) => Map<String, dynamic>.from(e)));
          return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
            _Header(site: site),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(children: [
                Expanded(
                  child: _ActionTile(
                    icon: Icons.assignment_outlined,
                    label: 'Daily Report',
                    sub: 'Work, labour, material, expenses, photos',
                    color: Brand.purple,
                    onTap: () => _open(DailyReportScreen(siteId: _id, detail: d)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ActionTile(
                    icon: Icons.local_shipping_outlined,
                    label: 'Material Receipt',
                    sub: 'Vendor delivery, Indus material, store transfer',
                    color: Brand.orange,
                    onTap: () => _open(ReceiptScreen(siteId: _id, detail: d)),
                  ),
                ),
              ]),
            ),
            const SectionTitle('TAT milestones'),
            Card(
              child: Column(children: [
                for (final m in ms)
                  ListTile(
                    dense: true,
                    leading: Icon(
                      m['status'] == 'Done'
                          ? Icons.check_circle
                          : m['status'] == 'Overdue'
                              ? Icons.error
                              : Icons.radio_button_unchecked,
                      color: m['status'] == 'Done'
                          ? Colors.green
                          : m['status'] == 'Overdue'
                              ? Colors.red
                              : Colors.grey,
                    ),
                    title: Text(m['milestone'].toString()),
                    subtitle: Text(m['actual_date'] != null
                        ? 'Done ${fmtDate(m['actual_date'])}'
                        : 'Due ${fmtDate(m['planned_date'])}${toDouble(m['delay_days']) > 0 ? ' · ${qty(m['delay_days'])} days late' : ''}'),
                  ),
              ]),
            ),
            SectionTitle('BOQ progress (${boq.length} items)'),
            Card(
              child: Column(children: [
                for (final b in boq)
                  ListTile(
                    dense: true,
                    title: Text((b['description'] ?? b['item_code']).toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(children: [
                        Expanded(
                          child: LinearProgressIndicator(value: (toDouble(b['progress']) / 100).clamp(0.0, 1.0).toDouble(), minHeight: 5),
                        ),
                        const SizedBox(width: 8),
                        Text('${qty(b['executed_qty'])} / ${qty(b['po_qty'])} ${b['uom'] ?? ''}',
                            style: const TextStyle(fontSize: 12)),
                      ]),
                    ),
                  ),
              ]),
            ),
            if (recent.isNotEmpty) ...[
              const SectionTitle('Recent from this site'),
              Card(
                child: Column(children: [
                  for (final r in recent)
                    ListTile(
                      dense: true,
                      leading: Icon(r['kind'] == 'Daily Report' ? Icons.assignment_outlined : Icons.local_shipping_outlined),
                      title: Text('${r['kind']} · ${fmtDate(r['date'])}'),
                      subtitle: Text((r['summary'] ?? r['name']).toString(), maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: StatusChip(r['status'].toString()),
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => SubmissionScreen(doctype: SiteApi.doctypeFor(r), name: r['name'].toString()),
                        ),
                      ),
                    ),
                ]),
              ),
            ],
          ]);
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.site});
  final Map<String, dynamic> site;

  @override
  Widget build(BuildContext context) {
    final p = toDouble(site['overall_progress']);
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(16)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${site['nominal_name'] ?? site['name']}',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white)),
          const SizedBox(height: 2),
          Text('${site['status']} · ${site['tower_type'] ?? ''} ${site['tower_height'] != null ? '${qty(site['tower_height'])} m' : ''}'),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                    value: (p / 100).clamp(0.0, 1.0).toDouble(), minHeight: 8, backgroundColor: Colors.white24, color: Colors.white),
              ),
            ),
            const SizedBox(width: 10),
            Text('${p.toStringAsFixed(0)}% done', style: const TextStyle(fontWeight: FontWeight.w700)),
          ]),
          if ((site['site_address'] ?? '').toString().isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(site['site_address'].toString(), style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
          if (site['fse_name'] != null || site['de_name'] != null) ...[
            const SizedBox(height: 6),
            Text('Indus: ${[site['de_name'], site['fse_name']].where((e) => e != null).join(' · ')}',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ]),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.icon, required this.label, required this.sub, required this.color, required this.onTap});
  final IconData icon;
  final String label;
  final String sub;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.1),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            CircleAvatar(backgroundColor: color, child: Icon(icon, color: Colors.white)),
            const SizedBox(height: 10),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 2),
            Text(sub, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
