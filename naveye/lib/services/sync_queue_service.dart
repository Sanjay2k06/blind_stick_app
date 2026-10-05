import 'dart:math';

class SyncQueueService {
  static const List<String> validStatuses = <String>['pending', 'syncing', 'synced', 'failed'];

  static bool isValidStatus(String? value) =>
      value != null && validStatuses.contains(value.trim().toLowerCase());

  static String normaliseStatus(String? value) {
    final trimmed = (value ?? 'pending').trim().toLowerCase();
    return validStatuses.contains(trimmed) ? trimmed : 'pending';
  }

  static int retryDelaySeconds(int retryCount) {
    final base = 15;
    final capped = min(300, base * (1 << min(retryCount, 5)));
    return capped;
  }

  static String nextStatus(String status, int retryCount, int lastAttemptMsAgo) {
    final normalised = normaliseStatus(status);
    if (normalised == 'synced') return 'synced';
    if (normalised == 'syncing') return 'syncing';

    // If a sync has been attempted more than the current backoff window, retry it.
    final delayMs = retryDelaySeconds(retryCount) * 1000;
    if (lastAttemptMsAgo >= delayMs || retryCount == 0) {
      return 'syncing';
    }
    return 'pending';
  }
}
