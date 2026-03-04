import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

/// A compact voice-message playback widget for use inside chat bubbles.
/// Plays from a remote URL (Cloudinary) or local file path.
class VoiceBubble extends StatefulWidget {
  /// Remote URL or local file path of the voice note.
  final String audioUrl;

  /// Total duration in milliseconds (from Firestore `mediaDurationMs`).
  final int? durationMs;

  /// Whether the bubble should tint for "mine" or "theirs" styling.
  final bool isMine;

  const VoiceBubble({
    super.key,
    required this.audioUrl,
    this.durationMs,
    this.isMine = true,
  });

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  late final AudioPlayer _player;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _totalDuration = Duration.zero;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();

    // Seed total duration from Firestore metadata if available.
    if (widget.durationMs != null && widget.durationMs! > 0) {
      _totalDuration = Duration(milliseconds: widget.durationMs!);
    }

    _player.onPositionChanged.listen((pos) {
      if (mounted) setState(() => _position = pos);
    });

    _player.onDurationChanged.listen((dur) {
      if (mounted && dur.inMilliseconds > 0) {
        setState(() => _totalDuration = dur);
      }
    });

    _player.onPlayerComplete.listen((_) {
      if (mounted) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      }
    });

    _player.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() => _isPlaying = state == PlayerState.playing);
      }
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
    } else {
      final url = widget.audioUrl;
      if (url.startsWith('http://') || url.startsWith('https://')) {
        await _player.play(UrlSource(url));
      } else {
        await _player.play(DeviceFileSource(url));
      }
    }
  }

  String _fmtDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final total = _totalDuration.inMilliseconds > 0
        ? _totalDuration
        : const Duration(seconds: 1);
    final progress = _position.inMilliseconds / total.inMilliseconds;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Play / Pause button
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: widget.isMine
                  ? Colors.white.withValues(alpha: 0.25)
                  : Colors.deepPurple.withValues(alpha: 0.25),
            ),
            child: Icon(
              _isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
              size: 22,
            ),
          ),
        ),
        const SizedBox(width: 8),
        // Progress bar + time
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  minHeight: 4,
                  backgroundColor: Colors.white24,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    widget.isMine ? Colors.white70 : Colors.deepPurple,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _isPlaying || _position.inMilliseconds > 0
                    ? '${_fmtDuration(_position)} / ${_fmtDuration(total)}'
                    : _fmtDuration(total),
                style: const TextStyle(color: Colors.white60, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
