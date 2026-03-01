import 'dart:io';

import 'package:flutter/material.dart';

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
import '../services/local_media_service.dart';
import '../widgets/animated_empty_state.dart';
import '../widgets/romantic_hearts_overlay.dart';

/// Shows all shared images and voice notes in a grid gallery.
class SharedMediaScreen extends StatelessWidget {
  final String coupleId;
  const SharedMediaScreen({super.key, required this.coupleId});

  @override
  Widget build(BuildContext context) {
    final chatService = ChatService();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Shared Media 📸'),
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
            child: FutureBuilder<List<ChatMessage>>(
              future: chatService.getSharedMedia(coupleId),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  );
                }

                final media = snap.data ?? [];
                if (media.isEmpty) {
                  return const AnimatedEmptyState(
                    icon: Icons.photo_library_outlined,
                    message: 'No shared media yet 📭',
                  );
                }

                final images = media.where((m) =>
                    m.messageType == MessageType.image &&
                    (m.localPath != null || m.mediaUrl != null)).toList();
                final voiceNotes = media.where((m) =>
                    m.messageType == MessageType.voice).toList();

                return DefaultTabController(
                  length: 2,
                  child: Column(
                    children: [
                      TabBar(
                        indicatorColor: Colors.white,
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.white54,
                        tabs: [
                          Tab(text: 'Images (${images.length})'),
                          Tab(text: 'Voice (${voiceNotes.length})'),
                        ],
                      ),
                      Expanded(
                        child: TabBarView(
                          children: [
                            // Images grid
                            GridView.builder(
                              padding: const EdgeInsets.all(8),
                              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 3,
                                crossAxisSpacing: 4,
                                mainAxisSpacing: 4,
                              ),
                              itemCount: images.length,
                              itemBuilder: (ctx, i) {
                                final img = images[i];
                                final path = img.localPath ?? img.mediaUrl ?? '';
                                final file = File(path);
                                return GestureDetector(
                                  onTap: () => _showFullImage(context, path),
                                  onLongPress: () => _confirmDelete(context, chatService, img),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: file.existsSync()
                                        ? Image.file(file, fit: BoxFit.cover)
                                        : Container(
                                            color: Colors.white12,
                                            child: const Center(
                                              child: Text('File deleted',
                                                  style: TextStyle(
                                                      color: Colors.white38,
                                                      fontSize: 11)),
                                            ),
                                          ),
                                  ),
                                );
                              },
                            ),
                            // Voice notes list
                            ListView.builder(
                              padding: const EdgeInsets.all(12),
                              itemCount: voiceNotes.length,
                              itemBuilder: (ctx, i) {
                                final vn = voiceNotes[i];
                                return Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.mic, color: Colors.white70),
                                      const SizedBox(width: 12),
                                      Text(
                                        'Voice Note${vn.mediaDurationMs != null ? ' (${(vn.mediaDurationMs! / 1000).toStringAsFixed(0)}s)' : ''}',
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  void _showFullImage(BuildContext context, String path) {
    final file = File(path);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Save to Gallery',
                onPressed: () async {
                  final ok =
                      await LocalMediaService.downloadToGallery(path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(ok
                            ? 'Saved to Gallery ✅'
                            : 'Failed to save to Gallery'),
                        backgroundColor:
                            ok ? Colors.green : Colors.redAccent,
                      ),
                    );
                  }
                },
              ),
            ],
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: file.existsSync()
                  ? Image.file(file, fit: BoxFit.contain)
                  : const Text('File deleted',
                      style: TextStyle(color: Colors.white54)),
            ),
          ),
        ),
      ),
    );
  }

  void _confirmDelete(
      BuildContext context, ChatService chatService, ChatMessage msg) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1B3D),
        title:
            const Text('Delete media?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will remove the media for everyone.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              chatService.deleteForEveryone(
                coupleId: coupleId,
                messageId: msg.id,
              );
              Navigator.pop(ctx);
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
