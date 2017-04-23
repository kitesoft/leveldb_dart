
import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:leveldb/leveldb.dart';

Future<LevelDB> _openTestDB({int index: 0, bool shared: false}) async {
  Directory d = new Directory('/tmp/test-level-db-dart-$index');
  if (d.existsSync()) {
    await d.delete(recursive: true);
  }
  return (await LevelDB.open('/tmp/test-level-db-dart-$index', shared: shared));
}

const Matcher _isClosedError = const _ClosedMatcher();

class _ClosedMatcher extends TypeMatcher {
  const _ClosedMatcher() : super("LevelDBClosedError");
  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) => item is LevelClosedError;
}

const Matcher _isInvalidArgumentError = const _InvalidArgumentMatcher();

class _InvalidArgumentMatcher extends TypeMatcher {
  const _InvalidArgumentMatcher() : super("LevelInvalidArgumentError");
  @override
  bool matches(dynamic item, Map<dynamic, dynamic> matchState) => item is LevelInvalidArgumentError;
}

/// tests
void main() {
  test('LevelDB', () async {
    LevelDB db = await _openTestDB();

    db.put("k1", "v");
    db.put("k2", "v");

    expect(db.get("k1"), equals("v"));
    List<dynamic> keys = db.getItems().keys.toList();
    expect(keys.first, equals("k1"));

    String v = db.get("DOESNOTEXIST");
    expect(v, equals(null));

    // All keys
    keys = db.getItems().keys.toList();
    expect(keys.length, equals(2));
    keys = db.getItems(gte: "k1").keys.toList();
    expect(keys.length, equals(2));
    keys = db.getItems(gt: "k1").keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(gt: "k0").keys.toList();
    expect(keys.length, equals(2));

    keys = db.getItems(gt: "k5").keys.toList();
    expect(keys.length, equals(0));
    keys = db.getItems(gte: "k5").keys.toList();
    expect(keys.length, equals(0));

    keys = db.getItems(limit: 1).keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(lte: "k2").keys.toList();
    expect(keys.length, equals(2));
    keys = db.getItems(lt: "k2").keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(gt: "k1", lt: "k2").keys.toList();
    expect(keys.length, equals(0));

    keys = db.getItems(gte: "k1", lt: "k2").keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(gt: "k1", lte: "k2").keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(gte: "k1", lte: "k2").keys.toList();
    expect(keys.length, equals(2));

    // Test with LevelEncodingNone
    Uint8List key = new Uint8List(2);
    key[0] = "k".codeUnitAt(0);
    key[1] = "1".codeUnitAt(0);
    keys = db.getItems(gt: key, keyEncoding: LevelEncoding.none).keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(gte: key, keyEncoding: LevelEncoding.none).keys.toList();
    expect(keys.length, equals(2));

    key[1] = "2".codeUnitAt(0);
    keys = db.getItems(gt: key, keyEncoding: LevelEncoding.none).keys.toList();
    expect(keys.length, equals(0));

    keys = db.getItems(gte: key, keyEncoding: LevelEncoding.none).keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(lt: key, keyEncoding: LevelEncoding.none).keys.toList();
    expect(keys.length, equals(1));

    keys = db.getItems(lt: key, keyEncoding: LevelEncoding.none).values.toList();
    expect(keys.length, equals(1));

    db.close();
  });

  test('LevelDB delete', () async {
    LevelDB db = await _openTestDB();
    try {
      db.put("k1", "v");
      db.put("k2", "v");

      db.delete("k1");

      expect(db.get("k1"), equals(null));
      expect(db.getItems().length, 1);
    } finally {
      db.close();
    }
  });

  test('TWO DBS', () async {
    LevelDB db1 = await _openTestDB();
    LevelDB db2 = await _openTestDB(index: 1);

    db1.put("a", "1");

    String v = await db2.get("a");
    expect(v, equals(null));

    db1.close();
    db2.close();
  });

  test('Usage after close()', () async {
    LevelDB db1 = await _openTestDB();
    db1.close();

    expect(() => db1.get("SOME KEY"), throwsA(_isClosedError));
    expect(() => db1.delete("SOME KEY"), throwsA(_isClosedError));
    expect(() => db1.put("SOME KEY", "SOME KEY"), throwsA(_isClosedError));
    expect(() => db1.close(), throwsA(_isClosedError));

    try {
      for (LevelItem _ in db1.getItems()) {
        expect(true, equals(false)); // Should not happen.
      }
    } on LevelClosedError {
      expect(true, equals(true)); // Should happen.
    }
  });

  test('DB locking throws IOError', () async {
    LevelDB db1 = await _openTestDB();
    try {
      await _openTestDB();
      expect(true, equals(false)); // Should not happen. The db is locked.
    } on LevelIOError {
      expect(true, equals(true)); // Should happen.
    } finally {
      db1.close();
    }
  });

  test('Exception inside iteration', () async {
    LevelDB db1 = await _openTestDB();
    db1.put("a", "1");
    db1.put("b", "1");
    db1.put("c", "1");

    try {
      for (LevelItem _ in db1.getItems()) {
        throw new Exception("OH NO");
      }
    } catch (e) {
      // Pass
    } finally {
      db1.close();
    }
  });

  test('Test with None encoding', () async {
    LevelDB db1 = await _openTestDB();
    Uint8List v = new Uint8List.fromList(UTF8.encode("key1"));

    db1.put(v, v, keyEncoding: LevelEncoding.none, valueEncoding: LevelEncoding.none);

    String s = await db1.get("key1");
    expect(s, equals("key1"));

    String s2 = await db1.get("key1", keyEncoding: LevelEncoding.ascii);
    expect(s2, equals("key1"));

    Uint8List v2 = await db1.get(v, keyEncoding: LevelEncoding.none, valueEncoding: LevelEncoding.none);
    expect(v2, equals(v));

    db1.delete(v, keyEncoding: LevelEncoding.none);

    db1.close();
  });

  test('Close inside iteration', () async {
    LevelDB db1 = await _openTestDB();
    db1.put("a", "1");
    db1.put("b", "1");

    bool isClosedSeen = false;

    try {
      for (LevelItem _ in db1.getItems()) {
        db1.close();
      }
    } on LevelClosedError catch (_) {
      isClosedSeen = true;
    }

    expect(isClosedSeen, equals(true));
  });

  test('Test no create if missing', () async {
    expect(LevelDB.open('/tmp/test-level-db-dart-DOES-NOT-EXIST', createIfMissing: false), throwsA(_isInvalidArgumentError));
  });

  test('Test error if exists', () async {

    LevelDB db = await LevelDB.open('/tmp/test-level-db-dart-exists');
    db.close();
    expect(LevelDB.open('/tmp/test-level-db-dart-exists', errorIfExists: true), throwsA(_isInvalidArgumentError));
  });

  test('LevelDB sync iterator', () async {
    LevelDB db = await _openTestDB();

    db.put("k1", "v");
    db.put("k2", "v");

    // All keys
    List<LevelItem> items = db.getItems().toList();
    expect(items.length, equals(2));
    expect(items.map((LevelItem i) => i.key).toList(), equals(<String>["k1", "k2"]));
    expect(items.map((LevelItem i) => i.value).toList(), equals(<String>["v", "v"]));

    items = db.getItems(keyEncoding: LevelEncoding.none, valueEncoding: LevelEncoding.none).toList();
    expect(items.first.key, <int>[107, 49]);

    items = db.getItems(gte: "k1").toList();
    expect(items.length, equals(2));
    items = db.getItems(gt: "k1").toList();
    expect(items.length, equals(1));

    items = db.getItems(gt: "k0").toList();
    expect(items.length, equals(2));

    items = db.getItems(gt: "k5").toList();
    expect(items.length, equals(0));
    items = db.getItems(gte: "k5").toList();
    expect(items.length, equals(0));

    items = db.getItems(limit: 1).toList();
    expect(items.length, equals(1));

    items = db.getItems(lte: "k2").toList();
    expect(items.length, equals(2));
    items = db.getItems(lt: "k2").toList();
    expect(items.length, equals(1));

    items = db.getItems(gt: "k1", lt: "k2").toList();
    expect(items.length, equals(0));

    items = db.getItems(gte: "k1", lt: "k2").toList();
    expect(items.length, equals(1));

    items = db.getItems(gt: "k1", lte: "k2").toList();
    expect(items.length, equals(1));

    items = db.getItems(gte: "k1", lte: "k2").toList();
    expect(items.length, equals(2));

    String val = "bv-12345678901234567890123456789012345678901234567890123456789012345678901234567890";
    db.put("a", val);
    LevelItem item = db.getItems(lte: "a").first;
    expect(item.value.length, val.length);

    String longKey = "";
    for (int _ in new Iterable<int>.generate(10)) {
      longKey += val;
    }
    db.put(longKey, longKey);
    item = db.getItems(gt: "a", lte: "c").first;
    expect(item.value.length, longKey.length);

    db.close();
  });

  test('LevelDB sync iterator use after close', () async {
    LevelDB db = await _openTestDB();

    db.put("k1", "v");
    db.put("k2", "v");

    // All keys
    Iterator<LevelItem> it = db.getItems().iterator;
    it.moveNext();

    db.close();

    expect(() => it.moveNext(), throwsA(_isClosedError));
  });

  test('LevelDB sync iterator current == null', () async {
    LevelDB db = await _openTestDB();

    db.put("k1", "v");
    LevelIterator it = db.getItems().iterator;
    expect(it.current, null);
    expect(it.currentKey, null);
    expect(it.currentValue, null);

    it.moveNext();
    expect(it.current.key, "k1");
    expect(it.currentKey, "k1");
    expect(it.currentValue, "v");
    expect(it.moveNext(), false);
    expect(it.current, null);
    for (int _ in new Iterable<int>.generate(10)) {
      expect(it.moveNext(), false); // Dart requires that it is safe to call moveNext after the end.
      expect(it.current, null);
      expect(it.currentKey, null);
      expect(it.currentValue, null);
    }
    db.close();
  });


  test('Shared db in same isolate', () async {
    LevelDB db = await _openTestDB(shared: true);
    LevelDB db1 = await _openTestDB(shared: true);

    db.put("k1", "v");
    expect(db1.get("k1"), "v");

    // Close the 1st reference. It cannot be used now.
    db.close();
    expect(() => db.get("SOME KEY"), throwsA(_isClosedError));

    // db1 Should still work.
    db1.put("k1", "v2");
    expect(db1.get("k1"), "v2");

    // close the 2nd reference. It cannot be used.
    db1.close();
    expect(() => db1.get("SOME KEY"), throwsA(_isClosedError));
  });


  test('Shared db removed from map', () async {
    // Test that a shared db is correctly removed from the shared map when closed.
    LevelDB db = await _openTestDB(shared: true);
    db.close();

    // Since the db is closed above it will be remove from the shared map and therefore
    // this will open a new db and we are allowed to read/write keys.
    LevelDB db1 = await _openTestDB(shared: true);
    db1.put("k1", "v");
    expect(db1.get("k1"), "v");
  });

}