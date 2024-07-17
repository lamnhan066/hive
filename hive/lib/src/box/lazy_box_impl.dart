// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: invalid_use_of_visible_for_testing_member

import 'package:hive_plus/hive.dart';
import 'package:hive_plus/src/binary/frame.dart';
import 'package:hive_plus/src/box/box_base_impl.dart';
import 'package:hive_plus/src/object/hive_object.dart';

/// Not part of public API
class LazyBoxImpl<E> extends BoxBaseImpl<E> implements LazyBox<E> {
  /// Not part of public API
  LazyBoxImpl(
    super.hive,
    super.name,
    super.keyComparator,
    super.compactionStrategy,
    super.backend,
  );

  @override
  final bool lazy = true;

  @override
  Future<E?> get(dynamic key, {E? defaultValue}) async {
    checkOpen();

    var frame = keystore.get(key);

    if (frame != null) {
      var value = await backend.readValue(frame);
      if (value is HiveObjectMixin) {
        value.init(key, this);
      }
      return value as E?;
    } else {
      if (defaultValue != null && defaultValue is HiveObjectMixin) {
        defaultValue.init(key, this);
      }
      return defaultValue;
    }
  }

  @override
  Future<E?> getAt(int index) {
    return get(keystore.keyAt(index));
  }

  @override
  Future<void> putAll(
    Map<dynamic, dynamic> kvPairs, {
    bool notify = true,
  }) async {
    checkOpen();

    var frames = <Frame>[];
    for (var key in kvPairs.keys) {
      frames.add(Frame(key, kvPairs[key]));
      if (key is int) {
        keystore.updateAutoIncrement(key);
      }
    }

    if (frames.isEmpty) return;
    await backend.writeFrames(frames);

    for (var frame in frames) {
      if (frame.value is HiveObjectMixin) {
        (frame.value as HiveObjectMixin).init(frame.key, this);
      }
      keystore.insert(
        frame,
        lazy: true,
        notify: notify,
      );
    }

    await performCompactionIfNeeded();
  }

  @override
  Future<void> deleteAll(
    Iterable<dynamic> keys, {
    bool notify = true,
  }) async {
    checkOpen();

    var frames = <Frame>[];
    for (var key in keys) {
      if (keystore.containsKey(key)) {
        frames.add(Frame.deleted(key));
      }
    }

    if (frames.isEmpty) return;
    await backend.writeFrames(frames);

    for (var frame in frames) {
      keystore.insert(
        frame,
        notify: notify,
      );
    }

    await performCompactionIfNeeded();
  }

  @override
  Future<void> flush() async {
    await backend.flush();
  }
}
