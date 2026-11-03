import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Tiny JSON-file store in the app's private documents folder. Used for the offline
/// cache (sites, BOQ, open POs) and the outbox of reports waiting to be sent.
class JsonStore {
  JsonStore._();

  static Directory? _dir;

  static Future<Directory> dir() async {
    if (_dir != null) return _dir!;
    final base = await getApplicationDocumentsDirectory();
    _dir = Directory('${base.path}/sanvidhi_site');
    await _dir!.create(recursive: true);
    return _dir!;
  }

  static Future<File> _file(String key) async => File('${(await dir()).path}/$key.json');

  static Future<dynamic> read(String key) async {
    try {
      final f = await _file(key);
      if (!await f.exists()) return null;
      return jsonDecode(await f.readAsString());
    } catch (_) {
      return null;
    }
  }

  static Future<void> write(String key, dynamic value) async {
    final f = await _file(key);
    final tmp = File('${f.path}.tmp');
    await tmp.writeAsString(jsonEncode(value), flush: true);
    await tmp.rename(f.path);
  }

  static Future<void> delete(String key) async {
    final f = await _file(key);
    if (await f.exists()) await f.delete();
  }

  /// Folder for photos taken for reports that are not yet uploaded.
  static Future<Directory> photoDir() async {
    final d = Directory('${(await dir()).path}/photos');
    await d.create(recursive: true);
    return d;
  }

  static Future<void> clearAll() async {
    final d = await dir();
    if (await d.exists()) await d.delete(recursive: true);
    _dir = null;
  }
}
