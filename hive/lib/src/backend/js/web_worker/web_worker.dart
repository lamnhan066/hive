import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';

import 'package:hive/src/backend/js/web_worker/web_worker_operation.dart';
import 'package:web/web.dart';

///
///
/// CAUTION: THIS FILE NEEDS TO BE MANUALLY COMPILED
///
/// 1. in your project, create a file `web/web_worker.dart`
/// 2. add the following contents:
/// ```dart
/// import 'package:hive/hive.dart';
///
/// Future<void> main() => startWebWorker();
/// ```
/// 3. compile the file using:
/// ```shell
/// dart compile js -o web/web_worker.dart.js -m web/web_worker.dart
/// ```
///
/// You should not check in that file into your VCS. Instead, you should compile
/// the web worker in your CI pipeline.
///

@pragma('dart2js:tryInline')
Future<void> startWebWorker() async {
  print('[web worker]: Starting...');
  self.onmessage = (event) async {
    final data = event.data;
    try {
      final operation = WebWorkerOperation.fromJson(Map.from(data as Map));

      void respond([Object? response]) {
        sendResponse(operation.label, response);
      }

      switch (operation.command) {
        case 'open':
          try {
            Set<String> storeNames = {};

            if (operation.objectStore != null) {
              storeNames.add(operation.objectStore!);
            } else if (operation.value is Iterable) {
              storeNames
                  .addAll((operation.value as Iterable).whereType<String>());
            } else {
              storeNames.add('box');
            }

            var version = await getDatabaseVersion(operation.database);

            var db = await _completeRequest(indexedDB!
                .open(operation.database, version)
              ..onupgradeneeded = (e) {
                var db = e.target.result as IDBDatabase;
                for (var objectStoreName in storeNames) {
                  if (!db.objectStoreNames.contains(objectStoreName)) {
                    db.createObjectStore(objectStoreName);
                  }
                }
              }.toJS
              ..onblocked = (e) {
                print('[web worker] Error opening indexed DB: ${event.data}');
              }.toJS);

            // in case the objectStore is not contained, re-open the db and
            // update version
            if (!(storeNames.every((objectStoreName) =>
                (db.objectStoreNames ?? []).contains(objectStoreName)))) {
              db.close();
              version++;
              setDatabaseVersion(operation.database, version);
              db = await _completeRequest(indexedDB!
                  .open(operation.database, version)
                ..onupgradeneeded = (e) {
                  var db = e.target.result as IDBDatabase;
                  for (var objectStoreName in storeNames) {
                    if (!db.objectStoreNames.contains(objectStoreName)) {
                      db.createObjectStore(objectStoreName);
                    }
                  }
                }.toJS
                ..onblocked = (e) {
                  print('[web worker] Error opening indexed DB: ${event.data}');
                }.toJS);
            }
            _databases[operation.database] = db;
            respond(db.name);
          } on Event catch (e, s) {
            print('[web worker]: Runtime error:'
                ' ${(e.target as IDBRequest).error}, $s');
          }
          break;

        case 'close':
          _databases[operation.database]!.close();
          respond();
          break;

        case 'createObjectStore':
          final result = _databases[operation.database]!
              .createObjectStore(operation.objectStore!);
          respond(result);
          break;

        case 'add':
          await _completeRequest(
              getObjectStore(operation.database, operation.objectStore!, true)
                  .add(operation.value as JSAny, operation.key as JSAny));
          respond();
          break;

        case 'clear':
          await _completeRequest(
              getObjectStore(operation.database, operation.objectStore!, true)
                  .clear());
          respond();
          break;

        case 'delete':
          try {
            final db0 = _databases[operation.database] ??
                await _completeRequest(indexedDB!.open(operation.database));

            // directly deleting the entire DB if a non-collection Box
            if (db0!.objectStoreNames.length == 1) {
              await _completeRequest(indexedDB!.deleteDatabase(db0.name));
            } else {
              final db = await _completeRequest(indexedDB!.open(db0.name, 1)
                ..onupgradeneeded = (e) {
                  var db = e.target.result as IDBDatabase;
                  if (db.objectStoreNames.contains(operation.objectStore!)) {
                    db.deleteObjectStore(operation.objectStore!);
                  }
                }.toJS);
              if ((db.objectStoreNames ?? []).isEmpty) {
                await _completeRequest(indexedDB!.deleteDatabase(db0.name));
              }
            }
          } finally {}
          respond();
          break;

        case 'getAll':
          var completer = Completer<List<dynamic>>();
          var request =
              getObjectStore(operation.database, operation.objectStore!, false)
                  .getAll(null);
          request.onsuccess = (_) {
            completer.complete(request.result as List<dynamic>?);
          }.toJS;
          request.onerror = (_) {
            completer.completeError(request.error!);
          }.toJS;
          final result = await completer.future;
          respond(result);
          break;

        case 'getAllKeys':
          var completer = Completer<List<dynamic>>();
          try {
            var request = getObjectStore(
                    operation.database, operation.objectStore!, false)
                .getAllKeys(null);
            request.onsuccess = (_) {
              completer.complete(request.result as List<dynamic>?);
            }.toJS;
            request.onerror = (_) {
              completer.completeError(request.error!);
            }.toJS;
          } catch (e) {
            print('[web worker] $e');
          }
          final result = await completer.future;
          respond(result);
          break;

        case 'put':
          final objectStore =
              getObjectStore(operation.database, operation.objectStore!, true);
          final keys = List.from(operation.key as Iterable);
          final values = List.from(operation.value as Iterable);
          final futures = <Future>[];
          for (var i = 0; i < keys.length; i++) {
            futures.add(_completeRequest(objectStore.put(values[i], keys[i])));
          }
          await Future.wait(futures);

          respond();
          break;

        case 'deleteKey':
          final objectStore =
              getObjectStore(operation.database, operation.objectStore!, true);
          final keys = List.from(operation.key as Iterable);
          final futures = <Future>[];
          for (var i = 0; i < keys.length; i++) {
            futures.add(_completeRequest(objectStore.delete(keys[i])));
          }
          await Future.wait(futures);

          respond();
          break;

        case 'get':
          final store =
              getObjectStore(operation.database, operation.objectStore!, false);
          final response =
              await _completeRequest(store.get(operation.key as JSAny));
          respond(response);

          break;

        case 'startTransaction':
          final db = _databases[operation.database]!;
          // value represents all affected objectStoreNames here, as
          // [operation.objectStore] is not a `List<String>`
          final txn = db.transaction(operation.value as JSAny, 'read-write');
          _transactions[operation.transaction!] = txn;
          respond();
          break;

        case 'stopTransaction':
          _transactions.remove(operation.transaction!);
          respond();
          break;

        default:
          print('[web worker] Unknown command ${operation.command}');
          respond();
          break;
      }
    } on Event catch (e, s) {
      _replyError((e.target as IDBRequest).error, s, data['label'] as double);
    } catch (e, s) {
      _replyError(e, s, data['label'] as double);
    }
  }.toJS;
}

