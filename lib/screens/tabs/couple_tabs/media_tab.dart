import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/chat_message_model.dart';
import '../../../services/chat_service.dart';
import '../../../services/local_media_service.dart';
import '../../../widgets/animated_empty_state.dart';

/// Media sub-tab inside the Couple Dashboard.
/// Shows shared images and voice notes in a grid gallery — adapted from
/// SharedMediaScreen to work as an embedded tab (no separate Scaffold).
class CoupleMedia extends StatelessWidget {
  final String coupleId;

  const CoupleMedia({super.key, required this.coupleId});

  @override
  Widget build(BuildContext context) {
    final chatService = ChatService();

    return FutureBuilder<List<ChatMessage>>(
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

        final images = media
            .where(
                (m) => m.messageType == MessageType.image &&
                    (m.localPath != null || m.mediaUrl != null))
            .toList();
        final voiceNotes =
            media.where((m) => m.messageType == MessageType.voice).toList();

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                indicatorColor: Colors.white,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white54,
                dividerColor: Colors.transparent,
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
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 4,
                        mainAxisSpacing: 4,
                      ),
                      itemCount: images.length,
                      itemBuilder: (ctx, i) {
                        final img = images[i];
                        final path = img.localPath ?? img.mediaUrl;
                        final file = path != null ? File(path) : null;
                        final exists = file != null && file.existsSync();
                        return GestureDetector(
                          onTap: exists ? () => _showFullImage(context, path!) : null,
                          onLongPress: () => _confirmDelete(context, chatService, img),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: exists
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
                  await LocalMediaService.downloadToGallery(path);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Saved to gallery')),
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
              child: Image.file(file, fit: BoxFit.contain),
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
              // Force rebuild
              (context as Element).markNeedsBuild();
            },
            child: const Text('Delete',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }
}
