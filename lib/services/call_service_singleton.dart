import 'package:flutter/material.dart';
import 'package:zego_express_engine/zego_express_engine.dart';

/// Singleton CallService for Zego engine lifecycle management.
/// Initialize once in main() via CallService().init().
/// Use CallService() to access the engine anywhere.
class CallService {
  static final CallService _instance = CallService._internal();

  factory CallService() => _instance;

  CallService._internal();

  late ZegoExpressEngine engine;
  bool _initialized = false;

  // ─── Zego Credentials ───────────────────────────────────────────────────
  static const int _appID = 1753181857;
  static const String _appSign =
      '535d2d5721eafdb2446b18e87092dd9e7a8042077cbcc879ca47c72dc121780b';

  // ─── Init Engine Once ───────────────────────────────────────────────────

  /// Initializes the Zego engine. Safe to call multiple times;
  /// will skip if already initialized.
  Future<void> init() async {
    if (_initialized) {
      debugPrint('[CallService] Engine already initialized');
      return;
    }

    try {
      final profile = ZegoEngineProfile(
        _appID,
        ZegoScenario.General,
        appSign: _appSign,
      );

      await ZegoExpressEngine.createEngineWithProfile(profile);
      engine = ZegoExpressEngine.instance;

      // Enable hardware globally
      await engine.enableCamera(true);
      await engine.muteMicrophone(false); // false = unmute (enable microphone)
      await engine.setAudioRouteToSpeaker(true);

      _initialized = true;
      debugPrint('[CallService] Zego engine initialized successfully');
    } catch (e) {
      debugPrint('[CallService] Init error: $e');
      rethrow;
    }
  }

  bool get isInitialized => _initialized;
}
