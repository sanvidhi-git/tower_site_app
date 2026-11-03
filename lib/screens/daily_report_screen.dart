import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../services/outbox.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/photo_strip.dart';
import '../widgets/pickers.dart';

class _Work {
  _Work(this.boq);
  final Map<String, dynamic> boq;
  double qty = 0;
}

class _Material {
  _Material(this.item);
  final Map<String, dynamic> item;
  double qty = 0;
  String? warehouse;
}

class _Expense {
  String? type;
  double amount = 0;
  String description = '';
  String paidTo = '';
  String? billPath;
}

class DailyReportScreen extends StatefulWidget {
  const DailyReportScreen({super.key, required this.siteId, required this.detail});
  final String siteId;
  final Map<String, dynamic> detail;

  @override
  State<DailyReportScreen> createState() => _DailyReportScreenState();
}

class _DailyReportScreenState extends State<DailyReportScreen> {
  final _form = GlobalKey<FormState>();
  DateTime _date = DateTime.now();
  final _labour = TextEditingController();
  final _work = TextEditingController();
  final _pending = TextEditingController();
  final _remarks = TextEditingController();
  String? _milestone;
  Position? _pos;
  final _works = <_Work>[];
  final _materials = <_Material>[];
  final _expenses = <_Expense>[];
  final _photos = <PhotoEntry>[];
  bool _busy = false;

  List<Map<String, dynamic>> get _boq =>
      List<Map<String, dynamic>>.from((widget.detail['boq'] as List).map((e) => Map<String, dynamic>.from(e)));

