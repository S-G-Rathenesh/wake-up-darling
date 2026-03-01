import 'package:cloud_firestore/cloud_firestore.dart';

/// Tracks relationship wake statistics in Firestore.
///
/// Couple document fields (under `stats` map):
///   totalWakeAttempts, currentStreak, longestStreak,
///   lastWakeStatus, lastWakeTime, activeLogId
///
/// Sub-collection: couples/{coupleId}/wake_logs/{logId}
///   triggeredBy, createdAt, status (pending/woke/ignored), wokeAt/ignoredAt
class WakeStatsService {
  static final _db = FirebaseFirestore.instance;

  // ─── Write helpers ────────────────────────────────────────────────────────

  /// Called when the Wake Partner button is pressed.
  /// Creates a wake_log entry and increments totalWakeAttempts.
  static Future<void> recordWakeAttempt({
    required String coupleId,
    required String triggeredByUid,
  }) async {
    if (coupleId.isEmpty) return;

    final coupleRef = _db.collection('couples').doc(coupleId);
    final logRef = coupleRef.collection('wake_logs').doc();

    final batch = _db.batch();
    batch.set(logRef, {
      'triggeredBy': triggeredByUid,
      'createdAt': Timestamp.now(),
      'status': 'pending',
    });

    batch.update(coupleRef, {
      'stats.totalWakeAttempts': FieldValue.increment(1),
      'stats.lastWakeStatus': 'pending',
      'stats.lastWakeTime': Timestamp.now(),
      'stats.activeLogId': logRef.id,
    });

    await batch.commit();
  }

  /// Called when the sleeper taps STOP — counted as a successful wake.
  /// Increments the streak and updates the active log to 'woke'.
  static Future<void> recordWoke({required String coupleId}) async {
    if (coupleId.isEmpty) return;

    final coupleRef = _db.collection('couples').doc(coupleId);
    final snap = await coupleRef.get();
    final data = snap.data() ?? {};
    final statsMap = (data['stats'] as Map<String, dynamic>?) ?? {};
    final logId = statsMap['activeLogId']?.toString() ?? '';
    final currentStreak = (statsMap['currentStreak'] ?? 0) as int;
    final longestStreak = (statsMap['longestStreak'] ?? 0) as int;
    final newStreak = currentStreak + 1;

    final batch = _db.batch();

    if (logId.isNotEmpty) {
      batch.update(coupleRef.collection('wake_logs').doc(logId), {
        'status': 'woke',
        'wokeAt': Timestamp.now(),
      });
    }

    batch.update(coupleRef, {
      'stats.currentStreak': newStreak,
      'stats.longestStreak':
          newStreak > longestStreak ? newStreak : longestStreak,
      'stats.lastWakeStatus': 'woke',
      'stats.lastWakeTime': Timestamp.now(),
      'stats.activeLogId': FieldValue.delete(),
    });

    await batch.commit();
  }

  /// Called after 60 seconds if the alarm was not dismissed.
  /// Resets the current streak to 0.
  static Future<void> recordIgnored({required String coupleId}) async {
    if (coupleId.isEmpty) return;

    final coupleRef = _db.collection('couples').doc(coupleId);
    final snap = await coupleRef.get();
    final statsMap =
        ((snap.data() ?? {})['stats'] as Map<String, dynamic>?) ?? {};
    final logId = statsMap['activeLogId']?.toString() ?? '';

    final batch = _db.batch();

    if (logId.isNotEmpty) {
      batch.update(coupleRef.collection('wake_logs').doc(logId), {
        'status': 'ignored',
        'ignoredAt': Timestamp.now(),
      });
    }

    batch.update(coupleRef, {
      'stats.currentStreak': 0,
      'stats.lastWakeStatus': 'ignored',
      'stats.lastWakeTime': Timestamp.now(),
      'stats.activeLogId': FieldValue.delete(),
    });

    await batch.commit();
  }

  /// Deletes all wake_logs and resets every stat counter to zero.
  static Future<void> clearWakeLogs({required String coupleId}) async {
    if (coupleId.isEmpty) return;

    final coupleRef = _db.collection('couples').doc(coupleId);
    final logsSnap = await coupleRef.collection('wake_logs').get();

    // Firestore batches are limited to 500 writes; split if needed.
    const batchLimit = 499;
    var batch = _db.batch();
    int writes = 0;

    for (final doc in logsSnap.docs) {
      batch.delete(doc.reference);
      writes++;
      if (writes >= batchLimit) {
        await batch.commit();
        batch = _db.batch();
        writes = 0;
      }
    }

    batch.update(coupleRef, {
      'stats.totalWakeAttempts': 0,
      'stats.currentStreak': 0,
      'stats.longestStreak': 0,
      'stats.lastWakeStatus': FieldValue.delete(),
      'stats.lastWakeTime': FieldValue.delete(),
      'stats.activeLogId': FieldValue.delete(),
    });

    await batch.commit();
  }

  // ─── Read helpers ─────────────────────────────────────────────────────────

  /// Real-time stream of the couple document (for stats card).
  static Stream<DocumentSnapshot<Map<String, dynamic>>> streamStats(
      String coupleId) {
    return _db.collection('couples').doc(coupleId).snapshots();
  }
}
