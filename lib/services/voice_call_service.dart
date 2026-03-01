import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Minimal, clean WebRTC voice-call service using Firestore for signaling.
///
/// Signaling flow:
///   1. Caller creates offer → writes to `Calls/{callId}.offer`
///   2. Callee reads offer, creates answer → writes to `Calls/{callId}.answer`
///   3. ICE candidates exchanged via:
///        `Calls/{callId}/callerCandidates`
///        `Calls/{callId}/calleeCandidates`
///
/// Usage:
///   final svc = VoiceCallService(callId);
///   await svc.init(isCaller: true);
///   // … later …
///   await svc.dispose();
class VoiceCallService {
  VoiceCallService(this.callId, {FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  final String callId;
  final FirebaseFirestore _db;

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  final _remoteStreamController = StreamController<MediaStream>.broadcast();
  Stream<MediaStream> get onRemoteStream => _remoteStreamController.stream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  StreamSubscription? _answerSub;
  StreamSubscription? _candidateSub;

  bool _remoteDescSet = false;
  bool _disposed = false;

  // ─── ICE servers ──────────────────────────────────────────────────────
  static const _config = <String, dynamic>{
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
  };

  // ─── Public API ───────────────────────────────────────────────────────

  /// Initialise WebRTC peer connection + local audio stream, then either
  /// create an offer (caller) or listen for one and respond (callee).
  Future<void> init({required bool isCaller}) async {
    // 1. Get local audio stream.
    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });
    debugPrint('[VoiceCall] Local audio stream acquired');

    // 2. Create peer connection.
    _pc = await createPeerConnection(_config);

    // 3. Add local audio tracks.
    for (final track in _localStream!.getTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    // 4. Remote stream handlers.
    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && !_disposed) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream!);
        debugPrint('[VoiceCall] Remote stream received');
      }
    };

    // ignore: deprecated_member_use
    _pc!.onAddStream = (MediaStream stream) {
      if (!_disposed) {
        _remoteStream ??= stream;
        _remoteStreamController.add(stream);
      }
    };

    // 5. Debug logging.
    _pc!.onIceConnectionState = (state) {
      debugPrint('[VoiceCall] ICE state: $state');
    };
    _pc!.onConnectionState = (state) {
      debugPrint('[VoiceCall] Connection state: $state');
    };

    // 6. Signaling.
    if (isCaller) {
      await _createOffer();
    } else {
      await _handleOffer();
    }
  }

  /// Mute / unmute the microphone.
  void toggleMute(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  /// Switch between earpiece and speaker.
  void toggleSpeaker(bool speaker) {
    _localStream?.getAudioTracks().forEach((t) {
      t.enableSpeakerphone(speaker);
    });
  }

  /// Clean up Firestore signaling data (ICE candidate sub-collections).
  Future<void> cleanupSignaling() async {
    try {
      final callDoc = _db.collection('Calls').doc(callId);
      final callerCands = await callDoc.collection('callerCandidates').get();
      for (final doc in callerCands.docs) {
        doc.reference.delete();
      }
      final calleeCands = await callDoc.collection('calleeCandidates').get();
      for (final doc in calleeCands.docs) {
        doc.reference.delete();
      }
    } catch (e) {
      debugPrint('[VoiceCall] cleanupSignaling error: $e');
    }
  }

  /// Release all resources. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _answerSub?.cancel();
    _candidateSub?.cancel();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _remoteStream?.dispose();

    await _pc?.close();
    _pc = null;

    _remoteStreamController.close();
    debugPrint('[VoiceCall] Disposed');
  }

  // ─── Caller side ──────────────────────────────────────────────────────

  Future<void> _createOffer() async {
    final callDoc = _db.collection('Calls').doc(callId);
    final callerCandidates = callDoc.collection('callerCandidates');

    // Collect ICE candidates → Firestore.
    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      callerCandidates.add(candidate.toMap());
    };

    // Create SDP offer.
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);

    // Write offer to call doc.
    await callDoc.update({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
    debugPrint('[VoiceCall] Offer written');

    // Listen for answer from callee.
    _answerSub = callDoc.snapshots().listen((snap) async {
      if (_disposed || _remoteDescSet) return;
      final data = snap.data();
      if (data == null || data['answer'] == null) return;

      _remoteDescSet = true;
      final answer = data['answer'];
      try {
        await _pc!.setRemoteDescription(
          RTCSessionDescription(answer['sdp'], answer['type']),
        );
        debugPrint('[VoiceCall] Remote answer set');
      } catch (e) {
        debugPrint('[VoiceCall] Error setting remote answer: $e');
      }
    });

    // Listen for callee ICE candidates.
    _candidateSub = callDoc
        .collection('calleeCandidates')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d != null) {
            _pc!.addCandidate(RTCIceCandidate(
              d['candidate'],
              d['sdpMid'],
              d['sdpMLineIndex'],
            ));
          }
        }
      }
    });
  }

  // ─── Callee side ──────────────────────────────────────────────────────

  Future<void> _handleOffer() async {
    final callDoc = _db.collection('Calls').doc(callId);
    final calleeCandidates = callDoc.collection('calleeCandidates');

    // Collect ICE candidates → Firestore.
    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      calleeCandidates.add(candidate.toMap());
    };

    // Read offer from Firestore.
    final callData = (await callDoc.get()).data();
    final offerData = callData?['offer'];
    if (offerData == null) {
      debugPrint('[VoiceCall] No offer found – retrying via snapshot');
      // Offer may not be written yet; listen for it.
      _answerSub = callDoc.snapshots().listen((snap) async {
        if (_disposed || _remoteDescSet) return;
        final data = snap.data();
        if (data == null || data['offer'] == null) return;

        _remoteDescSet = true;
        _answerSub?.cancel();
        await _setOfferAndAnswer(callDoc, data['offer']);
      });
      // Listen for caller ICE candidates regardless.
      _listenCallerCandidates(callDoc);
      return;
    }

    await _setOfferAndAnswer(callDoc, offerData);

    // Listen for caller ICE candidates.
    _listenCallerCandidates(callDoc);
  }

  Future<void> _setOfferAndAnswer(
    DocumentReference<Map<String, dynamic>> callDoc,
    Map<String, dynamic> offerData,
  ) async {
    await _pc!.setRemoteDescription(
      RTCSessionDescription(offerData['sdp'], offerData['type']),
    );
    debugPrint('[VoiceCall] Remote offer set');

    // Create SDP answer.
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);

    // Write answer to call doc.
    await callDoc.update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
    debugPrint('[VoiceCall] Answer written');
  }

  void _listenCallerCandidates(
    DocumentReference<Map<String, dynamic>> callDoc,
  ) {
    _candidateSub = callDoc
        .collection('callerCandidates')
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final d = change.doc.data();
          if (d != null) {
            _pc!.addCandidate(RTCIceCandidate(
              d['candidate'],
              d['sdpMid'],
              d['sdpMLineIndex'],
            ));
          }
        }
      }
    });
  }
}
