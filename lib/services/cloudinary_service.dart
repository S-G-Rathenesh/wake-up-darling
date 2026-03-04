import 'dart:io';
import 'package:cloudinary_public/cloudinary_public.dart';

/// Cloudinary upload service with preset: wakeupdarling_preset
class CloudinaryService {
  final cloudinary = CloudinaryPublic(
    'dwsvou0hk',
    'wakeupdarling_preset',
    cache: false,
  );

  /// Upload a file to Cloudinary and return the secure URL.
  /// Throws exception if upload fails.
  Future<String> uploadFile(File file) async {
    final response = await cloudinary.uploadFile(
      CloudinaryFile.fromFile(
        file.path,
        resourceType: CloudinaryResourceType.Auto,
      ),
    );

    if (response.secureUrl.isEmpty) {
      throw Exception('Upload failed: empty URL');
    }

    return response.secureUrl;
  }
}
