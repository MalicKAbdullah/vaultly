/// How often scheduled backups run.
enum BackupInterval {
  off('Off'),
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly');

  const BackupInterval(this.label);

  final String label;

  static BackupInterval parse(String? raw) => BackupInterval.values.firstWhere(
        (i) => i.name == raw,
        orElse: () => BackupInterval.off,
      );
}

/// Pure scheduling rules for auto-backup. Checked on every successful
/// unlock; a backup runs when the last one is at least one interval old.
abstract final class AutoBackupPolicy {
  /// When the next backup is due, or null when [interval] is off.
  /// A vault that has never been backed up is due immediately.
  static DateTime? nextDue({
    required BackupInterval interval,
    required DateTime? lastBackupAt,
  }) {
    if (interval == BackupInterval.off) return null;
    if (lastBackupAt == null) return DateTime.fromMillisecondsSinceEpoch(0);
    return switch (interval) {
      BackupInterval.off => null,
      BackupInterval.daily => lastBackupAt.add(const Duration(days: 1)),
      BackupInterval.weekly => lastBackupAt.add(const Duration(days: 7)),
      BackupInterval.monthly => addCalendarMonth(lastBackupAt),
    };
  }

  static bool isDue({
    required BackupInterval interval,
    required DateTime? lastBackupAt,
    required DateTime now,
  }) {
    final due = nextDue(interval: interval, lastBackupAt: lastBackupAt);
    if (due == null) return false;
    return !now.isBefore(due);
  }

  /// Adds one calendar month, clamping the day to the target month's length
  /// (Jan 31 → Feb 28/29, etc.). Preserves the time of day.
  static DateTime addCalendarMonth(DateTime date) {
    final year = date.month == 12 ? date.year + 1 : date.year;
    final month = date.month == 12 ? 1 : date.month + 1;
    final lastDay = DateTime(year, month + 1, 0).day;
    final day = date.day > lastDay ? lastDay : date.day;
    return DateTime(
      year,
      month,
      day,
      date.hour,
      date.minute,
      date.second,
      date.millisecond,
    );
  }
}
