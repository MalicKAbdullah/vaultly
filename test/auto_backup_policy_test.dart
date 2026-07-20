import 'package:core_backup/core_backup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final base = DateTime(2026, 7, 5, 10, 30);

  group('AutoBackupPolicy.isDue', () {
    test('never due when interval is off', () {
      expect(
        AutoBackupPolicy.isDue(
          interval: BackupInterval.off,
          lastBackupAt: null,
          now: base,
        ),
        isFalse,
      );
    });

    test('due immediately when there has never been a backup', () {
      for (final interval in [
        BackupInterval.daily,
        BackupInterval.weekly,
        BackupInterval.monthly,
      ]) {
        expect(
          AutoBackupPolicy.isDue(
            interval: interval,
            lastBackupAt: null,
            now: base,
          ),
          isTrue,
          reason: interval.name,
        );
      }
    });

    test('daily: not due before 24h, due at exactly 24h', () {
      expect(
        AutoBackupPolicy.isDue(
          interval: BackupInterval.daily,
          lastBackupAt: base,
          now: base.add(const Duration(hours: 23, minutes: 59)),
        ),
        isFalse,
      );
      expect(
        AutoBackupPolicy.isDue(
          interval: BackupInterval.daily,
          lastBackupAt: base,
          now: base.add(const Duration(hours: 24)),
        ),
        isTrue,
      );
    });

    test('weekly: due after 7 days', () {
      expect(
        AutoBackupPolicy.isDue(
          interval: BackupInterval.weekly,
          lastBackupAt: base,
          now: base.add(const Duration(days: 6, hours: 23)),
        ),
        isFalse,
      );
      expect(
        AutoBackupPolicy.isDue(
          interval: BackupInterval.weekly,
          lastBackupAt: base,
          now: base.add(const Duration(days: 7)),
        ),
        isTrue,
      );
    });

    test('monthly: due on the same day next month', () {
      final last = DateTime(2026, 7, 5, 10, 30);
      expect(
        AutoBackupPolicy.isDue(
          interval: BackupInterval.monthly,
          lastBackupAt: last,
          now: DateTime(2026, 8, 5, 10, 29),
        ),
        isFalse,
      );
      expect(
        AutoBackupPolicy.isDue(
          interval: BackupInterval.monthly,
          lastBackupAt: last,
          now: DateTime(2026, 8, 5, 10, 30),
        ),
        isTrue,
      );
    });
  });

  group('AutoBackupPolicy.nextDue', () {
    test('off has no next due date', () {
      expect(
        AutoBackupPolicy.nextDue(
          interval: BackupInterval.off,
          lastBackupAt: base,
        ),
        isNull,
      );
    });

    test('daily and weekly add fixed durations', () {
      expect(
        AutoBackupPolicy.nextDue(
          interval: BackupInterval.daily,
          lastBackupAt: base,
        ),
        base.add(const Duration(days: 1)),
      );
      expect(
        AutoBackupPolicy.nextDue(
          interval: BackupInterval.weekly,
          lastBackupAt: base,
        ),
        base.add(const Duration(days: 7)),
      );
    });
  });

  group('AutoBackupPolicy.addCalendarMonth', () {
    test('normal month addition preserves day and time', () {
      expect(
        AutoBackupPolicy.addCalendarMonth(DateTime(2026, 7, 5, 10, 30)),
        DateTime(2026, 8, 5, 10, 30),
      );
    });

    test('clamps Jan 31 to Feb 28 in a non-leap year', () {
      expect(
        AutoBackupPolicy.addCalendarMonth(DateTime(2026, 1, 31)),
        DateTime(2026, 2, 28),
      );
    });

    test('clamps Jan 31 to Feb 29 in a leap year', () {
      expect(
        AutoBackupPolicy.addCalendarMonth(DateTime(2028, 1, 31)),
        DateTime(2028, 2, 29),
      );
    });

    test('rolls over December into January of the next year', () {
      expect(
        AutoBackupPolicy.addCalendarMonth(DateTime(2026, 12, 15, 8)),
        DateTime(2027, 1, 15, 8),
      );
    });
  });
}
