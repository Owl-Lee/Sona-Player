/// Lets only the newest asynchronous request update visible state.
class LatestRequestGate {
  int _latest = 0;

  int begin() => ++_latest;

  bool isCurrent(int request) => request == _latest;
}
