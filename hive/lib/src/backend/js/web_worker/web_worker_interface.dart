import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:hive_plus/hive.dart';
import 'package:hive_plus/src/backend/js/web_worker/web_worker_operation.dart';
import 'package:web/web.dart';

class WebWorkerInterface {
  final WebWorkerStackTraceCallback onStackTrace;
  final Worker _worker;
  final Random _random = Random();

  final Map<double, Completer> _queries = {};

  WebWorkerInterface(String href, this.onStackTrace)
      : _worker = Worker(href.toJS) {
    print('[hive] Created Worker($href)');
    _worker.onmessage = _handleMessage.toJS;
  }

  Future<T> query<T>(String command, String database,
      [String? objectStore, Object? key, Object? value, String? transaction]) {
    final label = _random.nextDouble();
    final completer = Completer<T>();
    _queries[label] = completer;

    final operation = WebWorkerOperation(
      command: command,
      label: label,
      database: database,
      objectStore: objectStore,
      key: key,
      value: value,
      transaction: transaction,
    );

    _worker.postMessage(operation.toJson().toJSBox);
    return completer.future.timeout(Duration(seconds: 45));
  }

  void _handleMessage(MessageEvent event) {
    final label = (event.data as Map)['label'];
    // don't forget handling errors of our second thread...
    if (label == 'stacktrace') {
      final origin = (event.data as Map)['origin'];
      final completer = _queries[origin];

      final error = (event.data as Map)['error']!;

      Future.value(
        onStackTrace.call((event.data as Map)['stacktrace'] as String),
      ).then(
        (stackTrace) => completer?.completeError(
          WebWorkerError(error: error, stackTrace: stackTrace),
        ),
      );
    }
    final completer = _queries[label];
    var response = (event.data as Map)['response'];
    completer?.complete(response);
    _queries.remove(label);
  }
}

class WebWorkerError extends Error {
  /// the error thrown in the web worker. Usually a [String]
  final Object? error;

  /// de-serialized [StackTrace]
  @override
  final StackTrace stackTrace;

  WebWorkerError({required this.error, required this.stackTrace});

  @override
  String toString() {
    return '$error, $stackTrace';
  }
}
