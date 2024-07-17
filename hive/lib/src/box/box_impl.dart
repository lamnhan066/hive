import 'dart:async';

import 'package:hive_plus/hive.dart';
import 'package:hive_plus/src/binary/frame.dart';
import 'package:hive_plus/src/box/box_base_impl.dart';
import 'package:hive_plus/src/object/hive_object.dart';

/// Not part of public API
class BoxImpl<E> extends BoxBaseImpl<E> implements Box<E> {
  /// Not part of public API
  BoxImpl(
    super.hive,
    super.name,
    super.keyComparator,
    super.compactionStrategy,
    super.backend,
  );

  @override
  final bool lazy = false;

  @override
  Iterable<E> get values {
    checkOpen();

    return keystore.getValues();
  }

  @override
  Iterable<E> valuesBetween({dynamic startKey, dynamic endKey}) {
    checkOpen();

    return keystore.getValuesBetween(startKey, endKey);
  }

  @override
  E? get(dynamic key, {E? defaultValue}) {
    checkOpen();

    var frame = keystore.get(key);
    if (frame != null) {
      return frame.value as E?;
    } else {
      if (defaultValue != null && defaultValue is HiveObjectMixin) {
        defaultValue.init(key, this);
      }
      return defaultValue;
    }
  }

  @override
  E? getAt(int index) {
    checkOpen();

    return keystore.getAt(index)?.value as E?;
  }

  @override
  Future<void> putAll(
    Map<dynamic, E> kvPairs, {
    bool notify = true,
  }) {
    var frames = <Frame>[];
    for (var key in kvPairs.keys) {
      frames.add(Frame(key, kvPairs[key]));
    }

    return _writeFrames(frames, notify: notify);
  }

  @override
  Future<void> deleteAll(Iterable<dynamic> keys, {bool notify = true}) {
    var frames = <Frame>[];
    for (var key in keys) {
      if (keystore.containsKey(key)) {
        frames.add(Frame.deleted(key));
      }
    }

    return _writeFrames(frames, notify: notify);
  }

  Future<void> _writeFrames(
    List<Frame> frames, {
    bool notify = true,
  }) async {
    checkOpen();

    if (!keystore.beginTransaction(frames, notify: notify)) return;

    try {
      await backend.writeFrames(frames);
      keystore.commitTransaction();
    } catch (e) {
      keystore.cancelTransaction();
      rethrow;
    }

    await performCompactionIfNeeded();
  }

  @override
  Map<dynamic, E> toMap() {
    var map = <dynamic, E>{};
    for (var frame in keystore.frames) {
      map[frame.key] = frame.value as E;
    }
    return map;
  }

  @override
  Future<void> flush() async {
    await backend.flush();
  }
}
