import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/chat_message_model.dart';
import '../../../services/chat_service.dart';
import '../../../services/local_media_service.dart';
import '../../../services/media_service.dart';
import '../../../widgets/animated_empty_state.dart';
import '../../../widgets/voice_bubble.dart';

/// Media sub-tab inside the Couple Dashboard.
/// Shows shared images and voice notes in a grid gallery — adapted from
/// SharedMediaScreen to work as an embedded tab (no separate Scaffold).
class CoupleMedia extends StatefulWidget {
  final String coupleId;

  const CoupleMedia({super.key, required this.coupleId});

  @override
  State<CoupleMedia> createState() => _CoupleMediaState();
}

class _CoupleMediaState extends State<CoupleMedia> {
  final ChatService _chatService = ChatService();
  final Set<String> _selectedIds = {};
  bool get _isSelecting => _selectedIds.isNotEmpty;

  void _toggleSelection(String messageId) {
    setState(() {
      if (_selectedIds.contains(messageId)) {
        _selectedIds.remove(messageId);
      } else {
        _selectedIds.add(messageId);
      }
    });
  }

  void _clearSelection() => setState(() => _selectedIds.clear());

  Future<void> _deleteSelected(List<ChatMessage> allMedia) async {
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1B3D),
        title: Text('Delete $count item${count > 1 ? 's' : ''}?',
            style: const TextStyle(color: Colors.white)),
        content: const Text('This will remove the media for everyone.',
            style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child:
                const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    for (final id in _selectedIds) {
      await _chatService.deleteForEveryone(
          coupleId: widget.coupleId, messageId: id);
    }
    _clearSelection();
    setState(() {}); // force rebuild
  }

  Future<void> _saveSelectedToGallery(List<ChatMessage> allMedia) async {
    int saved = 0;
    for (final id in _selectedIds) {
      final msg = allMedia.firstWhere((m) => m.id == id,
          orElse: () => allMedia.first);
      if (msg.id != id) continue;

      String? localPath = msg.localPath;
      final hasLocal = localPath != null && File(localPath).existsSync();

      if (!hasLocal && MediaService.isRemoteUrl(msg.mediaUrl)) {
        try {
          localPath = await MediaService.downloadToLocal(
              msg.mediaUrl!, msg.id,
              extension: 'jpg');
        } catch (_) {
          continue;
        }
      }
      if (localPath != null && File(localPath).existsSync()) {
        final ok = await LocalMediaService.downloadToGallery(localPath);
        if (ok) saved++;
      }
    }
    _clearSelection();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Saved $saved image(s) to gallery ✅')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<ChatMessage>>(
      future: _chatService.getSharedMedia(widget.coupleId),
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
            .where((m) =>
                m.messageType == MessageType.image &&
                (m.localPath != null || m.mediaUrl != null))
            .toList();
        final voiceNotes =
            media.where((m) => m.messageType == MessageType.voice).toList();

        return DefaultTabController(
          length: 2,
          child: Column(
            children: [
              // ── Selection action bar ──
              if (_isSelecting)
                Container(
                  color: const Color(0xFF2A1B3D),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: _clearSelection,
                      ),
                      Text('${_selectedIds.length} selected',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 16)),
                      const Spacer(),
                      IconButton(
                        icon:
                            const Icon(Icons.download, color: Colors.white),
                        tooltip: 'Save to Gallery',
                        onPressed: () => _saveSelectedToGallery(media),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.redAccent),
                        tooltip: 'Delete selected',
                        onPressed: () => _deleteSelected(media),
                      ),
                    ],
                  ),
                ),
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
                        final localPath = img.localPath;
                        final remoteUrl = img.mediaUrl;
                        final localFile =
                            localPath != null ? File(localPath) : null;
                        final hasLocal =
                            localFile != null && localFile.existsSync();
                        final hasRemote = MediaService.isRemoteUrl(remoteUrl);
                        final isSelected = _selectedIds.contains(img.id);

                        return GestureDetector(
                          onTap: () {
                            if (_isSelecting) {
                              _toggleSelection(img.id);
                            } else if (hasLocal) {
                              _showFullImage(context, localPath!);
                            } else if (hasRemote) {
                              _showFullImageNetwork(context, remoteUrl!);
                            }
                          },
                          onLongPress: () => _toggleSelection(img.id),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: hasLocal
                                    ? Image.file(localFile!,
                                        fit: BoxFit.cover)
                                    : hasRemote
                                        ? Image.network(
                                            remoteUrl!,
                                            fit: BoxFit.cover,
                                            loadingBuilder:
                                                (_, child, progress) {
                                              if (progress == null)
                                                return child;
                                              return const Center(
                                                child:
                                                    CircularProgressIndicator(
                                                  color: Colors.white54,
                                                  strokeWidth: 2,
                                                ),
                                              );
                                            },
                                            errorBuilder: (_, __, ___) =>
                                                Container(
                                              color: Colors.white12,
                                              child: const Center(
                                                child: Icon(
                                                    Icons.broken_image,
                                                    color: Colors.white38),
                                              ),
                                            ),
                                          )
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
                              // Selection overlay
                              if (isSelected)
                                Container(
                                  decoration: BoxDecoration(
                                    color: Colors.blue.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: Colors.blueAccent, width: 2),
                                  ),
                                  child: const Align(
                                    alignment: Alignment.topRight,
                                    child: Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Icons.check_circle,
                                          color: Colors.white, size: 22),
                                    ),
                                  ),
                                ),
                            ],
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
                        final isVnSelected = _selectedIds.contains(vn.id);
                        final voiceUrl = vn.mediaUrl ?? vn.localPath;
                        return GestureDetector(
                          onLongPress: () => _toggleSelection(vn.id),
                          onTap: () {
                            if (_isSelecting) {
                              _toggleSelection(vn.id);
                            }
                            // Playback handled by VoiceBubble internally
                          },
                          child: Stack(
                            children: [
                              Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(16),
                                  border: isVnSelected
                                      ? Border.all(color: Colors.blueAccent, width: 2)
                                      : null,
                                ),
                                child: voiceUrl != null && voiceUrl.isNotEmpty
                                    ? VoiceBubble(
                                        audioUrl: voiceUrl,
                                        durationMs: vn.mediaDurationMs,
                                        isMine: true,
                                      )
                                    : Row(
                                        children: [
                                          const Icon(Icons.mic, color: Colors.white70),
                                          const SizedBox(width: 12),
                                          Text(
                                            'Voice Note${vn.mediaDurationMs != null ? ' (${(vn.mediaDurationMs! / 1000).toStringAsFixed(0)}s)' : ''}',
                                            style: const TextStyle(color: Colors.white),
                                          ),
                                        ],
                                      ),
                              ),
                              if (isVnSelected)
                                const Positioned(
                                  right: 10,
                                  top: 10,
                                  child: Icon(Icons.check_circle,
                                      color: Colors.green, size: 22),
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

  void _showFullImageNetwork(BuildContext context, String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                url,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(color: Colors.white54),
                  );
                },
                errorBuilder: (_, __, ___) => const Text(
                  'Failed to load image',
                  style: TextStyle(color: Colors.white54),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
