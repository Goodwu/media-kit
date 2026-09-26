/// Orders asynchronous output bind/destroy notifications by complete owner
/// identity. Only the latest live bind may publish output availability.
class CurrentOutputIntent<T> {
  T? _expected;
  int _serial = 0;

  T? get expected => _expected;
  int get serial => _serial;

  int bind(T owner) {
    _expected = owner;
    return ++_serial;
  }

  bool destroy(T owner) {
    if (_expected != owner) return false;
    _expected = null;
    ++_serial;
    return true;
  }

  bool isCurrent(T owner, int serial) =>
      _expected == owner && _serial == serial;
}
