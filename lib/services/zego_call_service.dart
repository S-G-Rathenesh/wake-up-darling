import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

/// ZEGOCLOUD Express Engine call service.
///
/// Handles engine lifecycle, room login, stream publishing/playing,
/// and local/remote video rendering.
///
/// Uses AppID: 1753181857 (test environment).
class ZegoCallService {
  ZegoCallService._();

  // ─── ZEGOCLOUD credentials ───────────────────────────────────────────
  static const int _appID = 1753181857;
  static const String _appSign =
      '535d2d5721eafdb2446b18e87092dd9e7a8042077cbcc879ca47c72dc121780b';

  // ─── Singleton guard ────────────────────────────────────────────────
  static bool _engineCreated = false;
  static bool _loggedIn = false;
  static String _currentRoomID = '';

  // ─── Dispose synchronisation ────────────────────────────────────────
  /// Tracks a running [dispose] so [joinRoom] can await it before
  /// re-initialising the engine. Prevents race conditions when the user
  /// starts a new call immediately after ending the previous one.
  static Future<void>? _pendingDispose;

  // ─── Stream IDs ─────────────────────────────────────────────────────
  static String _publishStreamID = '';  static String _currentUserID = '';
  // ─── Texture renderer IDs ───────────────────────────────────────────
  static int? localViewID;
  static int? remoteViewID;
  static Widget? localViewWidget;
  static Widget? remoteViewWidget;

  // ─── Remote stream ready notifier ───────────────────────────────────
  static final ValueNotifier<bool> remoteStreamReady =
      ValueNotifier<bool>(false);

  // ─── Initialize Engine ──────────────────────────────────────────────

  /// Creates the Zego Express Engine. Safe to call multiple times;
  /// will skip if the engine is already alive.
  static Future<void> initEngine() async {
    if (_engineCreated) {
      debugPrint('[Zego] Engine already created, skipping');
      return;
    }

    final profile = ZegoEngineProfile(
      _appID,
      ZegoScenario.General,
      appSign: _appSign,
    );

    await ZegoExpressEngine.createEngineWithProfile(profile);
    _engineCreated = true;
    debugPrint('[Zego] Engine created (appID=$_appID)');
  }

  // ─── Permissions ────────────────────────────────────────────────────

  /// Requests microphone + camera runtime permissions.
  /// Returns `true` if all were granted.
  static Future<bool> requestPermissions({required bool isVideo}) async {
    final mic = await Permission.microphone.request();
    if (!mic.isGranted) return false;

    if (isVideo) {
      final cam = await Permission.camera.request();
      if (!cam.isGranted) return false;
    }
    return true;
  }

  // ─── Join Room ──────────────────────────────────────────────────────

