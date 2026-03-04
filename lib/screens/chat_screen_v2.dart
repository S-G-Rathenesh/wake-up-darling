import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';

import '../models/chat_message_model.dart';
import '../services/chat_service.dart';
import '../services/local_media_service.dart';
import '../services/media_service.dart';
import '../widgets/chat_romantic_bg.dart';
import '../widgets/romantic_hearts_overlay.dart';
import '../widgets/typing_dots.dart';
import '../widgets/voice_bubble.dart';
import 'shared_media_screen.dart';

/// Full-featured WhatsApp-level couple chat screen.
///
/// When [embedded] is `true` the widget renders without its own Scaffold &
/// AppBar so it can be dropped into a TabBarView or any other parent layout.
class ChatScreenV2 extends StatefulWidget {
  final String coupleId;
  final String partnerId;
  final String partnerName;
  final bool embedded;

  const ChatScreenV2({
    super.key,
    required this.coupleId,
    required this.partnerId,
    this.partnerName = 'Partner',
    this.embedded = false,
  });

  @override
  State<ChatScreenV2> createState() => _ChatScreenV2State();
}

class _ChatScreenV2State extends State<ChatScreenV2> with WidgetsBindingObserver {
  final _chatService = ChatService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _imagePicker = ImagePicker();
  final _recorder = AudioRecorder();

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  bool _showEmoji = false;
  bool _isRecording = false;
  bool _isUploading = false;
  bool _isSearching = false;
  String _searchQuery = '';
  final _searchController = TextEditingController();
  DateTime? _recordStartedAt;

  // Reply state
  ChatMessage? _replyTo;

  // Partner status
  bool _partnerOnline = false;
  DateTime? _partnerLastSeen;
  bool _partnerTyping = false;

  StreamSubscription? _statusSub;
  StreamSubscription? _typingSub;
  Timer? _typingTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chatService.setOnlineStatus(true);
    _chatService.markMessagesAsRead(widget.coupleId);
    _chatService.markMessagesAsDelivered(widget.coupleId);

    _statusSub = _chatService.partnerStatusStream(widget.partnerId).listen((s) {
      if (mounted) {
        setState(() {
          _partnerOnline = s['online'] == true;
          _partnerLastSeen = s['lastSeen'] as DateTime?;
        });
      }
    });

    _typingSub = _chatService.partnerTypingStream(widget.partnerId).listen((t) {
      if (mounted) setState(() => _partnerTyping = t);
    });

