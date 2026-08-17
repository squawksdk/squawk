import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

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
  Future<List<SpooledReport>> list() async {
    final dir = await _directory();

    final reports = <SpooledReport>[];
    for (final file in dir.listSync().whereType<File>()) {
      if (!file.path.endsWith('.json')) continue;

      final report = await _read(dir, file);
      // A file we cannot parse is debris, not a report. Dropping it beats
      // failing every future drain on the same entry.
      if (report == null) {
        await _deleteFiles(dir, _idOf(file));
        continue;
      }
      reports.add(report);
    }

    reports.sort((a, b) => a.capturedAt.compareTo(b.capturedAt));
    return reports;
  }

  Future<SpooledReport?> _read(Directory dir, File jsonFile) async {
    try {
      final id = _idOf(jsonFile);
      final image = _image(dir, id);
      if (!image.existsSync()) return null;

      final data = jsonDecode(await jsonFile.readAsString());
      if (data is! Map<String, Object?>) return null;

      return SpooledReport(
        id: id,
        capturedAt: DateTime.parse(data['capturedAt']! as String),
        attempts: (data['attempts'] as num?)?.toInt() ?? 0,
        metadata: (data['metadata'] as Map).cast<String, Object?>(),
        screenshot: await image.readAsBytes(),
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
        'metadata': report.metadata,
      }),
      flush: true,
    );
  }

  @override
  Future<void> delete(String id) async => _deleteFiles(await _directory(), id);

  @override
  Future<void> sweepIncomplete() async {
    final dir = await _directory();

    for (final file in dir.listSync().whereType<File>()) {
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

/// Ids that sort by capture time, so the spool drains oldest-first without
/// opening every file.
String spoolId(DateTime at, Uint8List screenshot) {
  final stamp = at.toUtc().microsecondsSinceEpoch.toString().padLeft(20, '0');
  final salt = Object.hash(screenshot.length, at.microsecondsSinceEpoch)
      .toUnsigned(16)
      .toRadixString(16);
  return '$stamp-$salt';
}