  /// Logs into a Zego room. Both caller and callee must join the same
  /// [roomID] for media to flow.
  ///
  /// [userID] — unique user id (Firebase UID).
  /// [userName] — display name.
  /// [roomID] — shared room id (use coupleId).
  /// [isVideo] — whether to enable camera.
  static Future<bool> joinRoom({
    required String roomID,
    required String userID,
    required String userName,
    required bool isVideo,
  }) async {
    // Wait for any in-flight dispose() from a previous call.
    if (_pendingDispose != null) {
      debugPrint('[Zego] Waiting for pending dispose to finish…');
      await _pendingDispose;
      _pendingDispose = null;
    }

    if (_loggedIn && _currentRoomID == roomID) {
      debugPrint('[Zego] Already in room $roomID');
      return true;
    }

    // Ensure engine exists.
    await initEngine();

    // Store current user ID for filtering own stream
    _currentUserID = userID;

    // ── Enable hardware BEFORE loginRoom ────────────────────────────
    // This ensures the engine has audio/video enabled when joining
    await ZegoExpressEngine.instance.enableCamera(isVideo);
    await ZegoExpressEngine.instance.muteMicrophone(false); // unmute mic
    await ZegoExpressEngine.instance.setAudioRouteToSpeaker(true);
    debugPrint('[Zego] Hardware enabled before login: camera=$isVideo, mic=unmuted, speaker=true');

    // ── Register ALL callbacks BEFORE loginRoom ─────────────────────
    // This is critical: Zego fires onRoomStreamUpdate for existing
    // streams right after login. If the callback isn't set yet, the
    // events are lost and the remote stream is never played.
    ZegoExpressEngine.onRoomStreamUpdate = (
      String roomID,
      ZegoUpdateType updateType,
      List<ZegoStream> streamList,
      Map<String, dynamic> extendedData,
    ) async {
      if (updateType == ZegoUpdateType.Add) {
        for (final stream in streamList) {
          // Do NOT play own stream - only partner's stream
          if (stream.streamID != 'stream_$_currentUserID') {
            debugPrint('[Zego] Remote stream detected: ${stream.streamID}');
            await _startPlayingStream(stream.streamID, isVideo);
          } else {
            debugPrint('[Zego] Skipping own stream: ${stream.streamID}');
          }
        }
      } else if (updateType == ZegoUpdateType.Delete) {
        for (final stream in streamList) {
          debugPrint('[Zego] Remote stream removed: ${stream.streamID}');
          await _stopPlayingStream(stream.streamID);
        }
      }
    };

    ZegoExpressEngine.onRoomUserUpdate = (
      String roomID,
      ZegoUpdateType updateType,
      List<ZegoUser> userList,
    ) {
      for (final u in userList) {
        debugPrint(
          '[Zego] User ${updateType == ZegoUpdateType.Add ? "joined" : "left"}: '
          '${u.userID} (${u.userName}) in room $roomID',
        );
      }
    };

    ZegoExpressEngine.onRoomStateChanged = (
      String roomID,
      ZegoRoomStateChangedReason reason,
      int errorCode,
      Map<String, dynamic> extendedData,
    ) {
      debugPrint(
        '[Zego] Room state changed: room=$roomID, reason=$reason, '
        'errorCode=$errorCode',
      );
    };

    ZegoExpressEngine.onPublisherStateUpdate = (
      String streamID,
      ZegoPublisherState state,
      int errorCode,
      Map<String, dynamic> extendedData,
    ) {
      debugPrint(
        '[Zego] Publisher state: stream=$streamID, state=$state, '
        'errorCode=$errorCode',
      );
    };

    ZegoExpressEngine.onPlayerStateUpdate = (
      String streamID,
      ZegoPlayerState state,
      int errorCode,
      Map<String, dynamic> extendedData,
    ) {
      debugPrint(
        '[Zego] Player state: stream=$streamID, state=$state, '
        'errorCode=$errorCode',
      );
    };

    // ── Now login to room ───────────────────────────────────────────
    final user = ZegoUser(userID, userName);
    final config = ZegoRoomConfig.defaultConfig()
      ..isUserStatusNotify = true;

    try {
      final result = await ZegoExpressEngine.instance
          .loginRoom(roomID, user, config: config);

      if (result.errorCode != 0) {
        debugPrint('[Zego] loginRoom failed: ${result.errorCode}');
        return false;
      }

      _loggedIn = true;
      _currentRoomID = roomID;
      debugPrint('[Zego] Logged into room $roomID');
    } catch (e) {
      debugPrint('[Zego] loginRoom exception: $e');
      return false;
    }

    // ── Enable hardware ALREADY DONE ABOVE BEFORE loginRoom ─────────────────────
    // Hardware is now enabled before loginRoom call above
    // await ZegoExpressEngine.instance.enableCamera(isVideo);
    // await ZegoExpressEngine.instance.muteMicrophone(false);
    // await ZegoExpressEngine.instance.setAudioRouteToSpeaker(true);

    return true;
  }

  // ─── Start Publishing Stream ─────────────────────────────────────

  /// Starts publishing the local stream. Should be called AFTER startPreview()
  /// for video calls.
  static Future<void> startPublishing(String userID) async {
    if (_publishStreamID.isNotEmpty) {
      debugPrint('[Zego] Already publishing stream $_publishStreamID');
      return;
    }
    
    _publishStreamID = 'stream_$userID';
    await ZegoExpressEngine.instance
        .startPublishingStream(_publishStreamID);
    debugPrint('[Zego] Started publishing stream: $_publishStreamID');
  }

  // ─── Create local preview widget ───────────────────────────────────

  /// Creates and returns a Widget that renders the local camera preview.
  static Future<Widget?> createLocalPreview() async {
    try {
      final viewWidget = await ZegoExpressEngine.instance.createCanvasView(
        (viewID) async {
          localViewID = viewID;
          final canvas = ZegoCanvas(viewID, viewMode: ZegoViewMode.AspectFill);
          await ZegoExpressEngine.instance.startPreview(canvas: canvas);
          debugPrint('[Zego] Local preview started (viewID=$viewID)');
        },
      );
      localViewWidget = viewWidget;
      return viewWidget;
    } catch (e) {
      debugPrint('[Zego] createLocalPreview error: $e');
      return null;
    }
  }

  // ─── Play remote stream ───────────────────────────────────────────

