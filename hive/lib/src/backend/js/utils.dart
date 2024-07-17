import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart';

Future<T> completeRequest<T>(IDBRequest request) {
  var completer = Completer<T>.sync();
  void onsuccess(JSAny e) {
    T result = request.result as T;
    completer.complete(result);
  }

  request.onsuccess = onsuccess.toJS;
  request.onerror = (JSAny e) {
    completer.completeError(e);
  }.toJS;
  return completer.future;
}

Stream<T> cursorStreamFromResult<T extends IDBCursorWithValue>(
    IDBRequest request, bool? autoAdvance) {
  // TODO: need to guarantee that the controller provides the values
  // immediately as waiting until the next tick will cause the transaction to
  // close.
  var controller = StreamController<T>(sync: true);

  //TODO: Report stacktrace once issue 4061 is resolved.
  request.onerror = (MessageEvent e) {
    controller.addError(e);
  }.toJS;

  request.onsuccess = (MessageEvent e) {
    T? cursor = request.result as dynamic;
    if (cursor == null) {
      controller.close();
    } else {
      controller.add(cursor);
      if (autoAdvance == true && controller.hasListener) {
        cursor.continue_();
      }
    }
  }.toJS;
  return controller.stream;
}
