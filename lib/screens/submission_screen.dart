import 'dart:io';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/brand.dart';
import '../core/format.dart';
import '../services/outbox.dart';
import '../services/site_api.dart';
import '../widgets/common.dart';

/// Read-only view of a submitted Daily Report / Material Receipt.
///
/// Either loads it from the server ([doctype] + [name]) or shows a report that is still
/// waiting on this phone ([local]), using the same layout.
class SubmissionScreen extends StatelessWidget {
  const SubmissionScreen({super.key, required this.doctype, required this.name}) : local = null;
  const SubmissionScreen.local({super.key, required OutboxItem item})
      : local = item,
        doctype = '',
        name = '';

  final String doctype;
  final String name;
  final OutboxItem? local;

  @override
  Widget build(BuildContext context) {
    final item = local;
    if (item != null) {
      return Scaffold(
        appBar: AppBar(title: Text(item.kindLabel)),
        body: _SubmissionView(data: _fromOutbox(item), pending: item),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(name)),
      body: AsyncList<Map<String, dynamic>>(
        load: () => SiteApi.submission(doctype, name),
        builder: (context, data, reload) => _SubmissionView(data: data),
      ),
    );
  }

  /// Maps a queued payload to the server's get_submission shape.
  static Map<String, dynamic> _fromOutbox(OutboxItem item) {
    final p = item.payload;
    final dsr = item.kind == OutboxKind.dailyReport;
    return {
      ...p,
      'kind': item.kindLabel,
      'status': item.error != null ? 'Not accepted' : 'Waiting to send',
      'date': dsr ? p['report_date'] : p['receipt_date'],
      'created_on': item.created.toIso8601String(),
      if (dsr)
        'total_expense': (p['expenses'] as List? ?? []).fold<double>(0, (a, e) => a + toDouble((e as Map)['amount'])),
      'expenses': [
        for (final e in (p['expenses'] as List? ?? [])) {...Map<String, dynamic>.from(e as Map), 'bill': e['bill_path']}
      ],
      'photos': [
        for (final ph in (p['photos'] as List? ?? [])) {'image': (ph as Map)['path'], 'caption': ph['caption']}
      ],
      'postings': const [],
    };
  }
}

class _SubmissionView extends StatelessWidget {
  const _SubmissionView({required this.data, this.pending});
  final Map<String, dynamic> data;
  final OutboxItem? pending;

  bool get _dsr => data['kind'] == 'Daily Report';

