import '../../../core/utils/latest_request_gate.dart';
import '../../../core/utils/serialized_task_queue.dart';

/// Owns the single command lane used by Sona's native media player.
///
/// A source request is invalidated as soon as a newer explicit selection is
/// made, even when the older native `open` call cannot be cancelled. Once that
/// older call completes, [openLatest] actively discards the stale native
/// source before the next queued command is allowed to run.
class MediaTransportCoordinator {
  final SerializedTaskQueue _commands = SerializedTaskQueue();
  final LatestRequestGate _sourceRequests = LatestRequestGate();

  int beginSourceRequest() => _sourceRequests.begin();

  bool isCurrentSourceRequest(int request) =>
      _sourceRequests.isCurrent(request);

  Future<T> run<T>(Future<T> Function() command) => _commands.run(command);

  /// Opens a media source only when [request] is still the newest request.
  ///
  /// Native players generally cannot cancel an in-progress open. Therefore a
  /// request may become stale while [open] is awaiting. In that case
  /// [discardStale] is awaited before the command lane advances, guaranteeing
  /// that a deleted or superseded source cannot remain loaded underneath the
  /// next visible track.
  Future<bool> openLatest({
    required int request,
    required Future<void> Function() open,
    required Future<void> Function() discardStale,
    required void Function() commit,
  }) async {
    if (!isCurrentSourceRequest(request)) return false;
    try {
      await open();
    } catch (_) {
      // Some native backends throw after they have already replaced the
      // underlying source. If this request was superseded while opening, the
      // partially loaded source is stale and must be unloaded before the lane
      // advances to the newest request.
      if (!isCurrentSourceRequest(request)) await discardStale();
      rethrow;
    }
    if (!isCurrentSourceRequest(request)) {
      await discardStale();
      return false;
    }
    commit();
    return true;
  }
}
