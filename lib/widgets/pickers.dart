import 'dart:async';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../services/site_api.dart';

/// Bottom sheet with a search box over a local list.
Future<T?> pickFromList<T>(
  BuildContext context, {
  required String title,
  required List<T> items,
  required String Function(T) label,
  String Function(T)? subtitle,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SearchSheet<T>(
      title: title,
      search: (q) async => items
          .where((e) =>
              label(e).toLowerCase().contains(q.toLowerCase()) ||
              (subtitle?.call(e).toLowerCase().contains(q.toLowerCase()) ?? false))
          .toList(),
      label: label,
      subtitle: subtitle,
    ),
  );
}

/// Bottom sheet that searches stock items on the server (cached offline).
Future<Map<String, dynamic>?> pickStockItem(BuildContext context) {
  return showModalBottomSheet<Map<String, dynamic>>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SearchSheet<Map<String, dynamic>>(
      title: 'Select material',
      search: SiteApi.searchItems,
      label: (e) => (e['item_name'] ?? e['item_code']).toString(),
      subtitle: (e) => '${e['item_code']} · ${e['uom'] ?? ''}',
    ),
  );
}

class _SearchSheet<T> extends StatefulWidget {
  const _SearchSheet({required this.title, required this.search, required this.label, this.subtitle});

  final String title;
  final Future<List<T>> Function(String) search;
  final String Function(T) label;
  final String Function(T)? subtitle;

  @override
  State<_SearchSheet<T>> createState() => _SearchSheetState<T>();
}

class _SearchSheetState<T> extends State<_SearchSheet<T>> {
  List<T> _items = [];
  String? _error;
  bool _loading = true;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _run('');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _run(String q) async {
    setState(() => _loading = true);
    try {
      final r = await widget.search(q);
      if (mounted) {
        setState(() {
          _items = r;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e is ApiException ? e.message : '$e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              autofocus: false,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Search', isDense: true),
              onChanged: (q) {
                _debounce?.cancel();
                _debounce = Timer(const Duration(milliseconds: 300), () => _run(q));
              },
            ),
          ),
          const SizedBox(height: 8),
          if (_loading) const LinearProgressIndicator(),
          if (_error != null) Padding(padding: const EdgeInsets.all(16), child: Text(_error!)),
          Expanded(
            child: ListView.separated(
              itemCount: _items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final e = _items[i];
                return ListTile(
                  title: Text(widget.label(e), maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: widget.subtitle == null
                      ? null
                      : Text(widget.subtitle!(e), maxLines: 2, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.pop(context, e),
                );
              },
            ),
          ),
        ]),
      ),
    );
  }
}
