@TestOn('browser')
library;

import 'dart:async' show Future;
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:hive/hive.dart';
import 'package:hive/src/backend/js/native/storage_backend_js.dart';
import 'package:hive/src/backend/js/utils.dart';
import 'package:hive/src/binary/binary_writer_impl.dart';
import 'package:hive/src/binary/frame.dart';
import 'package:hive/src/box/change_notifier.dart';
import 'package:hive/src/box/keystore.dart';
import 'package:hive/src/registry/type_registry_impl.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

import '../../frames.dart';

late final IDBDatabase _nullDatabase;

StorageBackendJs _getBackend({
  IDBDatabase? db,
  HiveCipher? cipher,
  TypeRegistry registry = TypeRegistryImpl.nullImpl,
}) {
  return StorageBackendJs(db ?? _nullDatabase, cipher, 'box', registry);
}

Future<IDBDatabase> _openDb([String name = 'testBox']) async {
  return await completeRequest(window.indexedDB.open(name, 1)
    ..onupgradeneeded = (e) {
      var db = e.target.result as IDBDatabase;
      if (!db.objectStoreNames.contains('box')) {
        db.createObjectStore('box');
      }
    }.toJS);
}

IDBObjectStore _getStore(IDBDatabase db) {
  return db.transaction('box'.toJS, 'readwrite').objectStore('box');
}

Future<IDBDatabase> _getDbWith(Map<String, dynamic> content) async {
  var db = await _openDb();
  var store = _getStore(db);
  await completeRequest(store.clear());
  content.forEach((k, v) => store.put(v, k.toJS));
  return db;
}

