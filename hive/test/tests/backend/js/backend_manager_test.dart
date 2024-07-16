@TestOn('browser')
library;

import 'dart:js_interop';

import 'package:hive/src/backend/js/backend_manager.dart';
import 'package:hive/src/backend/js/utils.dart';
import 'package:test/test.dart';
import 'package:web/web.dart';

Future<IDBDatabase> _openDb() async {
  return await completeRequest(window.indexedDB.open('testBox', 1)
    ..onupgradeneeded = (e) {
      var db = e.target.result as IDBDatabase;
      if (!db.objectStoreNames.contains('box')) {
        db.createObjectStore('box');
      }
    }.toJS);
}

void main() {
  group('BackendManager', () {
    group('.boxExists()', () {
      test('returns true', () async {
        var backendManager = BackendManager.select();
        var db = await _openDb();
        db.close();
        expect(await backendManager.boxExists('testBox', null, null), isTrue);
      });

      test('returns false', () async {
        var backendManager = BackendManager.select();
        var boxName = 'notexists-${DateTime.now().millisecondsSinceEpoch}';
        expect(await backendManager.boxExists(boxName, null, null), isFalse);
      });
    });
  });
}
