import 'dart:typed_data';

import 'package:hive_plus/hive_plus.dart';
import 'package:hive_plus/src/binary/binary_reader_impl.dart';
import 'package:hive_plus/src/box/keystore.dart';

/// Not part of public API
class FrameHelper {
  /// Not part of public API
  Future<int> framesFromBytes(
    Uint8List bytes,
    Keystore? keystore,
    TypeRegistry registry,
    HiveCipher? cipher,
  ) async {
    var reader = BinaryReaderImpl(bytes, registry);

    while (reader.availableBytes != 0) {
      var frameOffset = reader.usedBytes;

      var frame = await reader.readFrame(
        cipher: cipher,
        lazy: false,
        frameOffset: frameOffset,
      );
      if (frame == null) return frameOffset;

      keystore!.insert(frame, notify: false);
    }

    return -1;
  }
}