  static Future<void> _startPlayingStream(
      String streamID, bool isVideo) async {
    try {
      if (isVideo) {
        // Video call: create a canvas view to render remote video.
        final viewWidget = await ZegoExpressEngine.instance.createCanvasView(
          (viewID) async {
            remoteViewID = viewID;
            final canvas =
                ZegoCanvas(viewID, viewMode: ZegoViewMode.AspectFill);
            await ZegoExpressEngine.instance
                .startPlayingStream(streamID, canvas: canvas);
            debugPrint(
                '[Zego] Playing remote video stream $streamID (viewID=$viewID)');
          },
        );
        remoteViewWidget = viewWidget;
        remoteStreamReady.value = true;
      } else {
        // Voice call: play audio-only — no canvas needed.
        await ZegoExpressEngine.instance.startPlayingStream(streamID);
        remoteStreamReady.value = true;
        debugPrint('[Zego] Playing remote audio stream $streamID');
      }
    } catch (e) {
      debugPrint('[Zego] _startPlayingStream error: $e');
    }
  }

  static Future<void> _stopPlayingStream(String streamID) async {
    try {
      await ZegoExpressEngine.instance.stopPlayingStream(streamID);
      if (remoteViewID != null) {
        await ZegoExpressEngine.instance.destroyCanvasView(remoteViewID!);
        remoteViewID = null;
      }
      remoteViewWidget = null;
      remoteStreamReady.value = false;
    } catch (e) {
      debugPrint('[Zego] _stopPlayingStream error: $e');
    }
  }

  // ─── Controls ─────────────────────────────────────────────────────

  static Future<void> toggleMute(bool muted) async {
    await ZegoExpressEngine.instance.muteMicrophone(muted);
    debugPrint('[Zego] Mic muted=$muted');
  }

  static Future<void> toggleCamera(bool off) async {
    await ZegoExpressEngine.instance.enableCamera(!off);
    debugPrint('[Zego] Camera enabled=${!off}');
  }

  static Future<void> toggleSpeaker(bool speaker) async {
    await ZegoExpressEngine.instance.setAudioRouteToSpeaker(speaker);
    debugPrint('[Zego] Speaker=$speaker');
  }

  static bool _isFrontCamera = true;

  static Future<void> switchCamera() async {
    _isFrontCamera = !_isFrontCamera;
    await ZegoExpressEngine.instance.useFrontCamera(_isFrontCamera);
    debugPrint('[Zego] Camera switched to ${_isFrontCamera ? "front" : "back"}');
  }

  // ─── Leave room & destroy ─────────────────────────────────────────

  /// Stops publishing, previewing, leaves the room, and destroys the engine.
  /// Safe to call multiple times. The returned [Future] is also stored in
  /// [_pendingDispose] so that [joinRoom] can await it.
  static Future<void> dispose() async {
    final future = _doDispose();
    _pendingDispose = future;
    await future;
    _pendingDispose = null;
  }

  static Future<void> _doDispose() async {
    try {
      await ZegoExpressEngine.instance.stopPublishingStream();
      debugPrint('[Zego] Stopped publishing');
    } catch (_) {}

    try {
      await ZegoExpressEngine.instance.stopPreview();
      debugPrint('[Zego] Stopped preview');
    } catch (_) {}

    // Destroy canvas views.
    try {
      if (localViewID != null) {
        await ZegoExpressEngine.instance.destroyCanvasView(localViewID!);
        localViewID = null;
      }
      if (remoteViewID != null) {
        await ZegoExpressEngine.instance.destroyCanvasView(remoteViewID!);
        remoteViewID = null;
      }
    } catch (_) {}

    localViewWidget = null;
    remoteViewWidget = null;
    remoteStreamReady.value = false;

    if (_loggedIn) {
      try {
        await ZegoExpressEngine.instance.logoutRoom(_currentRoomID);
        debugPrint('[Zego] Logged out of room $_currentRoomID');
      } catch (_) {}
      _loggedIn = false;
      _currentRoomID = '';
    }

    if (_engineCreated) {
      try {
        await ZegoExpressEngine.destroyEngine();
        debugPrint('[Zego] Engine destroyed');
      } catch (_) {}
      _engineCreated = false;
    }

    _publishStreamID = '';
    _currentUserID = '';

    // Clear callbacks.
    ZegoExpressEngine.onRoomStreamUpdate = null;
    ZegoExpressEngine.onRoomUserUpdate = null;
    ZegoExpressEngine.onRoomStateChanged = null;
    ZegoExpressEngine.onPublisherStateUpdate = null;
    ZegoExpressEngine.onPlayerStateUpdate = null;
  }
}
