import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

/// Storage helper backed by Bunny.net.
///
/// We keep the legacy name [WasabiService] to avoid changing all call sites,
/// but under the hood this now uses Bunny Storage + CDN.
class WasabiService {
  static String? _storageZone;
  static String? _storageKey;
  static String? _storageHost;
  static String? _cdnBaseUrl;
  static bool _initialized = false;

  static Future<void> initialize() async {
    _storageZone = dotenv.env['BUNNY_STORAGE_ZONE'];
    _storageKey = dotenv.env['BUNNY_STORAGE_KEY'];
    _storageHost = dotenv.env['BUNNY_STORAGE_HOST'] ?? 'storage.bunnycdn.com';
    _cdnBaseUrl = dotenv.env['BUNNY_CDN_BASE_URL'];

    if (_storageZone == null ||
        _storageKey == null ||
        _storageHost == null ||
        _cdnBaseUrl == null) {
      throw StateError('Bunny configuration is missing in .env');
    }
    _initialized = true;
  }

  static Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  static Uri _buildStorageUri(String path) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.https(_storageHost!, '$_storageZone/$cleanPath');
  }

  static String _buildCdnUrl(String path) {
    final base = _cdnBaseUrl!.endsWith('/')
        ? _cdnBaseUrl!.substring(0, _cdnBaseUrl!.length - 1)
        : _cdnBaseUrl!;
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return '$base/$cleanPath';
  }

  /// Bunny Storage does not require signing for simple public CDN access.
  /// We keep this for compatibility: if [key] is already a full URL, return it;
  /// otherwise return the CDN URL for the stored path.
  static Future<String> getSignedUrl(String key, {int expires = 3600}) async {
    await _ensureInitialized();
    if (key.startsWith('http://') || key.startsWith('https://')) {
      return key;
    }
    return _buildCdnUrl(key);
  }

  static Future<String> _uploadFile(File file, String objectPath) async {
    await _ensureInitialized();
    final uri = _buildStorageUri(objectPath);
    final bytes = await file.readAsBytes();
    final response = await http.put(
      uri,
      headers: {
        'AccessKey': _storageKey!,
        'Content-Type': 'application/octet-stream',
      },
      body: bytes,
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return objectPath;
    }
    throw Exception(
      'Bunny upload failed (${response.statusCode}): ${response.body}',
    );
  }

  /// Public helper for uploading a single file to an explicit [objectPath].
  /// Returns the stored path (which can be turned into a CDN URL via [getSignedUrl]).
  static Future<String> uploadFileAtPath(File file, String objectPath) {
    return _uploadFile(file, objectPath);
  }

  static Future<List<String>> uploadMultiplePostMedia(
      List<XFile> files, String userId) async {
    final List<String> urls = [];
    for (final file in files) {
      final ext = p.extension(file.path);
      final key =
          'posts/$userId/media_${DateTime.now().millisecondsSinceEpoch}$ext';
      final storedPath = await _uploadFile(File(file.path), key);
      urls.add(storedPath);
    }
    return urls;
  }

  static Future<String?> uploadVoiceComment(String path, String userId) async {
    try {
      final ext = p.extension(path);
      final key =
          'comments/$userId/voice_${DateTime.now().millisecondsSinceEpoch}$ext';
      final storedPath = await _uploadFile(File(path), key);
      return storedPath;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfileImage(XFile file, String userId) async {
    try {
      final ext = p.extension(file.path);
      final key =
          'profiles/$userId/avatar_${DateTime.now().millisecondsSinceEpoch}$ext';
      final storedPath = await _uploadFile(File(file.path), key);
      return storedPath;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> uploadProfileCover(XFile file, String userId) async {
    try {
      final ext = p.extension(file.path);
      final key =
          'profiles/$userId/cover_${DateTime.now().millisecondsSinceEpoch}$ext';
      final storedPath = await _uploadFile(File(file.path), key);
      return storedPath;
    } catch (_) {
      return null;
    }
  }

  static Future<void> deleteFile(String path) async {
    await _ensureInitialized();
    String key = path;
    if (key.startsWith('http://') || key.startsWith('https://')) {
      final uri = Uri.parse(key);
      final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
      if (segments.isNotEmpty && segments.first == _storageZone) {
        key = segments.skip(1).join('/');
      } else {
        key = segments.join('/');
      }
    }
    if (key.startsWith('/')) {
      key = key.substring(1);
    }
    if (key.isEmpty) return;
    final uri = _buildStorageUri(key);
    final response = await http.delete(
      uri,
      headers: {'AccessKey': _storageKey!},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception(
          'Bunny delete failed (${response.statusCode}): ${response.body}');
    }
  }
}
