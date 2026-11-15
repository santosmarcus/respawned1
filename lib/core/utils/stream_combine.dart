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
