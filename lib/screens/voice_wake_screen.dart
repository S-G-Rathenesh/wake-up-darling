import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../services/voice_wake_service.dart';
import '../widgets/romantic_hearts_overlay.dart';

/// Screen for recording a voice message and scheduling a voice wake request.
class VoiceWakeScreen extends StatefulWidget {
  final String coupleId;
  final String partnerId;
  final String partnerName;

  const VoiceWakeScreen({
    super.key,
    required this.coupleId,
    required this.partnerId,
    this.partnerName = 'Partner',
  });

  @override
  State<VoiceWakeScreen> createState() => _VoiceWakeScreenState();
}

class _VoiceWakeScreenState extends State<VoiceWakeScreen> {
  final _voiceService = VoiceWakeService();
  final _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _hasRecording = false;
  bool _isSending = false;
  String? _recordedPath;
  TimeOfDay? _selectedTime;
  DateTime _recordStartedAt = DateTime.now();
  int _recordedDurationMs = 0;

  @override
  void dispose() {
    _recorder.dispose();
    super.dispose();
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      final path = await _recorder.stop();
      final durationMs =
          DateTime.now().difference(_recordStartedAt).inMilliseconds;
      setState(() {
        _isRecording = false;
        _hasRecording = path != null;
        _recordedPath = path;
        _recordedDurationMs = durationMs;
      });
    } else {
      if (await _recorder.hasPermission()) {
        final dir = await getTemporaryDirectory();
        final path =
            '${dir.path}/voice_wake_${DateTime.now().millisecondsSinceEpoch}.m4a';
        await _recorder.start(
          const RecordConfig(encoder: AudioEncoder.aacLc),
          path: path,
        );
        setState(() {
          _isRecording = true;
          _recordStartedAt = DateTime.now();
        });
      }
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (picked != null) setState(() => _selectedTime = picked);
  }

  Future<void> _sendVoiceWake() async {
    if (_recordedPath == null || _selectedTime == null) return;

    // Validate recorded file exists before attempting upload.
    final audioFile = File(_recordedPath!);
    if (!audioFile.existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording file not found. Please record again.')),
        );
      }
      return;
    }
    if (audioFile.lengthSync() == 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording is empty. Please record again.')),
        );
      }
      return;
    }

    setState(() => _isSending = true);

    final now = DateTime.now();
    final scheduled = DateTime(
      now.year,
      now.month,
      now.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    try {
      debugPrint('[VoiceWakeScreen] Sending voice wake: ${audioFile.path} (${audioFile.lengthSync()} bytes)');

      await _voiceService.createVoiceWakeRequest(
        coupleId: widget.coupleId,
        receiverId: widget.partnerId,
        audioFile: audioFile,
        scheduledTime: scheduled,
        durationMs: _recordedDurationMs,
      );

      debugPrint('[VoiceWakeScreen] Voice wake sent successfully');

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Voice wake sent for ${DateFormat('h:mm a').format(scheduled)} ❤️',
          ),
        ),
      );
      Navigator.pop(context);
    } catch (e, st) {
      debugPrint('[VoiceWakeScreen] ERROR sending voice wake: $e\n$st');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Voice Wake 🎙️'),
        backgroundColor: const Color(0xFF8E2DE2).withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Stack(
        children: [
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF8E2DE2), Color(0xFF4A00E0), Color(0xFF6A11CB)],
              ),
            ),
          ),
          const RomanticHeartsOverlay(),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  const SizedBox(height: 40),
                  Text(
                    'Record a voice message\nfor ${widget.partnerName}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 40),

                  // Record button
                  GestureDetector(
                    onTap: _toggleRecording,
                    child: Container(
                      width: 120,
                      height: 120,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _isRecording
                            ? const RadialGradient(colors: [Colors.redAccent, Colors.red])
                            : const RadialGradient(colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)]),
                        boxShadow: [
                          BoxShadow(
                            color: (_isRecording ? Colors.red : Colors.purple)
                                .withValues(alpha: 0.4),
                            blurRadius: 30,
                            spreadRadius: 5,
                          ),
                        ],
                      ),
                      child: Icon(
                        _isRecording ? Icons.stop : Icons.mic,
                        color: Colors.white,
                        size: 50,
                      ),
                    ),
                  )
                      .animate(onPlay: (c) => c.repeat(reverse: true))
                      .scale(
                        begin: const Offset(1, 1),
                        end: const Offset(1.08, 1.08),
                        duration: 1200.ms,
                      ),

                  const SizedBox(height: 16),
                  Text(
                    _isRecording
                        ? '🔴 Recording... Tap to stop'
                        : _hasRecording
                            ? '✅ Voice recorded!'
                            : 'Tap to start recording',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 15,
                    ),
                  ),

                  const SizedBox(height: 40),

                  // Time picker
                  GestureDetector(
                    onTap: _pickTime,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(25),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.access_time, color: Colors.white),
                          const SizedBox(width: 12),
                          Text(
                            _selectedTime != null
                                ? 'Wake at ${_selectedTime!.format(context)}'
                                : 'Select Wake Time ⏰',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const Spacer(),

                  // Send button
                  if (_hasRecording && _selectedTime != null)
                    GestureDetector(
                      onTap: _isSending ? null : _sendVoiceWake,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(30),
                          gradient: const LinearGradient(
                            colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.purple.withValues(alpha: 0.4),
                              blurRadius: 15,
                            ),
                          ],
                        ),
                        child: Center(
                          child: _isSending
                              ? const SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text(
                                  'Send Voice Wake ❤️',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ).animate().fadeIn(duration: 400.ms).slideY(begin: 0.2, end: 0),

                  const SizedBox(height: 30),

                  if (VoiceWakeService.isCollegeTime())
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Text(
                        '⚠️ College hours active (8 AM – 5:30 PM)\nWake will be saved as request, not direct alarm.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.orangeAccent, fontSize: 13),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
