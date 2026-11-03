import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../core/format.dart';
import '../core/session.dart';
import '../services/outbox.dart';
import '../services/site_api.dart';
import '../widgets/common.dart';
import '../widgets/form_bits.dart';
import '../widgets/photo_strip.dart';
import '../widgets/pickers.dart';

enum ReceiptType {
  vendor('Vendor Delivery against PO', 'Vendor (PO)', Icons.storefront),
  indus('Indus Free-Issue Material', 'Indus material', Icons.cell_tower),
  transfer('Transfer from Store', 'From our store', Icons.warehouse_outlined);

  const ReceiptType(this.server, this.short, this.icon);
  final String server;
  final String short;
  final IconData icon;
}

class _Line {
  _Line({this.itemCode, this.name = '', this.uom, this.pending, this.poItem, this.received = 0});
  String? itemCode;
  String name;
  String? uom;
  double? pending;
  String? poItem;
  double received;
  double rejected = 0;
  String serials = '';
}

class ReceiptScreen extends StatefulWidget {
  const ReceiptScreen({super.key, required this.siteId, required this.detail});
  final String siteId;
  final Map<String, dynamic> detail;

  @override
  State<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends State<ReceiptScreen> {
  final _form = GlobalKey<FormState>();
  ReceiptType _type = ReceiptType.vendor;
  DateTime _date = DateTime.now();
  final _challan = TextEditingController();
  final _vehicle = TextEditingController();
  final _indusRef = TextEditingController();
  final _remarks = TextEditingController();
  String? _po;
  String? _fromWarehouse;
  Position? _pos;
  List<_Line> _lines = [];
  final _photos = <PhotoEntry>[];
  bool _busy = false;
  bool _loadingPo = false;

  List<Map<String, dynamic>> get _openPos =>
      List<Map<String, dynamic>>.from((widget.detail['open_pos'] as List? ?? []).map((e) => Map<String, dynamic>.from(e)));

  @override
  void initState() {
    super.initState();
    _fromWarehouse = context.read<Session>().centralStore;
    if (_openPos.isEmpty) _type = ReceiptType.indus;
  }

  @override
  void dispose() {
    for (final c in [_challan, _vehicle, _indusRef, _remarks]) {
      c.dispose();
    }
    super.dispose();
  }

  void _setType(ReceiptType t) => setState(() {
        _type = t;
        _lines = [];
        _po = null;
      });

  Future<void> _selectPo(String? po) async {
    setState(() {
      _po = po;
      _lines = [];
      _loadingPo = po != null;
    });
    if (po == null) return;
    try {
      final rows = await SiteApi.poItems(po);
      if (!mounted || _po != po) return;
      setState(() => _lines = [
            for (final r in rows)
              _Line(
                itemCode: r['item_code'] as String,
                name: (r['item_name'] ?? r['item_code']).toString(),
                uom: r['uom'] as String?,
                pending: toDouble(r['pending_qty']),
                poItem: r['name'] as String,
                received: toDouble(r['pending_qty']),
              )
          ]);
    } catch (e) {
      if (mounted) showErrorDialog(context, e);
    } finally {
      if (mounted) setState(() => _loadingPo = false);
    }
  }

  Future<void> _addStockLine() async {
    final it = await pickStockItem(context);
    if (it == null) return;
    setState(() => _lines.add(_Line(
        itemCode: it['item_code'] as String, name: (it['item_name'] ?? it['item_code']).toString(), uom: it['uom'] as String?)));
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final lines = _lines.where((l) => l.received > 0 || l.rejected > 0).toList();
    if (lines.isEmpty) return showErrorDialog(context, 'Enter the quantity received for at least one item.');
    if (_type == ReceiptType.indus && lines.any((l) => l.name.trim().isEmpty)) {
      return showErrorDialog(context, 'Enter a description for every Indus material line.');
    }
    if (_type != ReceiptType.transfer && _photos.isEmpty) {
      return showErrorDialog(context, 'Add a photo of the challan / delivery note as proof of receipt.');
    }
    setState(() => _busy = true);
    final payload = <String, dynamic>{
      'mobile_ref': Outbox.newRef(),
      'tower_site': widget.siteId,
      'receipt_type': _type.server,
      'receipt_date': isoDate(_date),
      'purchase_order': _type == ReceiptType.vendor ? _po : null,
      'source_warehouse': _type == ReceiptType.transfer ? _fromWarehouse : null,
      'indus_warehouse': _type == ReceiptType.indus ? _indusRef.text.trim() : null,
      'challan_no': _challan.text.trim(),
      'vehicle_no': _vehicle.text.trim(),
      'remarks': _remarks.text.trim(),
      'latitude': _pos?.latitude,
      'longitude': _pos?.longitude,
      'items': [
        for (final l in lines)
          {
            'item_code': l.itemCode,
            'item_name': l.name,
            'uom': l.uom,
            'received_qty': l.received,
            'rejected_qty': l.rejected,
            'serial_nos': l.serials.trim(),
            'purchase_order_item': l.poItem,
          }
      ],
      'photos': [
        for (final p in _photos) {'path': p.path, 'caption': p.caption}
      ],
    };
    final title = '${_type.short}${_challan.text.trim().isEmpty ? '' : ' · ${_challan.text.trim()}'} · ${lines.length} item(s)';
    final r = await Outbox.instance.submit(OutboxKind.materialReceipt, widget.siteId, title, payload);
    if (!mounted) return;
    setState(() => _busy = false);
    await showSubmitResult(context, r, 'material receipt');
    if (mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<Session>();
    return Scaffold(
      appBar: AppBar(title: Text('Material Receipt · ${widget.siteId}')),
      body: Form(
        key: _form,
        child: ListView(padding: const EdgeInsets.only(bottom: 120), children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: SegmentedButton<ReceiptType>(
              segments: [
                for (final t in ReceiptType.values)
                  ButtonSegment(value: t, icon: Icon(t.icon), label: Text(t.short, style: const TextStyle(fontSize: 12))),
              ],
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (v) => _setType(v.first),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
            child: Wrap(spacing: 8, runSpacing: 8, children: [
              ActionChip(
                avatar: const Icon(Icons.event),
                label: Text(fmtDate(_date)),
                onPressed: () async {
                  final now = DateTime.now();
                  final d = await showDatePicker(
                      context: context, initialDate: _date, firstDate: now.subtract(const Duration(days: 7)), lastDate: now);
                  if (d != null) setState(() => _date = d);
                },
              ),
              GpsChip(onFix: (p) => _pos = p),
            ]),
          ),
          if (_type == ReceiptType.vendor) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: _openPos.isEmpty
                  ? const Text('No open Purchase Orders for this site. Ask the purchase team to tag the PO with this site / project.')
                  : DropdownButtonFormField<String>(
                      initialValue: _po,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Purchase Order', prefixIcon: Icon(Icons.receipt_long)),
                      items: [
                        for (final p in _openPos)
                          DropdownMenuItem(
                            value: p['name'] as String,
                            child: Text('${p['name']} · ${p['supplier_name'] ?? p['supplier']}', overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      validator: (v) => v == null ? 'Select the PO' : null,
                      onChanged: _selectPo,
                    ),
            ),
            if (_loadingPo) const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
          ],
          if (_type == ReceiptType.transfer)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: DropdownButtonFormField<String>(
                initialValue: s.warehouses.contains(_fromWarehouse) ? _fromWarehouse : null,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Sent from warehouse', prefixIcon: Icon(Icons.warehouse_outlined)),
                items: [for (final w in s.warehouses) DropdownMenuItem(value: w, child: Text(w, overflow: TextOverflow.ellipsis))],
                validator: (v) => v == null ? 'Select the warehouse' : null,
                onChanged: (v) => _fromWarehouse = v,
              ),
            ),
          if (_type == ReceiptType.indus)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: TextFormField(
                controller: _indusRef,
                decoration: const InputDecoration(
                    labelText: 'Indus warehouse / dispatch ref', hintText: 'e.g. MAW - Pune Warehouse', prefixIcon: Icon(Icons.cell_tower)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(children: [
              Expanded(
                child: TextFormField(
                  controller: _challan,
                  decoration: const InputDecoration(labelText: 'Challan / DC no'),
                  validator: (v) => _type != ReceiptType.transfer && (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextFormField(
                  controller: _vehicle,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(labelText: 'Vehicle no'),
                ),
              ),
            ]),
          ),
          SectionTitle('Items received', trailing: Text('${_lines.length}')),
          for (final l in _lines) _lineCard(l),
          if (_type == ReceiptType.transfer) AddButton('Add item', onPressed: _addStockLine),
          if (_type == ReceiptType.indus)
            AddButton('Add Indus material', onPressed: () => setState(() => _lines.add(_Line(uom: 'Nos')))),
          SectionTitle(_type == ReceiptType.transfer ? 'Photos (optional)' : 'Challan & material photos',
              trailing: Text('${_photos.length}')),
          PhotoStrip(photos: _photos, onChanged: () => setState(() {})),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: TextFormField(
              controller: _remarks,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Remarks (shortage, damage...)', alignLabelWithHint: true),
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
                : const Icon(Icons.inventory_2_outlined),
            label: const Text('Report material received'),
          ),
        ),
      ),
    );
  }

  Widget _lineCard(_Line l) {
    final indus = _type == ReceiptType.indus;
    return LineCard(
      key: ObjectKey(l),
      title: indus ? (l.name.isEmpty ? 'Indus material' : l.name) : l.name,
      subtitle: l.pending != null ? 'Pending on PO: ${qty(l.pending)} ${l.uom ?? ''}' : l.itemCode,
      onRemove: () => setState(() => _lines.remove(l)),
      children: [
        if (indus)
          SizedBox(
            width: 260,
            child: TextFormField(
              initialValue: l.name,
              decoration: const InputDecoration(labelText: 'Description (as on Indus DC)', isDense: true),
              onChanged: (v) => l.name = v,
            ),
          ),
        QtyField(value: l.received, label: 'Received', suffix: l.uom, onChanged: (v) => l.received = v),
        if (!indus) QtyField(value: l.rejected, label: 'Damaged / rejected', width: 150, onChanged: (v) => l.rejected = v),
        if (indus)
          SizedBox(
            width: 90,
            child: TextFormField(
              initialValue: l.uom,
              decoration: const InputDecoration(labelText: 'Unit', isDense: true),
              onChanged: (v) => l.uom = v.trim().isEmpty ? null : v.trim(),
            ),
          ),
        SizedBox(
          width: 260,
          child: TextFormField(
            initialValue: l.serials,
            maxLines: 2,
            minLines: 1,
            decoration: const InputDecoration(labelText: 'Serial nos (one per line)', isDense: true),
            onChanged: (v) => l.serials = v,
          ),
        ),
      ],
    );
  }
}
