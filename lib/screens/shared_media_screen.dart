import 'dart:io';

import 'package:flutter/material.dart';

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
import '../services/local_media_service.dart';
import '../services/media_service.dart';
import '../widgets/animated_empty_state.dart';
import '../widgets/romantic_hearts_overlay.dart';
import '../widgets/voice_bubble.dart';

/// Shows all shared images and voice notes in a grid gallery.
class SharedMediaScreen extends StatefulWidget {
  final String coupleId;
  const SharedMediaScreen({super.key, required this.coupleId});

  @override
  State<SharedMediaScreen> createState() => _SharedMediaScreenState();
}

class _SharedMediaScreenState extends State<SharedMediaScreen> {
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
    setState(() {});
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
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: _isSelecting
            ? Text('${_selectedIds.length} selected')
            : const Text('Shared Media 📸'),
        backgroundColor: const Color(0xFF8E2DE2).withValues(alpha: 0.85),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: _isSelecting
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _clearSelection,
              )
            : null,
        actions: _isSelecting
            ? [
                IconButton(
                  icon: const Icon(Icons.download),
                  tooltip: 'Save to Gallery',
                  onPressed: () => _saveSelectedToGallery(_cachedMedia ?? []),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.redAccent),
                  tooltip: 'Delete selected',
                  onPressed: () => _deleteSelected(_cachedMedia ?? []),
                ),
              ]
            : null,
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

                // Wire allMedia into the action bar callbacks
                // (rebuild when appBar actions need it)
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  // Cache for toolbar actions
                  _cachedMedia = media;
                });
                _cachedMedia ??= media;

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
                                final localPath = img.localPath;
                                final remoteUrl = img.mediaUrl;
                                final localFile = localPath != null ? File(localPath) : null;
                                final hasLocal = localFile != null && localFile.existsSync();
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
                                            ? Image.file(localFile!, fit: BoxFit.cover)
                                            : hasRemote
                                                ? Image.network(
                                                    remoteUrl!,
                                                    fit: BoxFit.cover,
                                                    loadingBuilder: (_, child, progress) {
                                                      if (progress == null) return child;
                                                      return const Center(
                                                        child: CircularProgressIndicator(
                                                          color: Colors.white54,
                                                          strokeWidth: 2,
                                                        ),
                                                      );
                                                    },
                                                    errorBuilder: (_, __, ___) => Container(
                                                      color: Colors.white12,
                                                      child: const Center(
                                                        child: Icon(Icons.broken_image,
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
            ),
          ),
        ],
      ),
    );
  }

  // Cache media list for toolbar actions that fire outside FutureBuilder
  List<ChatMessage>? _cachedMedia;

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
