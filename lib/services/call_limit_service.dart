import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Manages daily call usage limits per couple.
///
/// Scenario: 2 pairs, Zego free tier 10 000 min / 30 days.
/// Safe per-pair daily budget: 130 minutes total.
///   - Voice: 90 min/day
///   - Video: 40 min/day
///
/// Usage is tracked in Firestore:
///   Collection : `call_usage`
///   Document   : `{coupleId}_{yyyyMMdd}`
///
/// Structure:
/// ```json
/// {
///   "coupleId": "...",
///   "date": "20260301",
///   "voiceSeconds": 1200,
///   "videoSeconds": 600
/// }
/// ```
///
/// Auto-resets daily because each day gets a new document ID.
class CallLimitService {
  CallLimitService._();

  static final _db = FirebaseFirestore.instance;

  // ─── Daily limits ─────────────────────────────────────────────────────
  static const int maxVoiceMinutesPerDay = 90;
  static const int maxVideoMinutesPerDay = 40;

  static const int _voiceLimitSeconds = maxVoiceMinutesPerDay * 60; // 5 400 s
  static const int _videoLimitSeconds = maxVideoMinutesPerDay * 60; // 2 400 s

  // ─── Helpers ──────────────────────────────────────────────────────────

  /// Today's date key in `yyyyMMdd` format.
  static String _todayKey() => DateFormat('yyyyMMdd').format(DateTime.now());

  /// Firestore document ID for [coupleId] today.
  static String _docId(String coupleId) => '${coupleId}_${_todayKey()}';

  /// Reference to today's usage document.
  static DocumentReference _docRef(String coupleId) =>
      _db.collection('call_usage').doc(_docId(coupleId));

  // ─── Read usage ───────────────────────────────────────────────────────

  /// Returns today's usage for [coupleId] as
  /// `{ "voiceSeconds": int, "videoSeconds": int }`.
  static Future<Map<String, dynamic>> getTodayUsage(String coupleId) async {
    try {
      final snap = await _docRef(coupleId).get();
      if (snap.exists) {
        final data = snap.data() as Map<String, dynamic>? ?? {};
        return {
          'voiceSeconds': data['voiceSeconds'] as int? ?? 0,
          'videoSeconds': data['videoSeconds'] as int? ?? 0,
        };
      }
    } catch (e) {
      debugPrint('[CallLimit] getTodayUsage error: $e');
    }
    return {'voiceSeconds': 0, 'videoSeconds': 0};
  }

  /// Whether [coupleId] is still allowed to start a call of the given type.
  static Future<bool> canStartCall(String coupleId, bool isVideo) async {
    final usage = await getTodayUsage(coupleId);
    if (isVideo) {
      final usedMinutes = (usage['videoSeconds'] as int) / 60;
      return usedMinutes < maxVideoMinutesPerDay;
    } else {
      final usedMinutes = (usage['voiceSeconds'] as int) / 60;
      return usedMinutes < maxVoiceMinutesPerDay;
    }
  }

  /// Returns how many seconds remain for [coupleId] today.
  static Future<int> getRemainingSeconds(
      String coupleId, bool isVideo) async {
    final usage = await getTodayUsage(coupleId);
    if (isVideo) {
      final used = usage['videoSeconds'] as int;
      return (_videoLimitSeconds - used).clamp(0, _videoLimitSeconds);
    } else {
      final used = usage['voiceSeconds'] as int;
      return (_voiceLimitSeconds - used).clamp(0, _voiceLimitSeconds);
    }
  }

  // ─── Write usage ──────────────────────────────────────────────────────

  /// Records [durationSeconds] of call usage for [coupleId].
  static Future<void> addCallUsage(
    String coupleId,
    bool isVideo,
    int durationSeconds,
  ) async {
    if (durationSeconds <= 0) return;

    final ref = _docRef(coupleId);
    final field = isVideo ? 'videoSeconds' : 'voiceSeconds';

    try {
      await _db.runTransaction((tx) async {
        final snap = await tx.get(ref);
        if (snap.exists) {
          final current =
              (snap.data() as Map<String, dynamic>?)?[field] as int? ?? 0;
          tx.update(ref, {
            field: current + durationSeconds,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        } else {
          tx.set(ref, {
            'coupleId': coupleId,
            'date': _todayKey(),
            'voiceSeconds': isVideo ? 0 : durationSeconds,
            'videoSeconds': isVideo ? durationSeconds : 0,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
      });
    } catch (e) {
      debugPrint('[CallLimit] addCallUsage error: $e');
    }
  }
}
