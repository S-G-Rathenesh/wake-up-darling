import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

/// Full WebRTC peer connection service using Firestore for signaling.
///
/// Flow:
///   1. Caller calls [initialize] then [createOffer] → writes SDP offer to
///      `Calls/{callId}.offer` and listens for `answer`.
///   2. Callee calls [initialize] then [createAnswer] → reads `offer`,
///      writes `answer`, and exchanges ICE candidates.
///   3. ICE candidates are exchanged via `Calls/{callId}/callerCandidates`
///      and `Calls/{callId}/calleeCandidates` sub-collections.
class WebRTCService {
  WebRTCService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

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

  // Google STUN servers
  static const _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
    ]
  };

  /// Initialise local media (audio + optionally video).
  ///
  /// Sets audio mode to communication for echo cancellation.
  Future<void> initialize({required bool isVideo}) async {
    // Set audio mode to MODE_IN_COMMUNICATION to avoid echo cancellation
    // conflicts and ensure proper audio routing.
    try {
      const platform = MethodChannel('ultra_alarm');
      await platform.invokeMethod('setAudioMode').catchError((_) {});
    } catch (_) {
      // Native side may not implement this — safe to ignore.
    }

    final constraints = <String, dynamic>{
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': isVideo
          ? {'facingMode': 'user', 'width': 640, 'height': 480}
          : false,
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(constraints);
      debugPrint('[WebRTC] Local stream acquired: ${_localStream?.id}');
      debugPrint('[WebRTC] Audio tracks: ${_localStream?.getAudioTracks().length}');
      debugPrint('[WebRTC] Video tracks: ${_localStream?.getVideoTracks().length}');
    } catch (e) {
      debugPrint('[WebRTC] Failed to get user media: $e');
      rethrow;
    }
  }

  /// Create offer (caller side).
  Future<void> createOffer(String callId) async {
    _remoteDescSet = false;
    _disposed = false;

    final callDoc = _db.collection('Calls').doc(callId);
    final callerCandidates = callDoc.collection('callerCandidates');

    _pc = await createPeerConnection(_iceServers);

    // Monitor ICE connection state for debugging.
    _pc!.onIceConnectionState = (state) {
      debugPrint('[WebRTC] ICE connection state: $state');
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] Peer connection state: $state');
    };

    _pc!.onSignalingState = (state) {
      debugPrint('[WebRTC] Signaling state: $state');
    };

    // Add local tracks.
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
        debugPrint('[WebRTC] Added local track: ${track.kind} enabled=${track.enabled}');
      }
    }

    // Collect ICE candidates → write to Firestore.
    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_disposed) return;
      final map = candidate.toMap();
      if (map['candidate'] == null || (map['candidate'] as String).isEmpty) {
        debugPrint('[WebRTC] ICE gathering done (caller)');
        return;
      }
      callerCandidates.add(map);
      debugPrint('[WebRTC] Sent caller ICE candidate');
    };

    // Receive remote stream.
    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && !_disposed) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream!);
        debugPrint('[WebRTC] Remote stream received (tracks: ${_remoteStream!.getTracks().length})');
      }
    };

    // Also handle onAddStream for older WebRTC implementations.
    // ignore: deprecated_member_use
    _pc!.onAddStream = (MediaStream stream) {
      if (_disposed) return;
      _remoteStream ??= stream;
      _remoteStreamController.add(stream);
      debugPrint('[WebRTC] onAddStream: ${stream.id}');
    };

    // Create and set offer.
    final offer = await _pc!.createOffer();
    await _pc!.setLocalDescription(offer);
    debugPrint('[WebRTC] Local offer set, SDP type=${offer.type}');

    await callDoc.update({
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
    debugPrint('[WebRTC] Offer written to Firestore');

    // Listen for answer.
    _answerSub = callDoc.snapshots().listen((snap) async {
      if (_disposed || _remoteDescSet) return;
      final data = snap.data();
      if (data == null) return;
      final answerData = data['answer'];
      if (answerData == null) return;

      _remoteDescSet = true;

      final answer = RTCSessionDescription(
        answerData['sdp'],
        answerData['type'],
      );

      try {
        await _pc!.setRemoteDescription(answer);
        debugPrint('[WebRTC] Remote answer set successfully');
      } catch (e) {
        _remoteDescSet = false; // allow retry
        debugPrint('[WebRTC] Error setting remote answer: $e');
      }
    });

    // Listen for callee ICE candidates.
    _candidateSub = callDoc
        .collection('calleeCandidates')
        .snapshots()
        .listen((snap) {
      if (_disposed || _pc == null) return;
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['candidate'] != null) {
            _pc!.addCandidate(RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ));
            debugPrint('[WebRTC] Added callee ICE candidate');
          }
        }
      }
    });
  }

  /// Create answer (callee side).
  Future<void> createAnswer(String callId) async {
    _remoteDescSet = false;
    _disposed = false;

    final callDoc = _db.collection('Calls').doc(callId);
    final calleeCandidates = callDoc.collection('calleeCandidates');

    _pc = await createPeerConnection(_iceServers);

    // Monitor ICE connection state for debugging.
    _pc!.onIceConnectionState = (state) {
      debugPrint('[WebRTC] ICE connection state (callee): $state');
    };

    _pc!.onConnectionState = (state) {
      debugPrint('[WebRTC] Peer connection state (callee): $state');
    };

    _pc!.onSignalingState = (state) {
      debugPrint('[WebRTC] Signaling state (callee): $state');
    };

    // Add local tracks.
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await _pc!.addTrack(track, _localStream!);
        debugPrint('[WebRTC] Added local track (callee): ${track.kind} enabled=${track.enabled}');
      }
    }

    // Collect ICE candidates → write to Firestore.
    _pc!.onIceCandidate = (RTCIceCandidate candidate) {
      if (_disposed) return;
      final map = candidate.toMap();
      if (map['candidate'] == null || (map['candidate'] as String).isEmpty) {
        debugPrint('[WebRTC] ICE gathering done (callee)');
        return;
      }
      calleeCandidates.add(map);
      debugPrint('[WebRTC] Sent callee ICE candidate');
    };

    // Receive remote stream.
    _pc!.onTrack = (RTCTrackEvent event) {
      if (event.streams.isNotEmpty && !_disposed) {
        _remoteStream = event.streams[0];
        _remoteStreamController.add(_remoteStream!);
        debugPrint('[WebRTC] Remote stream received (callee, tracks: ${_remoteStream!.getTracks().length})');
      }
    };

    // Also handle onAddStream for older WebRTC implementations.
    // ignore: deprecated_member_use
    _pc!.onAddStream = (MediaStream stream) {
      if (_disposed) return;
      _remoteStream ??= stream;
      _remoteStreamController.add(stream);
      debugPrint('[WebRTC] onAddStream (callee): ${stream.id}');
    };

    // Read offer from Firestore — wait for it if not written yet.
    final callData = (await callDoc.get()).data();
    var offerMap = callData?['offer'] as Map<String, dynamic>?;
    if (offerMap == null) {
      debugPrint('[WebRTC] No offer yet – waiting via snapshot');
      final completer = Completer<Map<String, dynamic>>();
      StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? offerSub;
      offerSub = callDoc.snapshots().listen((snap) {
        final data = snap.data();
        if (data != null && data['offer'] != null && !completer.isCompleted) {
          completer.complete(Map<String, dynamic>.from(data['offer'] as Map));
          offerSub?.cancel();
        }
      });
      try {
        offerMap = await completer.future.timeout(
          const Duration(seconds: 30),
          onTimeout: () {
            offerSub?.cancel();
            throw TimeoutException('Timed out waiting for offer');
          },
        );
      } catch (e) {
        offerSub.cancel();
        debugPrint('[WebRTC] Error waiting for offer: $e');
        rethrow;
      }
    }

    await _pc!.setRemoteDescription(
      RTCSessionDescription(offerMap['sdp'], offerMap['type']),
    );
    _remoteDescSet = true;
    debugPrint('[WebRTC] Remote offer set (callee)');

    // Create and set answer.
    final answer = await _pc!.createAnswer();
    await _pc!.setLocalDescription(answer);
    debugPrint('[WebRTC] Local answer set, SDP type=${answer.type}');

    await callDoc.update({
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
    debugPrint('[WebRTC] Answer written to Firestore');

    // Listen for caller ICE candidates.
    _candidateSub = callDoc
        .collection('callerCandidates')
        .snapshots()
        .listen((snap) {
      if (_disposed || _pc == null) return;
      for (final change in snap.docChanges) {
        if (change.type == DocumentChangeType.added) {
          final data = change.doc.data();
          if (data != null && data['candidate'] != null) {
            _pc!.addCandidate(RTCIceCandidate(
              data['candidate'],
              data['sdpMid'],
              data['sdpMLineIndex'],
            ));
            debugPrint('[WebRTC] Added caller ICE candidate');
          }
        }
      }
    });
  }

  /// Toggle microphone mute.
  void toggleMute(bool muted) {
    _localStream?.getAudioTracks().forEach((t) => t.enabled = !muted);
  }

  /// Toggle camera on/off (video calls).
  void toggleCamera(bool off) {
    _localStream?.getVideoTracks().forEach((t) => t.enabled = !off);
  }

  /// Toggle speaker output.
  Future<void> toggleSpeaker(bool speaker) async {
    _localStream?.getAudioTracks().forEach((t) {
      t.enableSpeakerphone(speaker);
    });
  }

  /// Switch between front/back camera.
  Future<void> switchCamera() async {
    final videoTracks = _localStream?.getVideoTracks();
    if (videoTracks != null && videoTracks.isNotEmpty) {
      await Helper.switchCamera(videoTracks[0]);
    }
  }

  /// Clean up Firestore signaling data.
  Future<void> cleanupSignaling(String callId) async {
    try {
      final callDoc = _db.collection('Calls').doc(callId);
      // Delete ICE candidate sub-collections.
      final callerCands = await callDoc.collection('callerCandidates').get();
      for (final doc in callerCands.docs) {
        await doc.reference.delete();
      }
      final calleeCands = await callDoc.collection('calleeCandidates').get();
      for (final doc in calleeCands.docs) {
        await doc.reference.delete();
      }
    } catch (e) {
      debugPrint('[WebRTC] cleanup error: $e');
    }
  }

  /// Dispose all resources. Safe to call multiple times.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;

    _answerSub?.cancel();
    _candidateSub?.cancel();

    _localStream?.getTracks().forEach((t) => t.stop());
    _localStream?.dispose();
    _localStream = null;
    _remoteStream?.dispose();
    _remoteStream = null;

    await _pc?.close();
    _pc = null;

    _remoteStreamController.close();
    debugPrint('[WebRTC] Disposed');
  }
}