    _controller.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    _chatService.setTyping(_controller.text.isNotEmpty);
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 5), () {
      _chatService.setTyping(false);
    });
    // No setState here — the send/mic button uses ValueListenableBuilder
    // so only that widget rebuilds, not the entire chat message list.
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _chatService.setOnlineStatus(true);
      _chatService.markMessagesAsRead(widget.coupleId);
    } else if (state == AppLifecycleState.paused) {
      _chatService.setOnlineStatus(false);
      _chatService.setTyping(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusSub?.cancel();
    _typingSub?.cancel();
    _typingTimer?.cancel();
    _chatService.setTyping(false);
    _controller.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _searchController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  // ─── Sending ──────────────────────────────────────────────────────────────

  void _sendText() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    _chatService.sendTextMessage(
      coupleId: widget.coupleId,
      receiverId: widget.partnerId,
      text: text,
      replyToMessageId: _replyTo?.id,
      replyToText: _replyTo?.text,
      replyToSenderId: _replyTo?.senderId,
    );
    _controller.clear();
    _clearReply();
    _scrollToBottom();
  }

  Future<void> _pickAndSendImage({bool isOneTime = false}) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;
    
    setState(() => _isUploading = true);
    try {
      await _chatService.sendImageMessage(
        coupleId: widget.coupleId,
        receiverId: widget.partnerId,
        imageFile: File(picked.path),
        isOneTime: isOneTime,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  Future<void> _takePhotoAndSend({bool isOneTime = false}) async {
    final picked = await _imagePicker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1200,
      imageQuality: 80,
    );
    if (picked == null) return;
    
    setState(() => _isUploading = true);
    try {
      await _chatService.sendImageMessage(
        coupleId: widget.coupleId,
        receiverId: widget.partnerId,
        imageFile: File(picked.path),
        isOneTime: isOneTime,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Image upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  // ─── Voice Recording ─────────────────────────────────────────────────────

  Future<void> _startRecording() async {
    if (await _recorder.hasPermission()) {
      final dir = await getTemporaryDirectory();
      final path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: path);
      setState(() {
        _isRecording = true;
        _recordStartedAt = DateTime.now();
      });
    }
  }

  Future<void> _stopAndSendRecording() async {
    final path = await _recorder.stop();
    final durationMs = _recordStartedAt != null
        ? DateTime.now().difference(_recordStartedAt!).inMilliseconds
        : 0;
    setState(() => _isRecording = false);
    if (path == null) return;

    // Prevent sending if duration is 0 or too short (< 500ms)
    if (durationMs < 500) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording too short')),
        );
      }
      return;
    }

    setState(() => _isUploading = true);
    try {
      await _chatService.sendVoiceMessage(
        coupleId: widget.coupleId,
        receiverId: widget.partnerId,
        audioFile: File(path),
        durationMs: durationMs,
      );
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _cancelRecording() async {
    await _recorder.stop();
    setState(() => _isRecording = false);
  }

  // ─── Reply ────────────────────────────────────────────────────────────────

  void _setReply(ChatMessage msg) => setState(() => _replyTo = msg);
  void _clearReply() => setState(() => _replyTo = null);

  // ─── Scroll ───────────────────────────────────────────────────────────────

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 250), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          0.0, // with reverse: true, 0.0 is the bottom (newest)
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // ─── Formatting ───────────────────────────────────────────────────────────

  String _formatTime(DateTime dt) => DateFormat('h:mm a').format(dt);

  String _formatDateHeader(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final msgDay = DateTime(dt.year, dt.month, dt.day);
    if (msgDay == today) return 'Today';
    if (msgDay == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return DateFormat('MMM d, yyyy').format(dt);
  }

  String _lastSeenText() {
    if (_partnerOnline) return 'online';
    if (_partnerLastSeen == null) return '';
    final now = DateTime.now();
    final seen = _partnerLastSeen!;
    final today = DateTime(now.year, now.month, now.day);
    final seenDay = DateTime(seen.year, seen.month, seen.day);
    final timeStr = DateFormat('h:mm a').format(seen);
    if (seenDay == today) {
      return 'last seen today at $timeStr';
    } else if (seenDay == today.subtract(const Duration(days: 1))) {
      return 'last seen yesterday at $timeStr';
    } else {
      return 'last seen ${DateFormat('MMM d').format(seen)} at $timeStr';
    }
  }

  bool _shouldShowDateHeader(DateTime? prev, DateTime? current) {
    if (prev == null || current == null) return true;
    return prev.year != current.year ||
        prev.month != current.month ||
        prev.day != current.day;
  }

  // ─── Message Actions ─────────────────────────────────────────────────────

  void _showMessageOptions(ChatMessage msg) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF2A1B3D),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (msg.messageType == MessageType.text)
              _optionTile(Icons.copy, 'Copy', () {
                Clipboard.setData(ClipboardData(text: msg.text));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Copied')));
              }),
            _optionTile(Icons.reply, 'Reply', () {
              Navigator.pop(ctx);
              _setReply(msg);
              _focusNode.requestFocus();
            }),
            // Emoji reaction shortcut
            _optionTile(Icons.emoji_emotions, 'React', () {
              Navigator.pop(ctx);
              _showReactionPicker(msg);
            }),
            if (msg.canEdit(_myUid))
              _optionTile(Icons.edit, 'Edit', () {
                Navigator.pop(ctx);
                _showEditDialog(msg);
              }),
            if (msg.senderId == _myUid)
              _optionTile(Icons.delete_forever, 'Delete for Everyone', () {
                _chatService.deleteForEveryone(
                    coupleId: widget.coupleId, messageId: msg.id);
                Navigator.pop(ctx);
              }),
            _optionTile(Icons.delete_outline, 'Delete for Me', () {
              _chatService.deleteForMe(
                  coupleId: widget.coupleId, messageId: msg.id);
              Navigator.pop(ctx);
            }),
          ],
        ),
      ),
    );
  }

  Widget _optionTile(IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: onTap,
    );
  }

  void _showReactionPicker(ChatMessage msg) {
    final emojis = ['❤️', '😂', '😮', '😢', '👍', '🔥'];
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1B3D),
        content: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: emojis.map((e) {
            return GestureDetector(
              onTap: () {
                _chatService.toggleReaction(
                  coupleId: widget.coupleId,
                  messageId: msg.id,
                  emoji: e,
                );
                Navigator.pop(ctx);
              },
              child: Text(e, style: const TextStyle(fontSize: 28)),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _showEditDialog(ChatMessage msg) {
    final editCtrl = TextEditingController(text: msg.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF2A1B3D),
        title: const Text('Edit Message', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: editCtrl,
          style: const TextStyle(color: Colors.white),
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Edit your message...',
            hintStyle: TextStyle(color: Colors.white54),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              await _chatService.editMessage(
                coupleId: widget.coupleId,
                messageId: msg.id,
                newText: editCtrl.text.trim(),
              );
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  Widget _buildChatBody() {
    return Stack(
      children: [
        const Positioned.fill(child: ChatRomanticBackground()),
        Column(
      children: [
        // ── Online / Last Seen status (embedded mode) ─────────────
        if (widget.embedded)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            color: Colors.white.withValues(alpha: 0.06),
            child: Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _partnerOnline
                        ? const Color(0xFF69F0AE)
                        : Colors.white.withValues(alpha: 0.35),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _partnerTyping
                        ? '${widget.partnerName} is typing...'
                        : _partnerOnline
                            ? '${widget.partnerName} is online'
                            : _lastSeenText().isNotEmpty
                                ? '${widget.partnerName} · ${_lastSeenText()}'
                                : widget.partnerName,
                    style: TextStyle(
                      color: _partnerOnline
                          ? const Color(0xFF69F0AE)
                          : Colors.white.withValues(alpha: 0.6),
                      fontSize: 12,
                      fontStyle: _partnerTyping ? FontStyle.italic : FontStyle.normal,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),

        // ── Search bar (embedded mode) ──────────────────────────────
        if (widget.embedded)
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            child: _isSearching
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    color: Colors.white.withValues(alpha: 0.08),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: const TextStyle(color: Colors.white, fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search messages...',
                              hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                              prefixIcon: const Icon(Icons.search, color: Colors.white54, size: 20),
                              filled: true,
                              fillColor: Colors.white.withValues(alpha: 0.10),
                              contentPadding: const EdgeInsets.symmetric(vertical: 8),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(20),
                                borderSide: BorderSide.none,
                              ),
                            ),
                            onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white70, size: 20),
                          onPressed: () => setState(() {
                            _isSearching = false;
                            _searchQuery = '';
                            _searchController.clear();
                          }),
                        ),
                      ],
                    ),
                  )
                : Align(
                    alignment: Alignment.centerRight,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4, top: 2),
                      child: IconButton(
                        icon: const Icon(Icons.search, color: Colors.white54, size: 20),
                        tooltip: 'Search messages',
                        onPressed: () => setState(() => _isSearching = true),
                      ),
                    ),
                  ),
          ),

        // Typing indicator (non-embedded only; embedded shows it in status bar)
        if (_partnerTyping && !widget.embedded)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Text(
                  '${widget.partnerName} ',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontStyle: FontStyle.italic,
                    fontSize: 13,
                  ),
                ),
                const TypingDots(dotSize: 7),
              ],
            ),
          ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.2, end: 0, duration: 300.ms),

        // Messages
        Expanded(child: _buildMessageList()),

        // Reply preview
        if (_replyTo != null) _buildReplyPreview(),

        // Input bar
        _buildInputBar(),

        // Emoji picker
        if (_showEmoji)
          SizedBox(
            height: 260,
            child: EmojiPicker(
              onEmojiSelected: (_, emoji) {
                _controller.text += emoji.emoji;
                _controller.selection = TextSelection.fromPosition(
                  TextPosition(offset: _controller.text.length),
                );
              },
              config: const Config(
                height: 260,
                emojiViewConfig: EmojiViewConfig(
                  columns: 7,
                  emojiSizeMax: 28,
                  backgroundColor: Color(0xFF1A0A2E),
                ),
                categoryViewConfig: CategoryViewConfig(
                  backgroundColor: Color(0xFF1A0A2E),
                  iconColorSelected: Colors.purpleAccent,
                  iconColor: Colors.white38,
                  indicatorColor: Colors.purpleAccent,
                ),
                searchViewConfig: SearchViewConfig(
                  backgroundColor: Color(0xFF1A0A2E),
                  buttonIconColor: Colors.white54,
                ),
              ),
            ),
          ),
      ],
    ),  // end Column
      ],
    );  // end Stack
  }

  @override
  Widget build(BuildContext context) {
    // Embedded mode: skip Scaffold & AppBar, just render the chat content.
    if (widget.embedded) {
      return _buildChatBody();
    }

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          // Background
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
            child: _buildChatBody(),
          ),
        ],
      ),
    );
  }

  // ─── AppBar ───────────────────────────────────────────────────────────────

  PreferredSizeWidget _buildAppBar() {
    if (_isSearching) {
      return AppBar(
        backgroundColor: const Color(0xFF8E2DE2).withValues(alpha: 0.90),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => setState(() {
            _isSearching = false;
            _searchQuery = '';
            _searchController.clear();
          }),
        ),
        title: TextField(
          controller: _searchController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Search messages...',
            hintStyle: TextStyle(color: Colors.white54),
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _searchQuery = v.toLowerCase()),
        ),
      );
    }

    return AppBar(
      backgroundColor: const Color(0xFF8E2DE2).withValues(alpha: 0.90),
      foregroundColor: Colors.white,
      elevation: 0,
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${widget.partnerName} 💬', style: const TextStyle(fontSize: 17)),
          Text(
            _partnerTyping ? 'typing...' : _lastSeenText(),
            style: TextStyle(
              fontSize: 12,
              color: _partnerOnline
                  ? const Color(0xFF69F0AE)
                  : Colors.white.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          onPressed: () => setState(() => _isSearching = true),
        ),
        IconButton(
          icon: const Icon(Icons.photo_library_outlined),
          tooltip: 'Shared Media',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => SharedMediaScreen(coupleId: widget.coupleId),
            ),
          ),
        ),
        PopupMenuButton<String>(
          icon: const Icon(Icons.more_vert),
          color: const Color(0xFF2A1B3D),
          onSelected: (v) {
            if (v == 'gallery') {
              _pickAndSendImage();
            } else if (v == 'camera') {
              _takePhotoAndSend();
            } else if (v == 'one_time') {
              _pickAndSendImage(isOneTime: true);
            }
          },
          itemBuilder: (_) => [
            const PopupMenuItem(value: 'gallery', child: Text('Send Image', style: TextStyle(color: Colors.white))),
            const PopupMenuItem(value: 'camera', child: Text('Take Photo', style: TextStyle(color: Colors.white))),
            const PopupMenuItem(value: 'one_time', child: Text('One-Time Image 🔒', style: TextStyle(color: Colors.white))),
          ],
        ),
      ],
    );
  }

  // ─── Message List ─────────────────────────────────────────────────────────

  Widget _buildMessageList() {
    return StreamBuilder<List<ChatMessage>>(
      stream: _chatService.streamMessages(widget.coupleId),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white54),
          );
        }

        var messages = snapshot.data ?? [];
        if (_searchQuery.isNotEmpty) {
          messages = messages
              .where((m) => m.text.toLowerCase().contains(_searchQuery))
              .toList();
        }

        if (messages.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.chat_bubble_outline,
                    color: Colors.white.withValues(alpha: 0.5), size: 64),
                const SizedBox(height: 12),
                Text(
                  'No messages yet 💌\nSay hi to your partner!',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          );
        }

        // Mark as read when messages are visible.
        _chatService.markMessagesAsRead(widget.coupleId);

        // Reverse for reverse: true ListView (index 0 = newest at bottom).
        final reversed = messages.reversed.toList();

        return ListView.builder(
          key: const PageStorageKey('chat_list'),
          controller: _scrollController,
          reverse: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          itemCount: reversed.length,
          itemBuilder: (context, index) {
            final msg = reversed[index];
            final isMe = msg.senderId == _myUid;

            // With reverse: true, the message visually ABOVE this one
            // is at index + 1 (older message). Show a date header when
            // the day changes between this message and the one above.
            final olderMsg = index < reversed.length - 1
                ? reversed[index + 1]
                : null;

            Widget? dateHeader;
            if (_shouldShowDateHeader(olderMsg?.timestamp, msg.timestamp)) {
              dateHeader = Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _formatDateHeader(msg.timestamp),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              );
            }

            return Column(
              key: ValueKey('col_${msg.id}'),
              children: [
                ?dateHeader,
                _MessageBubbleV2(
                  key: ValueKey(msg.id),
                  message: msg,
                  isMe: isMe,
                  myUid: _myUid,
                  formatTime: _formatTime,
                  onLongPress: () => _showMessageOptions(msg),
                  onReply: () => _setReply(msg),
                  onOneTimeView: () {
                    _chatService.markOneTimeViewed(
                      coupleId: widget.coupleId,
                      messageId: msg.id,
                    );
                    // Auto-delete message from Firestore after one-time view
                    Future.delayed(const Duration(seconds: 6), () {
                      _chatService.deleteForEveryone(
                        coupleId: widget.coupleId,
                        messageId: msg.id,
                      );
                    });
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  // ─── Reply Preview ────────────────────────────────────────────────────────

  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        border: Border(
          left: BorderSide(color: Colors.purpleAccent.withValues(alpha: 0.7), width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyTo!.senderId == _myUid ? 'You' : widget.partnerName,
                  style: const TextStyle(
                    color: Colors.purpleAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  _replyTo!.messageType == MessageType.text
                      ? _replyTo!.text
                      : '📎 ${_replyTo!.messageType.name}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 18),
            onPressed: _clearReply,
          ),
        ],
      ),
    );
  }

  // ─── Input Bar ────────────────────────────────────────────────────────────

  Widget _buildInputBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        border: Border(
          top: BorderSide(color: Colors.white.withValues(alpha: 0.15)),
        ),
      ),
      child: Row(
        children: [
          // Emoji toggle
          IconButton(
            icon: Icon(
              _showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
              color: Colors.white70,
            ),
            onPressed: () {
              if (_showEmoji) {
                _focusNode.requestFocus();
              } else {
                _focusNode.unfocus();
              }
              setState(() => _showEmoji = !_showEmoji);
            },
          ),

          // Text field
          Expanded(
            child: TextField(
              controller: _controller,
              focusNode: _focusNode,
              style: const TextStyle(color: Colors.white),
              textCapitalization: TextCapitalization.sentences,
              maxLines: 4,
              minLines: 1,
              decoration: InputDecoration(
                hintText: _isRecording ? 'Recording...' : 'Type a message...',
                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.12),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _sendText(),
              onTap: () {
                if (_showEmoji) setState(() => _showEmoji = false);
              },
            ),
          ),
          const SizedBox(width: 4),

          // Attachment button — shows gallery, camera, one-time options
          PopupMenuButton<String>(
            icon: const Icon(Icons.attach_file, color: Colors.white70),
            color: const Color(0xFF2A1B3D),
            onSelected: (v) {
              if (v == 'gallery') {
                _pickAndSendImage();
              } else if (v == 'camera') {
                _takePhotoAndSend();
              } else if (v == 'one_time') {
                _pickAndSendImage(isOneTime: true);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'gallery', child: Text('📷 Gallery', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: 'camera', child: Text('📸 Camera', style: TextStyle(color: Colors.white))),
              PopupMenuItem(value: 'one_time', child: Text('🔒 One-Time Image', style: TextStyle(color: Colors.white))),
            ],
          ),

          // Send / Voice record button — wrapped in ValueListenableBuilder
          // so only this widget rebuilds when text changes, not the whole chat.
          if (_isUploading)
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                gradient: LinearGradient(
                  colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
                ),
              ),
              child: const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _controller,
            builder: (context, value, _) {
              final hasText = value.text.trim().isNotEmpty;
              if (hasText) {
                return GestureDetector(
                  onTap: _sendText,
                  child: Container(
                    padding: const EdgeInsets.all(10),
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
                      ),
                    ),
                    child: const Icon(Icons.send_rounded, color: Colors.white, size: 22),
                  ),
                );
              }
              return GestureDetector(
                onLongPressStart: (_) => _startRecording(),
                onLongPressEnd: (_) => _stopAndSendRecording(),
                onLongPressCancel: () => _cancelRecording(),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: _isRecording ? Colors.redAccent : null,
                    gradient: _isRecording
                        ? null
                        : const LinearGradient(
                            colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)],
                          ),
                  ),
                  child: Icon(
                    _isRecording ? Icons.mic : Icons.mic_none,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
// MESSAGE BUBBLE V2
// ═══════════════════════════════════════════════════════════════════════════════

class _MessageBubbleV2 extends StatelessWidget {
  final ChatMessage message;
  final bool isMe;
  final String myUid;
  final String Function(DateTime) formatTime;
  final VoidCallback onLongPress;
  final VoidCallback onReply;
  final VoidCallback onOneTimeView;

  const _MessageBubbleV2({
    super.key,
    required this.message,
    required this.isMe,
    required this.myUid,
    required this.formatTime,
    required this.onLongPress,
    required this.onReply,
    required this.onOneTimeView,
  });

  Widget _readStatusIcon() {
    if (!isMe) return const SizedBox.shrink();
    switch (message.readStatus) {
      case ReadStatus.sent:
        return const Icon(Icons.check, size: 14, color: Colors.white54);
      case ReadStatus.delivered:
        return const Icon(Icons.done_all, size: 14, color: Colors.white54);
      case ReadStatus.read:
        return const Icon(Icons.done_all, size: 14, color: Colors.lightBlueAccent);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (message.deletedForEveryone) {
      return Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Text(
            '🚫 This message was deleted',
            style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic, fontSize: 13),
          ),
        ),
      );
    }

    return GestureDetector(
      onLongPress: onLongPress,
      onHorizontalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) > 200) onReply();
      },
      child: Align(
        alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
        child: Column(
          crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            // Reply reference
            if (message.replyToMessageId != null)
              Container(
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border(
                    left: BorderSide(
                      color: Colors.purpleAccent.withValues(alpha: 0.6),
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  message.replyToText ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 12),
                ),
              ),

            // Bubble
            Container(
              margin: const EdgeInsets.symmetric(vertical: 3),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75,
              ),
              decoration: BoxDecoration(
                gradient: isMe
                    ? const LinearGradient(colors: [Color(0xFFE040FB), Color(0xFF7C4DFF)])
                    : null,
                color: isMe ? null : Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: Radius.circular(isMe ? 18 : 4),
                  bottomRight: Radius.circular(isMe ? 4 : 18),
                ),
              ),
              child: Column(
                crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  // Content by type
                  _buildContent(context),

                  const SizedBox(height: 3),
                  // Timestamp + edit badge + read status
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (message.editedAt != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: Text(
                            'edited',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.5),
                              fontSize: 10,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ),
                      Text(
                        formatTime(message.timestamp),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.6),
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      _readStatusIcon(),
                    ],
                  ),
                ],
              ),
            ),

            // Reactions
            if (message.reactions.isNotEmpty)
              Container(
                margin: const EdgeInsets.only(top: 2),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  message.reactions.values.join(' '),
                  style: const TextStyle(fontSize: 16),
                ),
              ),
          ],
        ),
      ),
    );
  }

  static void _openFullImage(BuildContext context, String localPath) {
    final file = File(localPath);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            actions: [
              // Download to gallery button
              IconButton(
                icon: const Icon(Icons.download),
                tooltip: 'Save to Gallery',
                onPressed: () async {
                  final ok =
                      await LocalMediaService.downloadToGallery(localPath);
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

  /// Resolves the display path for an image/voice message.
  /// Prefers localPath, falls back to mediaUrl (legacy).
  String? get _resolvedPath => message.localPath ?? message.mediaUrl;

  /// Whether the mediaUrl is a remote URL (not a local file path).
  bool get _isRemoteUrl {
    final url = message.mediaUrl;
    return url != null && (url.startsWith('http://') || url.startsWith('https://'));
  }

  Widget _buildContent(BuildContext context) {
    switch (message.messageType) {
      case MessageType.text:
        return Text(
          message.text,
          style: const TextStyle(color: Colors.white, fontSize: 15),
        );

      case MessageType.image:
        if (message.isDeleted) {
          return const Text('File deleted',
              style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic));
        }
        // If we have a remote URL, download to local first
        if (_isRemoteUrl) {
          return FutureBuilder<String>(
            future: MediaService.downloadToLocal(message.mediaUrl!, message.id),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const SizedBox(
                  width: 200,
                  height: 150,
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white54, strokeWidth: 2),
                  ),
                );
              }
              if (snapshot.hasError || !snapshot.hasData) {
                return const Text('📷 Failed to load image',
                    style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic));
              }
              final localPath = snapshot.data!;
              final file = File(localPath);
              if (!file.existsSync()) {
                return const Text('📷 File deleted',
                    style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic));
              }
              return GestureDetector(
                onTap: () => _openFullImage(context, localPath),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(
                    file,
                    width: 200,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        const Icon(Icons.broken_image, color: Colors.white54),
                  ),
                ),
              );
            },
          );
        }
        // Local file path (legacy or voice)
        final path = _resolvedPath;
        if (path == null || path.isEmpty) {
          return const Text('📷 Image', style: TextStyle(color: Colors.white70));
        }
        final file = File(path);
        if (!file.existsSync()) {
          return const Text('📷 File deleted',
              style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic));
        }
        return GestureDetector(
          onTap: () => _openFullImage(context, path),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              file,
              width: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) =>
                  const Icon(Icons.broken_image, color: Colors.white54),
            ),
          ),
        );

      case MessageType.voice:
        if (message.isDeleted) {
          return const Text('File deleted',
              style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic));
        }
        final voiceUrl = message.mediaUrl ?? message.localPath;
        if (voiceUrl == null || voiceUrl.isEmpty) {
          return const Text('Voice unavailable',
              style: TextStyle(color: Colors.white38, fontStyle: FontStyle.italic));
        }
        return VoiceBubble(
          audioUrl: voiceUrl,
          durationMs: message.mediaDurationMs,
          isMine: isMe,
        );

      case MessageType.oneTime:
        if (message.isDeleted) {
          return const Text(
            'File deleted',
            style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
          );
        }
        if (message.isOneTimeViewed || message.oneTimeViewedBy.contains(myUid)) {
          return const Text(
            '🔒 One-time photo viewed',
            style: TextStyle(color: Colors.white54, fontStyle: FontStyle.italic),
          );
        }
        if (!isMe) {
          return GestureDetector(
            onTap: () {
              final data = message.imageData;
              if (data != null && data.isNotEmpty) {
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (ctx) => _OneTimeImageViewer(
                    imageData: data,
                    messageId: message.id,
                    onViewed: () {
                      onOneTimeView();
                      Navigator.pop(ctx);
                    },
                  ),
                );
              }
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.photo_camera, color: Colors.white70),
                  SizedBox(width: 8),
                  Text('🔒 Tap to view once',
                      style: TextStyle(color: Colors.white70)),
                ],
              ),
            ),
          );
        }
        return const Text(
          '🔒 One-time photo sent',
          style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
        );
    }
  }
}