  List<Map<String, dynamic>> _rows(String key) =>
      (data[key] as List? ?? []).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final photos = _rows('photos');
    final postings = _rows('postings');
    return ListView(padding: const EdgeInsets.only(bottom: 32), children: [
      _Header(data: data),
      if (pending != null)
        Card(
          color: pending!.error != null ? scheme.errorContainer : scheme.tertiaryContainer,
          child: ListTile(
            leading: Icon(pending!.error != null ? Icons.error_outline : Icons.cloud_queue),
            title: Text(pending!.error != null ? 'Not accepted by the server' : 'Saved on this phone'),
            subtitle: Text(pending!.error ??
                'Not sent yet - it goes automatically when the network is back. Saved ${fmtDateTime(pending!.created)}.'),
          ),
        ),
      if (_dsr) ..._dailyReport(context) else ..._receipt(context),
      if (photos.isNotEmpty) ...[
        SectionTitle(_dsr ? 'Site photos' : 'Challan & material photos', trailing: Text('${photos.length}')),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(spacing: 10, runSpacing: 10, children: [
            for (final p in photos) _Photo(src: p['image'] as String?, caption: p['caption'] as String?, size: 104),
          ]),
        ),
      ],
      if (_text(data['remarks']) != null) ...[
        const SectionTitle('Remarks'),
        _TextCard(data['remarks'].toString()),
      ],
      if (data['latitude'] != null && toDouble(data['latitude']) != 0)
        ListTile(
          leading: const Icon(Icons.location_on_outlined),
          title: const Text('Reported from'),
          subtitle: Text('${toDouble(data['latitude']).toStringAsFixed(5)}, ${toDouble(data['longitude']).toStringAsFixed(5)}'),
        ),
      if (postings.isNotEmpty) ...[
        const SectionTitle('Posted in ERP'),
        Card(
          child: Column(children: [
            for (final p in postings)
              ListTile(
                dense: true,
                leading: const Icon(Icons.receipt_long_outlined),
                title: Text('${p['label']}'),
                subtitle: Text('${p['name']}'),
                trailing: StatusChip('${p['status']}'),
              ),
          ]),
        ),
      ],
    ]);
  }

  List<Widget> _dailyReport(BuildContext context) {
    final work = _rows('work_items');
    final mats = _rows('materials');
    final exps = _rows('expenses');
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            _Field('Labour count', '${data['labour_count'] ?? '-'}', Icons.groups),
            _Field('Milestone achieved', _text(data['milestone_achieved']) ?? 'None', Icons.flag_outlined),
            if (_text(data['supervisor_name']) != null) _Field('Supervisor', data['supervisor_name'].toString(), Icons.person_outline),
          ]),
        ),
      ),
      const SectionTitle('Work completed'),
      _TextCard(_text(data['work_completed']) ?? '-'),
      if (work.isNotEmpty) ...[
        SectionTitle('Quantity completed', trailing: Text('${work.length}')),
        Card(
          child: Column(children: [
            for (final w in work)
              ListTile(
                dense: true,
                title: Text((_text(w['description']) ?? w['item_code']).toString(), maxLines: 2, overflow: TextOverflow.ellipsis),
                subtitle: _text(w['description']) != null ? Text('${w['item_code']}') : null,
                trailing: Text('${qty(w['qty_completed'])} ${w['uom'] ?? ''}',
                    style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ],
      if (mats.isNotEmpty) ...[
        SectionTitle('Material used', trailing: Text('${mats.length}')),
        Card(
          child: Column(children: [
            for (final m in mats)
              ListTile(
                dense: true,
                title: Text((_text(m['item_name']) ?? m['item_code']).toString()),
                subtitle: Text([m['item_code'], m['source_warehouse']].where((e) => _text(e) != null).join(' · ')),
                trailing: Text('${qty(m['qty'])} ${m['uom'] ?? ''}', style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ],
      if (exps.isNotEmpty) ...[
        SectionTitle('Expenses', trailing: Text(money(toDouble(data['total_expense'])))),
        Card(
          child: Column(children: [
            for (final e in exps)
              ListTile(
                dense: true,
                leading: _text(e['bill']) != null
                    ? _Photo(src: e['bill'] as String, size: 44, caption: 'Bill · ${e['expense_type']}')
                    : const CircleAvatar(radius: 22, child: Icon(Icons.payments_outlined, size: 20)),
                title: Text('${e['expense_type']}'),
                subtitle: Text([e['paid_to'], e['description']].where((x) => _text(x) != null).join(' · ')),
                trailing: Text(money(toDouble(e['amount'])), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
          ]),
        ),
      ],
      if (_text(data['pending_work']) != null) ...[
        const SectionTitle('Pending work'),
        _TextCard(data['pending_work'].toString()),
      ],
    ];
  }

  List<Widget> _receipt(BuildContext context) {
    final items = _rows('items');
    final type = (data['receipt_type'] ?? '').toString();
    return [
      Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(children: [
            _Field('Receipt type', type, Icons.local_shipping_outlined),
            if (_text(data['purchase_order']) != null)
              _Field('Purchase Order', '${data['purchase_order']}${_text(data['supplier']) != null ? ' · ${data['supplier']}' : ''}',
                  Icons.receipt_long_outlined),
            if (_text(data['source_warehouse']) != null)
              _Field('Sent from', data['source_warehouse'].toString(), Icons.warehouse_outlined),
            if (_text(data['indus_warehouse']) != null)
              _Field('Indus warehouse / ref', data['indus_warehouse'].toString(), Icons.cell_tower),
            _Field('Challan / DC no', _text(data['challan_no']) ?? '-', Icons.description_outlined),
            if (_text(data['vehicle_no']) != null) _Field('Vehicle no', data['vehicle_no'].toString(), Icons.local_shipping),
            if (_text(data['received_by_name']) != null)
              _Field('Received by', data['received_by_name'].toString(), Icons.person_outline),
            if (_text(data['target_warehouse']) != null)
              _Field('Received into', data['target_warehouse'].toString(), Icons.inventory_2_outlined),
          ]),
        ),
      ),
      SectionTitle('Items received', trailing: Text('${items.length}')),
      Card(
        child: Column(children: [
          for (final i in items)
            ListTile(
              title: Text((_text(i['item_name']) ?? i['item_code'] ?? '-').toString()),
              subtitle: Text([
                if (_text(i['item_code']) != null && i['item_code'] != i['item_name']) '${i['item_code']}',
                if (toDouble(i['rejected_qty']) > 0) 'Damaged / rejected: ${qty(i['rejected_qty'])} ${i['uom'] ?? ''}',
                if (toDouble(i['ordered_qty']) > 0) 'Pending on PO was ${qty(i['ordered_qty'])}',
                if (_text(i['serial_nos']) != null) 'Serial: ${i['serial_nos'].toString().replaceAll('\n', ', ')}',
              ].join('\n')),
              isThreeLine: _text(i['serial_nos']) != null && toDouble(i['rejected_qty']) > 0,
              trailing: Text('${qty(i['received_qty'])} ${i['uom'] ?? ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
        ]),
      ),
    ];
  }
}

String? _text(dynamic v) {
  if (v == null) return null;
  final s = v.toString().trim();
  return s.isEmpty ? null : s;
}

class _Header extends StatelessWidget {
  const _Header({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final dsr = data['kind'] == 'Daily Report';
    final created = DateTime.tryParse('${data['created_on']}');
    final approvedOn = DateTime.tryParse('${data['approved_on']}');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(gradient: Brand.gradient, borderRadius: BorderRadius.circular(16)),
      child: DefaultTextStyle.merge(
        style: const TextStyle(color: Colors.white),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: Colors.white24,
              child: Icon(dsr ? Icons.assignment_outlined : Icons.local_shipping_outlined, color: Colors.white),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('${data['kind']} · ${fmtDate(data['date'])}',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800, color: Colors.white)),
                Text('${data['tower_site'] ?? ''}${_text(data['nominal_name']) != null ? ' · ${data['nominal_name']}' : ''}',
                    style: const TextStyle(color: Colors.white70)),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
              child: Text('${data['status']}',
                  style: TextStyle(color: _statusColor('${data['status']}'), fontWeight: FontWeight.w700, fontSize: 12)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                approvedOn != null
                    ? 'Approved${_text(data['approved_by']) != null ? ' by ${data['approved_by']}' : ''} · ${fmtDateTime(approvedOn.toLocal())}'
                    : created != null
                        ? 'Filed ${fmtDateTime(created.toLocal())}${_text(data['created_by']) != null ? ' by ${data['created_by']}' : ''}'
                        : '',
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  static Color _statusColor(String s) => switch (s) {
        'Approved' => Colors.green.shade700,
        'Cancelled' || 'Not accepted' => Colors.red.shade700,
        _ => Colors.orange.shade800,
      };
}

class _Field extends StatelessWidget {
  const _Field(this.label, this.value, this.icon);
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ListTile(
        dense: true,
        leading: Icon(icon, size: 22),
        title: Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        subtitle: Text(value, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
      );
}

class _TextCard extends StatelessWidget {
  const _TextCard(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(padding: const EdgeInsets.all(14), child: Text(text, style: const TextStyle(fontSize: 15, height: 1.35))),
      );
}

/// Thumbnail of a server photo (/private/files/..., loaded with the app's login) or of a
/// local file still in the outbox. Tap to view full screen.
class _Photo extends StatelessWidget {
  const _Photo({required this.src, this.caption, this.size = 104});
  final String? src;
  final String? caption;
  final double size;

  Widget _image(BoxFit fit) {
    final s = src;
    Widget broken() => Container(
          color: Colors.black12,
          alignment: Alignment.center,
          child: const Icon(Icons.image_not_supported_outlined, color: Colors.black38),
        );
    if (s == null || s.isEmpty) return broken();
    if (s.startsWith('/private/') || s.startsWith('/files/') || s.startsWith('http')) {
      return Image.network(ApiClient.instance.fileUrl(s),
          headers: ApiClient.instance.authHeaders, fit: fit, errorBuilder: (_, __, ___) => broken());
    }
    return Image.file(File(s), fit: fit, errorBuilder: (_, __, ___) => broken());
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              title: Text(_text(caption) ?? 'Photo'),
            ),
            body: Center(child: InteractiveViewer(maxScale: 5, child: _image(BoxFit.contain))),
          ),
        ),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ClipRRect(borderRadius: BorderRadius.circular(10), child: SizedBox(width: size, height: size, child: _image(BoxFit.cover))),
        if (size > 60 && _text(caption) != null)
          SizedBox(
            width: size,
            child: Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(caption!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12)),
            ),
          ),
      ]),
    );
  }
}
