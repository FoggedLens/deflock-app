import 'dart:async';

class Debouncer {
  Debouncer(this.duration);
  final Duration duration;
  Timer? _timer;

  void call(void Function() action) {
    _timer?.cancel();
    _timer = Timer(duration, action);
  }

  void dispose() => _timer?.cancel();
}

