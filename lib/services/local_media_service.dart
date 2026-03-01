import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:gallery_saver_plus/gallery_saver.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Private local media storage service.
///
/// All media is saved inside `getApplicationDocumentsDirectory()`
/// so it does NOT appear in the phone gallery and is deleted on
/// app uninstall.
class LocalMediaService {
  LocalMediaService._();

  static Directory? _cacheDir;

  /// Returns the private media root directory, creating it if needed.
  static Future<Directory> _mediaDir() async {
    if (_cacheDir != null && _cacheDir!.existsSync()) return _cacheDir!;
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/chat_media');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    _cacheDir = dir;
    return dir;
  }

  /// Save raw bytes to private storage.
  ///
  /// Returns the absolute path of the saved file.
  static Future<String> savePrivateFile(
    Uint8List bytes,
    String fileName,
  ) async {
    final dir = await _mediaDir();
    final file = File('${dir.path}/$fileName');
    await file.writeAsBytes(bytes, flush: true);
    debugPrint('[LocalMedia] Saved ${bytes.length} bytes → ${file.path}');
    return file.path;
  }

  /// Save a [File] to private storage (copies the file).
  ///
  /// Returns the absolute path of the saved copy.
  static Future<String> saveFileToPrivate(File srcFile, String fileName) async {
    final dir = await _mediaDir();
    final dest = File('${dir.path}/$fileName');
    await srcFile.copy(dest.path);
    debugPrint('[LocalMedia] Copied file → ${dest.path}');
    return dest.path;
  }

  /// Returns the full path for a file name inside private storage.
  static Future<String> getPrivateFilePath(String fileName) async {
    final dir = await _mediaDir();
    return '${dir.path}/$fileName';
  }

  /// Check if a private file exists.
  static Future<bool> fileExists(String filePath) async {
    return File(filePath).existsSync();
  }

  /// Delete a private file by its absolute path.
  static Future<void> deletePrivateFile(String filePath) async {
    try {
      final file = File(filePath);
      if (file.existsSync()) {
        await file.delete();
        debugPrint('[LocalMedia] Deleted: $filePath');
      }
    } catch (e) {
      debugPrint('[LocalMedia] deletePrivateFile error: $e');
    }
  }

  /// Download a private file to the device gallery (user-initiated).
  ///
  /// Requires storage permission on older Android versions.
  /// Returns `true` on success.
  static Future<bool> downloadToGallery(String filePath) async {
    // Request storage permission (needed for Android < 13).
    final status = await Permission.photos.request();
    if (!status.isGranted) {
      // Try legacy storage permission.
      final legacy = await Permission.storage.request();
      if (!legacy.isGranted) {
        debugPrint('[LocalMedia] Gallery save permission denied');
        return false;
      }
    }

    final file = File(filePath);
    if (!file.existsSync()) {
      debugPrint('[LocalMedia] File not found for gallery save: $filePath');
      return false;
    }

    final ext = filePath.split('.').last.toLowerCase();
    final isVideo = ['mp4', 'mov', 'avi', 'mkv', 'webm'].contains(ext);

    try {
      bool? result;
      if (isVideo) {
        result = await GallerySaver.saveVideo(filePath);
      } else {
        result = await GallerySaver.saveImage(filePath);
      }
      debugPrint('[LocalMedia] Gallery save result: $result');
      return result == true;
    } catch (e) {
      debugPrint('[LocalMedia] downloadToGallery error: $e');
      return false;
    }
  }
}
