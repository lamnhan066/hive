import 'dart:async';
import 'dart:js_interop';

import 'package:hive_plus/hive_plus.dart';
import 'package:hive_plus/src/backend/js/utils.dart';
import 'package:hive_plus/src/backend/js/web_worker/web_worker_interface.dart';
import 'package:web/web.dart';

import '../../storage_backend.dart';
import 'storage_backend_web_worker.dart';

/// Opens IndexedDB databases
class BackendManagerWebWorker implements BackendManagerInterface {
  final HiveStorageBackendPreferenceWebWorker backendPreference;

  WebWorkerInterface? _interface;

  WebWorkerInterface get interface {
    _interface ??= WebWorkerInterface(
        backendPreference.path, backendPreference.onStackTrace);
    return _interface!;
  }

  BackendManagerWebWorker(this.backendPreference);

  IDBFactory? get indexedDB => window.indexedDB;

  @override
  Future<StorageBackendWebWorker> open(String name, String? path,
      bool crashRecovery, HiveCipher? cipher, String? collection) async {
    // compatibility for old store format
    final databaseName = collection ?? name;
    final objectStoreName = collection == null ? 'box' : name;

    await interface.query('open', databaseName, objectStoreName);
    return StorageBackendWebWorker(
        interface, databaseName, cipher, objectStoreName);
  }

  @override
  Future<Map<String, StorageBackend>> openCollection(
      Set<String> names,
      String? path,
      bool crashRecovery,
      HiveCipher? cipher,
      String collection) async {
    // for collections, create an additional interface
    final interface = WebWorkerInterface(
        backendPreference.path, backendPreference.onStackTrace);
    await interface.query('open', collection, null, null, names);
    return Map.fromEntries(names.map(
      (e) => MapEntry(
        e,
        StorageBackendWebWorker(interface, collection, cipher, e),
      ),
    ));
  }

  @override
  Future<void> deleteBox(String name, String? path, String? collection) async {
    // compatibility for old store format
    final databaseName = collection ?? name;
    final objectStoreName = collection == null ? 'box' : name;

    // cipher doesn't matter on delete operation
    await interface.query('delete', databaseName, objectStoreName);
  }

  @override
  Future<bool> boxExists(String name, String? path, String? collection) async {
    // TODO(TheOneWithTheBraid): migrate into web worker

    // compatibility for old store format
    final databaseName = collection ?? name;
    final objectStoreName = collection == null ? 'box' : name;
    // https://stackoverflow.com/a/17473952
    try {
      var exists = true;
      if (collection == null) {
        await completeRequest(indexedDB!.open(databaseName, 1)
          ..onupgradeneeded = (MessageEvent e) {
            (e.target as IDBRequest).transaction!.abort();
            exists = false;
          }.toJS);
      } else {
        IDBDatabase db = await completeRequest(indexedDB!.open(collection, 1)
          ..onupgradeneeded = (MessageEvent e) {
            var db = (e.target as IDBRequest).result as IDBDatabase;
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