void main() async {
  _nullDatabase = await _openDb('nullTestBox');
  group('StorageBackendJs', () {
    test('.path', () {
      expect(_getBackend().path, null);
    });

    group('.encodeValue()', () {
      test('primitive', () async {
        var values = [
          null, 11, 17.25, true, 'hello', //
          [11, 12, 13], [17.25, 17.26], [true, false], ['str1', 'str2'] //
        ];
        var backend = _getBackend();
        for (var value in values) {
          expect(await backend.encodeValue(Frame('key', value)), value);
        }

        var bytes = Uint8List.fromList([1, 2, 3]);
        var buffer =
            await backend.encodeValue(Frame('key', bytes)) as ByteBuffer;
        expect(Uint8List.view(buffer), [1, 2, 3]);
      });

      test('crypto', () async {
        var backend =
            StorageBackendJs(_nullDatabase, testCipher, 'box', testRegistry);
        var i = 0;
        for (var frame in testFrames) {
          var buffer = await backend.encodeValue(frame) as ByteBuffer;
          var bytes = Uint8List.view(buffer);
          expect(bytes.sublist(28),
              [0x90, 0xA9, ...frameValuesBytesEncrypted[i]].sublist(28));
          i++;
        }
      });

      group('non primitive', () {
        test('map', () async {
          var frame = Frame(0, {
            'key': Uint8List.fromList([1, 2, 3]),
            'otherKey': null
          });
          var backend = StorageBackendJs(_nullDatabase, null, 'box');
          var encoded =
              Uint8List.view(await backend.encodeValue(frame) as ByteBuffer);

          var writer = BinaryWriterImpl(TypeRegistryImpl.nullImpl)
            ..write(frame.value);
          expect(encoded, [0x90, 0xA9, ...writer.toBytes()]);
        });

        test('bytes which start with signature', () async {
          var frame = Frame(0, Uint8List.fromList([0x90, 0xA9, 1, 2, 3]));
          var backend = _getBackend();
          var encoded =
              Uint8List.view(await backend.encodeValue(frame) as ByteBuffer);

          var writer = BinaryWriterImpl(TypeRegistryImpl.nullImpl)
            ..write(frame.value);
          expect(encoded, [0x90, 0xA9, ...writer.toBytes()]);
        });
      });
    });

    group('.decodeValue()', () {
      test('primitive', () async {
        var backend = _getBackend();
        expect(await backend.decodeValue(null), null);
        expect(await backend.decodeValue(11), 11);
        expect(await backend.decodeValue(17.25), 17.25);
        expect(await backend.decodeValue(true), true);
        expect(await backend.decodeValue('hello'), 'hello');
        expect(await backend.decodeValue([11, 12, 13]), [11, 12, 13]);
        expect(await backend.decodeValue([17.25, 17.26]), [17.25, 17.26]);

        var bytes = Uint8List.fromList([1, 2, 3]);
        expect(await backend.decodeValue(bytes.buffer), [1, 2, 3]);
      });

      test('crypto', () async {
        var cipher = HiveAesCipher(Uint8List.fromList(List.filled(32, 1)));
        var backend = _getBackend(cipher: cipher, registry: testRegistry);
        var i = 0;
        for (var testFrame in testFrames) {
          var bytes = [0x90, 0xA9, ...frameValuesBytesEncrypted[i]];
          var value =
              await backend.decodeValue(Uint8List.fromList(bytes).buffer);
          expect(value, testFrame.value);
          i++;
        }
      });

      test('non primitive', () async {
        var backend = _getBackend(registry: testRegistry);
        for (var testFrame in testFrames) {
          var bytes = await backend.encodeValue(testFrame);
          var value = await backend.decodeValue(bytes);
          expect(value, testFrame.value);
        }
      });
    });

    group('.getKeys()', () {
      test('with cursor', () async {
        var db = await _getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
        var backend = _getBackend(db: db);

        expect(await backend.getKeys(cursor: true), ['key1', 'key2', 'key3']);
      });

      test('without cursor', () async {
        var db = await _getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
        var backend = _getBackend(db: db);

        expect(await backend.getKeys(), ['key1', 'key2', 'key3']);
      });
    });

    group('.getValues()', () {
      test('with cursor', () async {
        var db = await _getDbWith({'key1': 1, 'key2': null, 'key3': 3});
        var backend = _getBackend(db: db);

        expect(await backend.getValues(cursor: true), [1, null, 3]);
      });

      test('without cursor', () async {
        var db = await _getDbWith({'key1': 1, 'key2': null, 'key3': 3});
        var backend = _getBackend(db: db);

        expect(await backend.getValues(), [1, null, 3]);
      });
    });

    group('.initialize()', () {
      test('not lazy', () async {
        var db = await _getDbWith({'key1': 1, 'key2': null, 'key3': 3});
        var backend = _getBackend(db: db);

        var keystore = Keystore.debug(notifier: ChangeNotifier());
        expect(
            await backend.initialize(
                TypeRegistryImpl.nullImpl, keystore, false),
            0);
        expect(keystore.frames, [
          Frame('key1', 1),
          Frame('key2', null),
          Frame('key3', 3),
        ]);
      });

      test('lazy', () async {
        var db = await _getDbWith({'key1': 1, 'key2': null, 'key3': 3});
        var backend = _getBackend(db: db);

        var keystore = Keystore.debug(notifier: ChangeNotifier());
        expect(
            await backend.initialize(TypeRegistryImpl.nullImpl, keystore, true),
            0);
        expect(keystore.frames, [
          Frame.lazy('key1'),
          Frame.lazy('key2'),
          Frame.lazy('key3'),
        ]);
      });
    });

    test('.readValue()', () async {
      var db = await _getDbWith({'key1': 1, 'key2': null, 'key3': 3});
      var backend = _getBackend(db: db);

      expect(await backend.readValue(Frame('key1', null)), 1);
      expect(await backend.readValue(Frame('key2', null)), null);
    });

    test('.writeFrames()', () async {
      var db = await _getDbWith({});
      var backend = _getBackend(db: db);

      var frames = [Frame('key1', 123), Frame('key2', null)];
      await backend.writeFrames(frames);
      expect(frames, [Frame('key1', 123), Frame('key2', null)]);
      expect(await backend.getKeys(), ['key1', 'key2']);

      await backend.writeFrames([Frame.deleted('key1')]);
      expect(await backend.getKeys(), ['key2']);
    });

    test('.compact()', () async {
      var db = await _getDbWith({});
      var backend = _getBackend(db: db);
      expect(
        () async => await backend.compact({}),
        throwsUnsupportedError,
      );
    });

    test('.clear()', () async {
      var db = await _getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = _getBackend(db: db);
      await backend.clear();
      expect(await backend.getKeys(), []);
    });

    test('.close()', () async {
      var db = await _getDbWith({'key1': 1, 'key2': 2, 'key3': 3});
      var backend = _getBackend(db: db);
      await backend.close();

      await expectLater(() async => await backend.getKeys(), throwsA(anything));
    });
  });
}
