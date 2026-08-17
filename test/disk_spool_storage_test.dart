import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:squawk/src/upload/disk_spool_storage.dart';
import 'package:squawk/src/upload/spool_storage.dart';

/// Exercises the real filesystem in a temporary directory. The spool's rules
/// are tested against a fake elsewhere; this is about durability.
void main() {
  late Directory dir;
  late DiskSpoolStorage storage;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('squawk_spool_test');
    storage = DiskSpoolStorage(directory: () async => dir);
  });

  tearDown(() => dir.deleteSync(recursive: true));

  SpooledReport entry(String id, {DateTime? at, int attempts = 0}) =>
      SpooledReport(
        id: id,
        capturedAt: at ?? DateTime.utc(2026, 8, 17, 12),
        metadata: {'text': 'the button is red', 'buildMode': 'release'},
        screenshot: Uint8List.fromList([137, 80, 78, 71, 1, 2, 3]),
        attempts: attempts,
      );

  test('a saved report survives being read back', () async {
    await storage.save(entry('a', attempts: 3));

    final read = (await storage.list()).single;

    expect(read.id, 'a');
    expect(read.attempts, 3);
    expect(read.metadata['text'], 'the button is red');
    expect(read.screenshot, [137, 80, 78, 71, 1, 2, 3]);
  });

  test('entries come back oldest first', () async {
    await storage.save(entry('late', at: DateTime.utc(2026, 8, 17, 18)));
    await storage.save(entry('early', at: DateTime.utc(2026, 8, 17, 6)));

    expect((await storage.list()).map((r) => r.id), ['early', 'late']);
  });

  test('delete removes both files', () async {
    await storage.save(entry('a'));

    await storage.delete('a');

    expect(await storage.list(), isEmpty);
    expect(dir.listSync(), isEmpty);
  });

  // The metadata file is the completion marker. An image with no metadata is
  // what a crash mid-write leaves behind.
  test('a half-written entry is never returned as a report', () async {
    File('${dir.path}/orphan.png').writeAsBytesSync([1, 2, 3]);

    expect(await storage.list(), isEmpty);
  });

  test('sweeping removes crash debris from the disk', () async {
    File('${dir.path}/orphan.png').writeAsBytesSync([1, 2, 3]);
    await storage.save(entry('good'));

    await storage.sweepIncomplete();

    expect(File('${dir.path}/orphan.png').existsSync(), isFalse);
    expect((await storage.list()).single.id, 'good');
  });

  // A corrupt file must not fail every future drain on the same entry.
  test('an unreadable entry is discarded rather than retried forever',
      () async {
    File('${dir.path}/bad.png').writeAsBytesSync([1]);
    File('${dir.path}/bad.json').writeAsStringSync('{not json');

    expect(await storage.list(), isEmpty);
    expect(dir.listSync(), isEmpty, reason: 'both files are cleaned up');
  });

  test('metadata survives a round trip through JSON', () async {
    await storage.save(entry('a'));

    final raw =
        jsonDecode(File('${dir.path}/a.json').readAsStringSync()) as Map;

    expect(raw['metadata'], {
      'text': 'the button is red',
      'buildMode': 'release',
    });
  });

  test('ids sort by capture time', () {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final earlier = spoolId(DateTime.utc(2026, 8, 17, 6), bytes);
    final later = spoolId(DateTime.utc(2026, 8, 17, 18), bytes);

    expect(earlier.compareTo(later), lessThan(0));
  });
}
