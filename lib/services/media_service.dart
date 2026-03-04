import 'dart:io';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class MediaService {
  static final _storage = FirebaseStorage.instance;

  /// Whether [url] is a remote HTTP/HTTPS URL.
  static bool isRemoteUrl(String? url) =>
      url != null && (url.startsWith('http://') || url.startsWith('https://'));

  // Upload media (images)
  static Future<String> uploadFile(File file, String messageId) async {
    final ref = _storage.ref().child("chat_media/$messageId.jpg");
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  // Upload voice note
  static Future<String> uploadVoiceNote(File file, String messageId) async {
    final ext = file.path.split('.').last;
    final ref = _storage.ref().child("voice_notes/$messageId.$ext");
    await ref.putFile(file);
    return await ref.getDownloadURL();
  }

  /// Download media to private local storage.
  /// Handles both Cloudinary (plain HTTPS) and Firebase Storage URLs.
  static Future<String> downloadToLocal(String url, String messageId, {String extension = 'jpg'}) async {
    final dir = await getApplicationDocumentsDirectory();
    final filePath = "${dir.path}/$messageId.$extension";

    // Return cached file if it already exists
    final file = File(filePath);
    if (file.existsSync()) return filePath;

    try {
      if (url.contains('firebasestorage.googleapis.com') ||
          url.startsWith('gs://')) {
        // Firebase Storage URL — use SDK
        final ref = _storage.refFromURL(url);
        await ref.writeToFile(file);
      } else {
        // Cloudinary or any plain HTTPS URL — use HTTP download
        final response = await http.get(Uri.parse(url));
        if (response.statusCode == 200) {
          await file.writeAsBytes(response.bodyBytes);
        } else {
          throw Exception('HTTP ${response.statusCode} downloading $url');
        }
      }
    } catch (e) {
      debugPrint('[MediaService] downloadToLocal failed: $e');
      rethrow;
    }

    return filePath;
  }

  // Delete from storage
  static Future<void> deleteRemote(String url) async {
    try {
      if (url.contains('firebasestorage.googleapis.com') ||
          url.startsWith('gs://')) {
        final ref = _storage.refFromURL(url);
        await ref.delete();
      }
      // Cloudinary files are managed via Cloudinary dashboard; skip deletion.
    } catch (e) {
      // Ignore if already deleted
    }
  }
}
