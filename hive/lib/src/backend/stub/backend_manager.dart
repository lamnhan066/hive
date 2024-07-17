import 'dart:async';

import 'package:hive_plus/hive_plus.dart';
import 'package:hive_plus/src/backend/storage_backend.dart';

/// Not part of public API
class BackendManager implements BackendManagerInterface {
  static BackendManager select(
          [HiveStorageBackendPreference? backendPreference]) =>
      BackendManager();

  @override
  Future<StorageBackend> open(String name, String? path, bool crashRecovery,
      HiveCipher? cipher, String? collection) {
    throw UnimplementedError();
  }

  @override
  Future<Map<String, StorageBackend>> openCollection(
      Set<String> names,
      String? path,
      bool crashRecovery,
      HiveCipher? cipher,
      String? collection) {
    throw UnimplementedError();
  }

  @override
  Future<void> deleteBox(String name, String? path, String? collection) {
    throw UnimplementedError();
  }

  @override
  Future<bool> boxExists(String name, String? path, String? collection) {
    throw UnimplementedError();
  }
}