  @override
  void dispose() {
    for (final c in [_labour, _work, _pending, _remarks]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final d = await showDatePicker(
        context: context, initialDate: _date, firstDate: now.subtract(const Duration(days: 7)), lastDate: now);
    if (d != null) setState(() => _date = d);
  }

  Future<void> _addWork() async {
    final open = _boq.where((b) => !_works.any((w) => w.boq['item_code'] == b['item_code'])).toList();
    final b = await pickFromList<Map<String, dynamic>>(context,
        title: 'BOQ item worked on',
        items: open,
        label: (e) => (e['description'] ?? e['item_code']).toString(),
        subtitle: (e) =>
            '${e['task_name'] ?? ''} · done ${qty(e['executed_qty'])} of ${qty(e['po_qty'])} ${e['uom'] ?? ''}');
    if (b != null) setState(() => _works.add(_Work(b)));
  }

  Future<void> _addMaterial() async {
    final it = await pickStockItem(context);
    if (it != null) setState(() => _materials.add(_Material(it)));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final s = context.read<Session>();
    final badExp = _expenses.where((e) => e.type == null || e.amount <= 0);
    if (badExp.isNotEmpty) {
      return showErrorDialog(context, 'Every expense needs a type and an amount.');
    }
    if (_works.any((w) => w.qty <= 0) || _materials.any((m) => m.qty <= 0)) {
      return showErrorDialog(context, 'Enter a quantity for every BOQ item and material line, or remove the line.');
    }
    setState(() => _busy = true);
    final payload = <String, dynamic>{
      'mobile_ref': Outbox.newRef(),
      'tower_site': widget.siteId,
      'report_date': isoDate(_date),
      'labour_count': int.tryParse(_labour.text.trim()) ?? 0,
      'milestone_achieved': _milestone,
      'work_completed': _work.text.trim(),
      'pending_work': _pending.text.trim(),
      'remarks': _remarks.text.trim(),
      'latitude': _pos?.latitude,
      'longitude': _pos?.longitude,
      'work_items': [
        for (final w in _works) {'item_code': w.boq['item_code'], 'qty_completed': w.qty}
      ],
      'materials': [
        for (final m in _materials) {'item_code': m.item['item_code'], 'qty': m.qty, 'source_warehouse': m.warehouse}
      ],
      'expenses': [
        for (final e in _expenses)
          {
            'expense_type': e.type,
            'amount': e.amount,
            'description': e.description,
            'paid_to': e.paidTo,
            'bill_path': e.billPath,
          }
      ],
      'photos': [
        for (final p in _photos) {'path': p.path, 'caption': p.caption}
      ],
    };
    final title = _work.text.trim().split('\n').first;
    final r = await Outbox.instance.submit(OutboxKind.dailyReport, widget.siteId, title, payload);
    if (!mounted) return;
    setState(() => _busy = false);
    await showSubmitResult(context, r, 'daily report');
    if (mounted) Navigator.pop(context, true);
    s.refresh().catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: Text('Daily Report · ${widget.siteId}')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(avatar: const Icon(Icons.event), label: Text(fmtDate(_date)), onPressed: _pickDate),
              GpsChip(onFix: (p) => _pos = p),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              SizedBox(
                width: 150,
                child: TextFormField(
                  controller: _labour,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Labour', prefixIcon: Icon(Icons.groups)),
                  validator: (v) => (int.tryParse(v?.trim() ?? '') == null) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String?>(
                  initialValue: _milestone,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Milestone achieved'),
                  items: [
                    const DropdownMenuItem<String?>(value: null, child: Text('None today')),
                    for (final m in s.milestones)
                      DropdownMenuItem<String?>(value: m['name'] as String, child: Text(m['name'] as String)),
                  ],
                  onChanged: (v) => setState(() => _milestone = v),
                ),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextFormField(
              controller: _work,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Work completed today', alignLabelWithHint: true),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Describe the work done' : null,
            ),
          ),
          SectionTitle('Quantity completed', trailing: Text('${_works.length}')),
          for (final w in _works)
            LineCard(
              key: ObjectKey(w),
              title: (w.boq['description'] ?? w.boq['item_code']).toString(),
              subtitle: 'Done so far ${qty(w.boq['executed_qty'])} of ${qty(w.boq['po_qty'])} ${w.boq['uom'] ?? ''}',
              onRemove: () => setState(() => _works.remove(w)),
              children: [QtyField(value: w.qty, label: 'Today', suffix: w.boq['uom']?.toString(), width: 160, onChanged: (v) => w.qty = v)],
            ),
          AddButton('Add BOQ item', onPressed: _addWork),
          SectionTitle('Material used', trailing: Text('${_materials.length}')),
          for (final m in _materials)
            LineCard(
              key: ObjectKey(m),
              title: (m.item['item_name'] ?? m.item['item_code']).toString(),
              subtitle: m.item['item_code'].toString(),
              onRemove: () => setState(() => _materials.remove(m)),
              children: [
                QtyField(value: m.qty, suffix: m.item['uom']?.toString(), onChanged: (v) => m.qty = v),
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String?>(
                    initialValue: m.warehouse,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Taken from', isDense: true),
                    items: [
                      const DropdownMenuItem<String?>(value: null, child: Text('Site stock / store')),
                      for (final w in s.warehouses) DropdownMenuItem<String?>(value: w, child: Text(w, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => m.warehouse = v,
                  ),
                ),
              ],
            ),
          AddButton('Add material', onPressed: _addMaterial),
          SectionTitle('Expenses', trailing: Text(money(_expenses.fold<double>(0, (a, e) => a + e.amount)))),
          for (final e in _expenses)
            LineCard(
              key: ObjectKey(e),
              title: e.type ?? 'New expense',
              onRemove: () => setState(() => _expenses.remove(e)),
              children: [
                SizedBox(
                  width: 210,
                  child: DropdownButtonFormField<String>(
                    initialValue: e.type,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Type', isDense: true),
                    items: [for (final t in s.expenseTypes) DropdownMenuItem(value: t, child: Text(t))],
                    onChanged: (v) => setState(() => e.type = v),
                  ),
                ),
                QtyField(value: e.amount, label: 'Amount ₹', onChanged: (v) => setState(() => e.amount = v)),
                SizedBox(
                  width: 210,
                  child: TextFormField(
                    initialValue: e.paidTo,
                    decoration: const InputDecoration(labelText: 'Paid to', isDense: true),
                    onChanged: (v) => e.paidTo = v,
                  ),
                ),
                SizedBox(
                  width: 210,
                  child: TextFormField(
                    initialValue: e.description,
                    decoration: const InputDecoration(labelText: 'Details', isDense: true),
                    onChanged: (v) => e.description = v,
                  ),
                ),
                OutlinedButton.icon(
                  icon: Icon(e.billPath == null ? Icons.receipt_long : Icons.check_circle,
                      color: e.billPath == null ? null : Colors.green),
                  label: Text(e.billPath == null ? 'Bill photo' : 'Bill attached'),
                  onPressed: () async {
                    final p = await pickPhoto(context);
                    if (p != null) setState(() => e.billPath = p);
                  },
                ),
              ],
            ),
          AddButton('Add expense', onPressed: () => setState(() => _expenses.add(_Expense()))),
          SectionTitle('Site photos', trailing: Text('${_photos.length}')),
          PhotoStrip(photos: _photos, onChanged: () => setState(() {})),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: TextFormField(
              controller: _pending,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Pending work', alignLabelWithHint: true),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: TextFormField(
              controller: _remarks,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Remarks / issues', alignLabelWithHint: true),
            ),
          ),
        ]),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            onPressed: _busy ? null : _submit,
            icon: _busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.send),
            label: const Text('Submit daily report'),
          ),
        ),
      ),
    );
  }
}