// ─── One-Time Image Viewer ──────────────────────────────────────────────────

class _OneTimeImageViewer extends StatefulWidget {
  final String imageData;   // base64 encoded image
  final String messageId;
  final VoidCallback onViewed;
  const _OneTimeImageViewer({required this.imageData, required this.messageId, required this.onViewed});

  @override
  State<_OneTimeImageViewer> createState() => _OneTimeImageViewerState();
}

class _OneTimeImageViewerState extends State<_OneTimeImageViewer> {
  static const _channel = MethodChannel('ultra_alarm');
  Uint8List? _imageBytes;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    // Enable FLAG_SECURE to block screenshots/screen recording.
    _channel.invokeMethod('enableSecureMode').catchError((_) {});
    _decodeImage();
  }

  void _decodeImage() {
    try {
      _imageBytes = base64Decode(widget.imageData);
      if (mounted) {
        setState(() => _loading = false);
      }
      // Auto close after 3 seconds.
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted) _close();
      });
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _close() {
    _channel.invokeMethod('disableSecureMode').catchError((_) {});
    _imageBytes = null; // Clear from memory immediately
    widget.onViewed();
  }

  @override
  void dispose() {
    _imageBytes = null;
    // Safety net: always clear secure mode.
    _channel.invokeMethod('disableSecureMode').catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onTap: _close,
        child: Stack(
          children: [
            Center(
              child: _loading
                  ? const CircularProgressIndicator(color: Colors.white54)
                  : _imageBytes != null
                      ? Image.memory(_imageBytes!, fit: BoxFit.contain)
                      : const Text('Image unavailable',
                          style: TextStyle(color: Colors.white54)),
            ),
            // Watermark overlay
            Positioned(
              top: 80,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  '🔒 One-Time View',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.3),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            // Countdown hint
            Positioned(
              bottom: 60,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  'Auto-closes in 3 seconds • Tap to close',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
