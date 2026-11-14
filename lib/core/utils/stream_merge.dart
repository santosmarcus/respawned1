import 'dart:async';

/// Small stream helpers, to avoid pulling in a package for one combinator.
class StreamGroupLite {
  const StreamGroupLite._();

  /// Emits `(a, null)` for each event of [a] and `(null, b)` for each event
  /// of [b], until both are done. Errors from either are passed on.
  static Stream<(A?, B?)> merge2<A, B>(Stream<A> a, Stream<B> b) {
    late StreamController<(A?, B?)> controller;
    StreamSubscription<A>? subA;
    StreamSubscription<B>? subB;
    var open = 2;
    void done() {
      if (--open == 0) controller.close();
    }

    controller = StreamController<(A?, B?)>(
      onListen: () {
        subA = a.listen((v) => controller.add((v, null)), onError: controller.addError, onDone: done);
        subB = b.listen((v) => controller.add((null, v)), onError: controller.addError, onDone: done);
      },
      onPause: () {
        subA?.pause();
        subB?.pause();
      },
      onResume: () {
        subA?.resume();
        subB?.resume();
      },
      onCancel: () async {
        await subA?.cancel();
        await subB?.cancel();
      },
    );
    return controller.stream;
  }
}
