import 'dart:async';

/// Emits the latest value of every stream once each has emitted, then again
/// whenever any of them does. Used to merge the separate queries that
/// firestore.rules requires (own organization, unowned pool, ...).
Stream<List<T>> combineLatest<T>(List<Stream<T>> streams) {
  if (streams.isEmpty) return Stream.value(<T>[]);
  final subs = <StreamSubscription<T>>[];
  final values = List<T?>.filled(streams.length, null);
  final seen = List<bool>.filled(streams.length, false);
  late final StreamController<List<T>> controller;
  controller = StreamController<List<T>>(
    onListen: () {
      for (var i = 0; i < streams.length; i++) {
        subs.add(streams[i].listen(
          (v) {
            values[i] = v;
            seen[i] = true;
            if (seen.every((s) => s)) controller.add(List<T>.from(values));
          },
          onError: controller.addError,
        ));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}

/// For each [source] event, switches to the stream [mapper] returns,
/// cancelling the previous one (rxdart's switchMap). Unlike `asyncExpand`,
/// a new source event is never stuck behind an inner stream that doesn't
/// end (Firestore snapshot streams never do).
Stream<R> switchMap<T, R>(Stream<T> source, Stream<R> Function(T value) mapper) {
  late final StreamController<R> controller;
  StreamSubscription<T>? outer;
  StreamSubscription<R>? inner;
  controller = StreamController<R>(
    onListen: () {
      outer = source.listen(
        (v) {
          inner?.cancel();
          inner = mapper(v).listen(controller.add, onError: controller.addError);
        },
        onError: controller.addError,
        onDone: () async {
          await inner?.asFuture<void>().catchError((_) {});
          await controller.close();
        },
      );
    },
    onPause: () {
      outer?.pause();
      inner?.pause();
    },
    onResume: () {
      outer?.resume();
      inner?.resume();
    },
    onCancel: () async {
      await inner?.cancel();
      await outer?.cancel();
    },
  );
  return controller.stream;
}
