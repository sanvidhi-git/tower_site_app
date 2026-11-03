import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

import '../core/format.dart';
import '../services/outbox.dart';
import '../services/location.dart';

/// Compact numeric field used inside line-item cards.
class QtyField extends StatelessWidget {
  const QtyField({super.key, required this.value, required this.onChanged, this.label = 'Qty', this.suffix, this.width = 110});
  final double value;
  final ValueChanged<double> onChanged;
  final String label;
  final String? suffix;
  final double width;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        child: TextFormField(
          initialValue: value == 0 ? '' : qty(value),
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: label, suffixText: suffix, isDense: true),
          onChanged: (v) => onChanged(double.tryParse(v.trim()) ?? 0),
        ),
      );
}

/// Card for one line in a list (BOQ qty, material, expense) with a remove button.
class LineCard extends StatelessWidget {
  const LineCard({super.key, required this.title, this.subtitle, required this.onRemove, required this.children});
  final String title;
  final String? subtitle;
  final VoidCallback onRemove;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 6, 4, 12),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w600), maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (subtitle != null)
                      Text(subtitle!, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  ]),
                ),
              ),
              IconButton(onPressed: onRemove, icon: const Icon(Icons.delete_outline), tooltip: 'Remove'),
            ]),
            const SizedBox(height: 8),
            Padding(padding: const EdgeInsets.only(right: 10), child: Wrap(spacing: 10, runSpacing: 10, children: children)),
          ]),
        ),
      );
}

class AddButton extends StatelessWidget {
  const AddButton(this.label, {super.key, required this.onPressed});
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        child: OutlinedButton.icon(onPressed: onPressed, icon: const Icon(Icons.add), label: Text(label)),
      );
}

/// Captures GPS when the form opens and shows the fix; tap to retry.
class GpsChip extends StatefulWidget {
  const GpsChip({super.key, required this.onFix});
  final ValueChanged<Position?> onFix;

  @override
  State<GpsChip> createState() => _GpsChipState();
}

class _GpsChipState extends State<GpsChip> {
  Position? _pos;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _get();
  }

  Future<void> _get() async {
    setState(() => _busy = true);
    final p = await LocationService.current();
    if (!mounted) return;
    setState(() {
      _pos = p;
      _busy = false;
    });
    widget.onFix(p);
  }

  @override
  Widget build(BuildContext context) {
    final label = _busy
        ? 'Getting location...'
        : _pos == null
            ? 'No GPS - tap to retry'
            : 'Location tagged (±${_pos!.accuracy.toStringAsFixed(0)} m)';
    return ActionChip(
      avatar: _busy
          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
          : Icon(_pos == null ? Icons.location_off : Icons.location_on, color: _pos == null ? Colors.red : Colors.green),
      label: Text(label),
      onPressed: _busy ? null : _get,
    );
  }
}

/// Dialog after submitting: sent now, or saved for later.
Future<void> showSubmitResult(BuildContext context, SubmitResult r, String what) {
  final (IconData icon, Color color, String title, String body) = r.queued
      ? r.error != null
          ? (Icons.error_outline, Colors.red, 'Not accepted', 'The server rejected this $what:\n\n${r.error}\n\nIt is kept in Submissions so you can retry or discard it.')
          : (Icons.cloud_queue, Colors.orange, 'Saved on phone', 'No network right now. Your $what is saved and will be sent automatically when you are back online.')
      : (Icons.check_circle, Colors.green, 'Sent', 'Your $what ${r.serverName} reached the office and is waiting for Project Manager approval.');
  return showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(icon, color: color, size: 40),
      title: Text(title),
      content: Text(body),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
