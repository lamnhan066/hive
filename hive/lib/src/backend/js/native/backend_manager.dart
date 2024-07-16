import 'dart:async';
import 'dart:js_interop';

import 'package:hive/hive.dart';
import 'package:hive/src/backend/js/utils.dart';
import 'package:hive/src/backend/storage_backend.dart';
import 'package:web/web.dart';

import 'storage_backend_js.dart';

/// Opens IndexedDB databases
class BackendManager implements BackendManagerInterface {
  IDBFactory? get indexedDB => window.indexedDB;

  @override
  Future<StorageBackend> open(String name, String? path, bool crashRecovery,
      HiveCipher? cipher, String? collection) async {
    // compatibility for old store format
    final databaseName = collection ?? name;
    final objectStoreName = collection == null ? 'box' : name;

    var db = await completeRequest(indexedDB!.open(databaseName, 1)
      ..onupgradeneeded = (e) {
        var db = e.target.result as IDBDatabase;
        if (!db.objectStoreNames.contains(objectStoreName)) {
          db.createObjectStore(objectStoreName);
        }
      }.toJS);

    // in case the objectStore is not contained, re-open the db and
    // update version
    if (!(db.objectStoreNames ?? []).contains(objectStoreName)) {
      db = await completeRequest(
        indexedDB!.open(databaseName, (db.version ?? 1) + 1)
          ..onupgradeneeded = (e) {
            var db = e.target.result as IDBDatabase;
            if (!db.objectStoreNames.contains(objectStoreName)) {
              db.createObjectStore(objectStoreName);
            }
          }.toJS,
      );
    }

    return StorageBackendJs(db, cipher, objectStoreName);
  }

  @override
  Future<Map<String, StorageBackend>> openCollection(
      Set<String> names,
      String? path,
      bool crashRecovery,
      HiveCipher? cipher,
      String collection) async {
    var db = await completeRequest(indexedDB!.open(collection, 1)
      ..onupgradeneeded = (e) {
        var db = e.target.result as IDBDatabase;
        for (var objectStoreName in names) {
          if (!db.objectStoreNames.contains(objectStoreName)) {
            db.createObjectStore(objectStoreName);
          }
        }
      }.toJS);

    // in case the objectStore is not contained, re-open the db and
    // update version
    if (!(names.every((objectStoreName) =>
        (db.objectStoreNames ?? []).contains(objectStoreName)))) {
      db = await completeRequest(
        indexedDB!.open(collection, (db.version ?? 1) + 1)
          ..onupgradeneeded = (e) {
            var db = e.target.result as IDBDatabase;
            for (var objectStoreName in names) {
              if (!db.objectStoreNames.contains(objectStoreName)) {
                db.createObjectStore(objectStoreName);
              }
            }
          }.toJS,
      );
    }
    return Map.fromEntries(
        names.map((e) => MapEntry(e, StorageBackendJs(db, cipher, e))));
  }

  @override
  Future<void> deleteBox(String name, String? path, String? collection) async {
    // compatibility for old store format
    final databaseName = collection ?? name;
    final objectStoreName = collection == null ? 'box' : name;

    // directly deleting the entire DB if a non-collection Box
    if (collection == null) {
      await completeRequest(indexedDB!.deleteDatabase(databaseName));
    } else {
      final db = await completeRequest(indexedDB!.open(databaseName, 1)
        ..onupgradeneeded = (e) {
          var db = e.target.result as IDBDatabase;
          if (db.objectStoreNames.contains(objectStoreName)) {
            db.deleteObjectStore(objectStoreName);
          }
        }.toJS);
      if ((db.objectStoreNames ?? []).isEmpty) {
        indexedDB!.deleteDatabase(databaseName);
      }
    }
  }

  @override
  Future<bool> boxExists(String name, String? path, String? collection) async {
    // compatibility for old store format
    final databaseName = collection ?? name;
    final objectStoreName = collection == null ? 'box' : name;
    // https://stackoverflow.com/a/17473952
    try {
      var exists = true;
      if (collection == null) {
        await completeRequest(indexedDB!.open(databaseName, 1)
          ..onupgradeneeded = (e) {
            e.target.transaction!.abort();
            exists = false;
          }.toJS);
      } else {
        final db = await completeRequest(indexedDB!.open(collection, 1)
          ..onupgradeneeded = (e) {
            var db = e.target.result as IDBDatabase;
            exists = db.objectStoreNames.contains(objectStoreName);
          }.toJS);
        exists = db.objectStoreNames.contains(objectStoreName);
      }
      return exists;
    } catch (error) {
      return false;
    }
  }
}
