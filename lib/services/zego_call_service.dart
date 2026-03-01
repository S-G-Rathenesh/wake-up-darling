import 'dart:async';

import 'package:flutter/foundation.dart';
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

  // ─── Stream IDs ─────────────────────────────────────────────────────
  static String _publishStreamID = '';

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
      ZegoScenario.Default,
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
  /// [roomID] — shared room id (use coupleId or callId).
  /// [isVideo] — whether to enable camera.
  static Future<bool> joinRoom({
    required String roomID,
    required String userID,
    required String userName,
    required bool isVideo,
  }) async {
    if (_loggedIn && _currentRoomID == roomID) {
      debugPrint('[Zego] Already in room $roomID');
      return true;
    }

    // Ensure engine exists.
    await initEngine();

    final user = ZegoUser(userID, userName);
    final config = ZegoRoomConfig.defaultConfig()
      ..isUserStatusNotify = true;

    try {
      final result =
          await ZegoExpressEngine.instance.loginRoom(roomID, user, config: config);

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

    // ── Enable hardware ─────────────────────────────────────────────
    await ZegoExpressEngine.instance.enableCamera(isVideo);
    await ZegoExpressEngine.instance.muteMicrophone(false);
    await ZegoExpressEngine.instance.setAudioRouteToSpeaker(true);

    // ── Register stream update callback ─────────────────────────────
    ZegoExpressEngine.onRoomStreamUpdate = (
      String roomID,
      ZegoUpdateType updateType,
      List<ZegoStream> streamList,
      Map<String, dynamic> extendedData,
    ) {
      for (final stream in streamList) {
        if (updateType == ZegoUpdateType.Add) {
          debugPrint('[Zego] Remote stream added: ${stream.streamID}');
          _startPlayingStream(stream.streamID, isVideo);
        } else {
          debugPrint('[Zego] Remote stream removed: ${stream.streamID}');
          _stopPlayingStream(stream.streamID);
        }
      }
    };

    // ── Publish local stream ────────────────────────────────────────
    _publishStreamID = '${userID}_stream';
    await ZegoExpressEngine.instance
        .startPublishingStream(_publishStreamID);
    debugPrint('[Zego] Publishing stream: $_publishStreamID');

    return true;
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
      final viewWidget = await ZegoExpressEngine.instance.createCanvasView(
        (viewID) async {
          remoteViewID = viewID;
          final canvas = ZegoCanvas(viewID, viewMode: ZegoViewMode.AspectFill);
          await ZegoExpressEngine.instance
              .startPlayingStream(streamID, canvas: canvas);
          debugPrint(
              '[Zego] Playing remote stream $streamID (viewID=$viewID)');
        },
      );
      remoteViewWidget = viewWidget;
      remoteStreamReady.value = true;
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

  static Future<void> switchCamera() async {
    await ZegoExpressEngine.instance.useFrontCamera(true);
  }

  // ─── Leave room & destroy ─────────────────────────────────────────

  /// Stops publishing, previewing, leaves the room, and destroys the engine.
  /// Safe to call multiple times.
  static Future<void> dispose() async {
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

    // Clear callbacks.
    ZegoExpressEngine.onRoomStreamUpdate = null;
  }
}
