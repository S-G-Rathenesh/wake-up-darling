// ─────────────────────────────────────────────────────────────────────────────
// DEPRECATED: This file is no longer used.
//
// The call screens have been split into separate files:
//   - lib/screens/outgoing_call_screen.dart  (caller side)
//   - lib/screens/incoming_call_screen.dart  (receiver side)
//   - lib/screens/ongoing_call_screen.dart   (active call)
//
// These new screens use [CallRepository] (Firestore signaling only).
// ─────────────────────────────────────────────────────────────────────────────

export 'outgoing_call_screen.dart';
export 'incoming_call_screen.dart';
export 'ongoing_call_screen.dart';
