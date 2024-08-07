import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:hive_plus/hive_plus.dart';
import 'package:hive_plus/src/backend/js/utils.dart';
import 'package:hive_plus/src/backend/storage_backend.dart';
import 'package:hive_plus/src/binary/binary_reader_impl.dart';
import 'package:hive_plus/src/binary/binary_writer_impl.dart';
import 'package:hive_plus/src/binary/frame.dart';
import 'package:hive_plus/src/box/keystore.dart';
import 'package:hive_plus/src/registry/type_registry_impl.dart';
import 'package:meta/meta.dart';
import 'package:web/web.dart';

/// Handles all IndexedDB related tasks
class StorageBackendJs extends StorageBackend {
  static const _bytePrefix = [0x90, 0xA9];
  final IDBDatabase _db;
  final HiveCipher? _cipher;
  final String objectStoreName;

  TypeRegistry _registry;

  /// Not part of public API
  StorageBackendJs(this._db, this._cipher, this.objectStoreName,
      [this._registry = TypeRegistryImpl.nullImpl]);

  @override
  String? get path => null;

  @override
  bool supportsCompaction = false;

  bool _isEncoded(Uint8List bytes) {
    return bytes.length >= _bytePrefix.length &&
        bytes[0] == _bytePrefix[0] &&
        bytes[1] == _bytePrefix[1];
  }

  /// Not part of public API
  @visibleForTesting
  Future<dynamic> encodeValue(Frame frame) async {
    var value = frame.value;
    if (_cipher == null) {
      if (value == null) {
        return value;
      } else if (value is Uint8List) {
        if (!_isEncoded(value)) {
          return value.buffer;
        }
      } else if (value is num ||
          value is bool ||
          value is String ||
          value is List<num> ||
          value is List<bool> ||
          value is List<String>) {
        return value;
      }
    }

    var frameWriter = BinaryWriterImpl(_registry);
    frameWriter.writeByteList(_bytePrefix, writeLength: false);

    if (_cipher == null) {
      frameWriter.write(value);
    } else {
      await frameWriter.writeEncrypted(value, _cipher);
    }

    var bytes = frameWriter.toBytes();
    var sublist = bytes.sublist(0, bytes.length);
    return sublist.buffer;
  }

  /// Not part of public API
  @visibleForTesting
  Future<dynamic> decodeValue(dynamic value) async {
    if (value is ByteBuffer) {
      var bytes = Uint8List.view(value);
      if (_isEncoded(bytes)) {
        var reader = BinaryReaderImpl(bytes, _registry);
        reader.skip(2);
        if (_cipher == null) {
          return reader.read();
        } else {
          return reader.readEncrypted(_cipher);
        }
      } else {
        return bytes;
      }
    } else {
      return value;
    }
  }

  /// Not part of public API
  @visibleForTesting
  IDBObjectStore getStore(bool write) {
    return _db
        .transaction(objectStoreName as JSAny, write ? 'readwrite' : 'readonly')
        .objectStore(objectStoreName);
  }

  /// Not part of public API
  @visibleForTesting
  Future<List<dynamic>> getKeys({bool cursor = false}) {
    var store = getStore(false);

    if (store.has('getAllKeys') && !cursor) {
      var completer = Completer<List<dynamic>>();
      var request = getStore(false).getAllKeys(null);
      request.onsuccess = (MessageEvent _) {
        completer.complete(request.result as List<dynamic>?);
      }.toJS;
      request.onerror = (MessageEvent _) {
        completer.completeError(request.error!);
      }.toJS;
      return completer.future;
    } else {
      return cursorStreamFromResult(store.openCursor(), true)
          .map((e) => e.key)
          .toList();
    }
  }

  /// Not part of public API
  @visibleForTesting
  Future<Iterable<dynamic>> getValues({bool cursor = false}) {
    var store = getStore(false);

    if (store.has('getAll') && !cursor) {
      var completer = Completer<Iterable<dynamic>>();
      var request = store.getAll(null);
      request.onsuccess = ((MessageEvent _) async {
        var futures = (request.result as List).map(decodeValue);
        completer.complete(await Future.wait(futures));
      } as void Function(MessageEvent))
          .toJS;
      request.onerror = (MessageEvent _) {
        completer.completeError(request.error!);
      }.toJS;
      return completer.future;
    } else {
      return cursorStreamFromResult(store.openCursor(), true)
          .map((e) => e.value)
          .toList();
    }
  }

  @override
  Future<int> initialize(
      TypeRegistry registry, Keystore keystore, bool lazy) async {
    _registry = registry;
    var keys = await getKeys();
    if (!lazy) {
      var i = 0;
      var values = await getValues();
      for (var value in values) {
        var key = keys[i++];
        keystore.insert(Frame(key, value), notify: false);
      }
    } else {
      for (var key in keys) {
        keystore.insert(Frame.lazy(key), notify: false);
      }
    }

    return 0;
  }

  @override
  Future<dynamic> readValue(Frame frame) async {
    var value = await completeRequest(getStore(false).get(frame.key));
    return decodeValue(value);
  }

  @override
  Future<void> writeFrames(List<Frame> frames) async {
    var store = getStore(true);
    for (var frame in frames) {
      if (frame.deleted) {
        await completeRequest(store.delete(frame.key));
      } else {
        await completeRequest(store.put(await encodeValue(frame), frame.key));
      }
    }
  }

  @override
  Future<List<Frame>> compact(Iterable<Frame> frames) {
    throw UnsupportedError('Not supported');
  }

  @override
  Future<void> clear() {
    return completeRequest(getStore(true).clear());
  }

  @override
  Future<void> close() {
    _db.close();
    return Future.value();
  }

  @override
  Future<void> deleteFromDisk() async {
    final indexDB = window.indexedDB;

    // directly deleting the entire DB if a non-collection Box
    if (_db.objectStoreNames.length == 1) {
      await completeRequest(indexDB.deleteDatabase(_db.name));
    } else {
      IDBDatabase db = await completeRequest(indexDB.open(_db.name, 1)
        ..onupgradeneeded = (MessageEvent e) {
          var db = (e.target as IDBRequest).result as IDBDatabase;
          if (db.objectStoreNames.contains(objectStoreName)) {
            db.deleteObjectStore(objectStoreName);
          }
        }.toJS);
      if (db.objectStoreNames.length == 0) {
        await completeRequest(indexDB.deleteDatabase(_db.name));
      }
    }
  }

  @override
  Future<void> flush() => Future.value();
}