final Map<String, int> _versionCache = {};

Future<int> getDatabaseVersion(String database) async {
  if (_versionCache.isEmpty) {
    final db = await _completeRequest(
        indexedDB!.open('hive_web_worker_database_versions', 1)
          ..onupgradeneeded = (e) {
            final db = (e.target.result as IDBDatabase);
            db.createObjectStore('versions');
          }.toJS);
    _databases['hive_web_worker_database_versions'] = db;
    final txn = db.transaction('versions', 'readonly');

    final versions = await txn.objectStore('versions').getObject('versions');

    if (versions is LinkedHashMap) {
      _versionCache.addAll(versions.cast());
    }
  }
  if (!_versionCache.containsKey(database)) {
    setDatabaseVersion(database, 1);
  }
  return _versionCache[database]!;
}

// caches background put operation of database versions
Future? _putVersionsFuture;

void setDatabaseVersion(String database, int version) {
  _versionCache[database] = version;
  (_putVersionsFuture ?? Future.value(null)).then((value) {
    final db = _databases['hive_web_worker_database_versions']!;
    final txn = db.transaction('versions'.toJS, 'readwrite');
    _putVersionsFuture = _completeRequest(txn
        .objectStore('versions')
        .put(_versionCache.toJSBox, 'versions'.toJS));
    _putVersionsFuture?.then((value) => _putVersionsFuture = null);
  });
}

void sendResponse(double label, dynamic response) {
  try {
    self.postMessage({
      'label': label,
      'response': response,
    }.toJSBox);
  } catch (e, s) {
    print('[web worker] Error responding: $e, $s');
  }
}

void _replyError(Object? error, StackTrace stackTrace, double origin) {
  if (error != null) {
    error = error.toString();
  }
  try {
    self.postMessage({
      'label': 'stacktrace',
      'origin': origin,
      'error': error,
      'stacktrace': stackTrace.toString(),
    }.toJSBox);
  } catch (e, s) {
    print('[web worker] Error responding: $e, $s');
  }
}

/// represents the [WorkerGlobalScope] the worker currently runs in.
@JS('self')
external DedicatedWorkerGlobalScope get self;

IDBFactory? get indexedDB => self.indexedDB;

Map<String, IDBDatabase> _databases = {};

Map<String, IDBTransaction> _transactions = {};

IDBObjectStore getObjectStore(
  String database,
  String box,
  bool write, [
  String? transaction,
]) {
  if (transaction != null) {
    if (_transactions.containsKey(transaction)) {
      return _transactions[transaction]!.objectStore(box);
    } else {
      final txn = _databases[database]!
          .transaction(box.toJS, write ? 'readwrite' : 'readonly');
      _transactions[transaction] = txn;
      return txn.objectStore(box);
    }
  } else {
    return _databases[database]!
        .transaction(box.toJS, write ? 'readwrite' : 'readonly')
        .objectStore(box);
  }
}

Future<T> _completeRequest<T>(IDBRequest request) {
  var completer = Completer<T>.sync();
  void onsuccess(e) {
    T result = request.result as T;
    completer.complete(result);
  }

  request.onsuccess = onsuccess.toJS;
  request.onerror = completer.completeError.toJS;
  return completer.future;
}
