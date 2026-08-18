import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'spool_storage.dart';

/// Keeps spooled reports as files on the device.
///
/// Two files per report, sharing an id: `<id>.png` and `<id>.json`. The
/// screenshot is written first and the metadata last, so **the metadata file
/// is the completion marker**. A report killed mid-write leaves a lone image,
/// which [sweepIncomplete] removes rather than uploading a screenshot with
/// nothing attached to it.
class DiskSpoolStorage implements SpoolStorage {
  DiskSpoolStorage({Future<Directory> Function()? directory})
      : _resolveDirectory = directory ?? _defaultDirectory;

  final Future<Directory> Function() _resolveDirectory;
  Directory? _cached;

  /// Application support rather than documents or cache.
  ///
  /// Documents is user-visible on iOS and synced to iCloud, and spooled
  /// reports hold screenshots and logs. Cache can be purged by the system at
  /// any moment, which would silently lose reports the reporter believes they
  /// sent.
  static Future<Directory> _defaultDirectory() async {
    final base = await getApplicationSupportDirectory();
    return Directory('${base.path}/squawk/spool');
  }

  Future<Directory> _directory() async {
    final existing = _cached;
    if (existing != null) return existing;

    final dir = await _resolveDirectory();
    if (!dir.existsSync()) await dir.create(recursive: true);
    return _cached = dir;
  }

  File _json(Directory dir, String id) => File('${dir.path}/$id.json');
  File _image(Directory dir, String id) => File('${dir.path}/$id.png');

  @override
  Future<List<SpoolEntry>> list() async {
    final dir = await _directory();

    final entries = <SpoolEntry>[];
    for (final file in (await dir.list().toList()).whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;

      final id = _idOf(file);
      final entry = await _readEntry(dir, id);
      // A file we cannot parse is debris, not a report. Dropping it beats
      // failing every future drain on the same entry.
      if (entry == null) {
        await _deleteFiles(dir, id);
        continue;
      }
      entries.add(entry);
    }

    entries.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return entries;
  }

  /// The metadata alone — deliberately never the screenshot, which is read
  /// one entry at a time in [load] so a listing costs kilobytes, not the
  /// whole queue's worth of images.
  Future<SpoolEntry?> _readEntry(Directory dir, String id) async {
    final data = await _readMeta(dir, id);
    if (data == null) return null;

    try {
      return SpoolEntry(
        id: id,
        capturedAt: DateTime.parse(data['capturedAt']! as String),
        attempts: (data['attempts'] as num?)?.toInt() ?? 0,
        lastAttemptAt: switch (data['lastAttemptAt']) {
          final String at => DateTime.parse(at),
          _ => null,
        },
      );
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, Object?>?> _readMeta(Directory dir, String id) async {
    try {
      if (!_image(dir, id).existsSync()) return null;

      final data = jsonDecode(await _json(dir, id).readAsString());
      return data is Map<String, Object?> ? data : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<SpooledReport?> load(String id) async {
    final dir = await _directory();

    try {
      final data = await _readMeta(dir, id);
      if (data == null) return null;

      return SpooledReport(
        id: id,
        capturedAt: DateTime.parse(data['capturedAt']! as String),
        attempts: (data['attempts'] as num?)?.toInt() ?? 0,
        lastAttemptAt: switch (data['lastAttemptAt']) {
          final String at => DateTime.parse(at),
          _ => null,
        },
        metadata: (data['metadata'] as Map).cast<String, Object?>(),
        screenshot: await _image(dir, id).readAsBytes(),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(SpooledReport report) async {
    final dir = await _directory();

    // Image first, metadata last — see the class comment.
    await _image(dir, report.id).writeAsBytes(report.screenshot, flush: true);
    await _json(dir, report.id).writeAsString(
      jsonEncode({
        'capturedAt': report.capturedAt.toIso8601String(),
        'attempts': report.attempts,
        if (report.lastAttemptAt != null)
          'lastAttemptAt': report.lastAttemptAt!.toIso8601String(),
        'metadata': report.metadata,
      }),
      flush: true,
    );
  }

  @override
  Future<void> recordAttempt(
    String id, {
    required int attempts,
    required DateTime at,
  }) async {
    final dir = await _directory();

    // Only the metadata file is touched: rewriting a multi-megabyte
    // screenshot to bump a counter would wear the disk for nothing.
    final data = await _readMeta(dir, id);
    if (data == null) return;

    data['attempts'] = attempts;
    data['lastAttemptAt'] = at.toIso8601String();
    await _json(dir, id).writeAsString(jsonEncode(data), flush: true);
  }

  @override
  Future<void> delete(String id) async => _deleteFiles(await _directory(), id);

  @override
  Future<void> sweepIncomplete() async {
    final dir = await _directory();

    for (final file in (await dir.list().toList()).whereType<File>()) {
      if (!file.path.endsWith('.png')) continue;

      final id = _idOf(file);
      if (!_json(dir, id).existsSync()) await file.delete();
    }
  }

  Future<void> _deleteFiles(Directory dir, String id) async {
    for (final file in [_json(dir, id), _image(dir, id)]) {
      if (file.existsSync()) await file.delete();
    }
  }

  String _idOf(File file) =>
      file.uri.pathSegments.last.replaceAll(RegExp(r'\.(json|png)$'), '');
}

int _idSequence = 0;

/// Ids that sort by capture time, so the spool drains oldest-first without
/// opening every file. The counter breaks the tie between two captures in
/// the same microsecond, which would otherwise silently overwrite each other.
String spoolId(DateTime at) {
  final stamp = at.toUtc().microsecondsSinceEpoch.toString().padLeft(20, '0');
  final seq = (_idSequence++).toUnsigned(16).toRadixString(16).padLeft(4, '0');
  return '$stamp-$seq';
}
