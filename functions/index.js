/**
 * Wake Up Darling V2 – Firebase Cloud Functions
 *
 * sendAlarmWake:
 *   Triggered whenever a couple document is updated.
 *   - alarm.status == "emergency"  → HIGH-PRIORITY FCM data message (emergency wake)
 *   - alarm.status == "scheduled"  → FCM data message (schedule alarm on partner device)
 *   - voiceWake field changed       → FCM data message (voice wake request)
 *   - activeCall field changed      → FCM data message (incoming call)
 */

const { onDocumentUpdated } = require("firebase-functions/v2/firestore");
const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

// ─── Helper: send high-priority FCM data message ──────────────────────────────
async function sendFCM(token, data) {
  const message = {
    token,
    android: { priority: "high", ttl: 3600000 },
    data,
  };
  try {
    const response = await admin.messaging().send(message);
    console.log(`FCM sent – msgId=${response}`);
  } catch (err) {
    console.error("FCM send failed", err);
  }
}

// ─── Helper: look up user's FCM token ─────────────────────────────────────────
async function getFcmToken(uid) {
  const snap = await admin.firestore().collection("users").doc(uid).get();
  return snap.data()?.fcmToken ?? null;
}

// ═══════════════════════════════════════════════════════════════════════════════
// 1. Alarm & Voice Wake & Incoming Call  (couple doc update trigger)
// ═══════════════════════════════════════════════════════════════════════════════
exports.sendEmergencyWake = onDocumentUpdated(
  "couples/{coupleId}",
  async (event) => {
    const before = event.data.before.data() ?? {};
    const after  = event.data.after.data()  ?? {};
    const coupleId = event.params.coupleId;

    // ── 1a. Alarm handling (original) ──────────────────────────────────────
    const alarm = after.alarm;
    if (alarm) {
      const status = alarm.status ?? "";
      const prevStatus = before.alarm?.status ?? "";

      if ((status === "emergency" || status === "scheduled") && prevStatus !== status) {
        const partnerUid = alarm.target;
        if (partnerUid) {
          const fcmToken = await getFcmToken(partnerUid);
          if (fcmToken) {
            const data = {
              type: status === "emergency" ? "emergency_wake" : "scheduled_alarm",
              coupleId,
              triggeredBy: alarm.createdBy ?? "",
              timestamp: String(Date.now()),
            };
            if (status === "scheduled") {
              const alarmTime = alarm.time;
              data.alarmId = String(alarm.id ?? 0);
              data.alarmTimeMs = alarmTime
                ? String(alarmTime.toMillis())
                : String(Date.now() + 20000);
            }
            await sendFCM(fcmToken, data);
          }
        }
      }
    }

    // ── 1b. Voice Wake handling (V2) ───────────────────────────────────────
    const voiceWake = after.voiceWake;
    const prevVoiceWake = before.voiceWake;
    if (voiceWake && voiceWake.status === "pending") {
      // Only fire if the voice wake field just appeared or changed to pending
      if (!prevVoiceWake || prevVoiceWake.status !== "pending" ||
          voiceWake.timestamp !== prevVoiceWake.timestamp) {
        const receiverUid = voiceWake.receiverId;
        if (receiverUid) {
          const fcmToken = await getFcmToken(receiverUid);
          if (fcmToken) {
            // Look up sender name
            const senderSnap = await admin.firestore()
              .collection("users").doc(voiceWake.senderId).get();
            const senderName = senderSnap.data()?.name ?? "Partner";

            await sendFCM(fcmToken, {
              type: "voice_wake",
              coupleId,
              senderName,
              voiceUrl: voiceWake.voiceUrl ?? "",
              scheduledTimeMs: voiceWake.scheduledTime
                ? String(voiceWake.scheduledTime.toMillis())
                : String(Date.now() + 30000),
              timestamp: String(Date.now()),
            });
          }
        }
      }
    }

    // ── 1c. Incoming Call handling (V2) ────────────────────────────────────
    const activeCall = after.activeCall;
    const prevActiveCall = before.activeCall;
    if (activeCall && (activeCall.status === "calling" || activeCall.status === "ringing")) {
      if (!prevActiveCall || (prevActiveCall.status !== "calling" && prevActiveCall.status !== "ringing") ||
          activeCall.callId !== prevActiveCall.callId) {
        const receiverUid = activeCall.receiverId;
        if (receiverUid) {
          const fcmToken = await getFcmToken(receiverUid);
          if (fcmToken) {
            await sendFCM(fcmToken, {
              type: "incoming_call",
              coupleId,
              callId: activeCall.callId ?? "",
              callerName: activeCall.callerName ?? "Partner",
              callType: activeCall.type ?? "voice",
              timestamp: String(Date.now()),
            });
          }
        }
      }
    }

    return null;
  }
);

// ═══════════════════════════════════════════════════════════════════════════════
// 2. Chat message notification (V2)
//    Triggered when a new message is created in any couple's chat.
// ═══════════════════════════════════════════════════════════════════════════════
exports.sendChatNotification = onDocumentCreated(
  "Chats/{coupleId}/Messages/{messageId}",
  async (event) => {
    const data = event.data.data();
    if (!data) return null;

    const senderUid = data.senderId ?? "";
    const coupleId = event.params.coupleId;

    // Determine the receiver from the couple doc
    const coupleSnap = await admin.firestore()
      .collection("couples").doc(coupleId).get();
    const members = coupleSnap.data()?.memberUids ?? [];
    const receiverUid = members.find((uid) => uid !== senderUid);
    if (!receiverUid) return null;

    const fcmToken = await getFcmToken(receiverUid);
    if (!fcmToken) return null;

    // Sender name
    const senderSnap = await admin.firestore()
      .collection("users").doc(senderUid).get();
    const senderName = senderSnap.data()?.name ?? "Partner";

    // Message preview
    let text = "💌 New message";
    const msgType = data.type ?? "text";
    if (msgType === "text") {
      text = (data.text ?? "").substring(0, 100);
    } else if (msgType === "image") {
      text = "📸 Photo";
    } else if (msgType === "voice") {
      text = "🎙️ Voice message";
    } else if (msgType === "oneTime") {
      text = "🔒 One-time photo";
    }

    await sendFCM(fcmToken, {
      type: "chat_message",
      coupleId,
      senderName,
      text,
      messageId: event.params.messageId,
      timestamp: String(Date.now()),
    });

    return null;
  }
);
