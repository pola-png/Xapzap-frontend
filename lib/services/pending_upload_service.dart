import 'dart:async';
import 'dart:io';

import 'package:appwrite/appwrite.dart' show ID;
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:video_thumbnail/video_thumbnail.dart';

import '../models/upload_type.dart';
import 'appwrite_service.dart';
import 'storage_service.dart';

class PendingUpload {
  PendingUpload({
    required this.id,
    required this.title,
    required this.request,
  });

  final String id;
  final String title;
  final PostUploadRequest request;
  double progress = 0.0;
  String status = 'Queued';
  bool completed = false;
  bool failed = false;
  String? error;
  int attempt = 0;
}

class PostUploadRequest {
  PostUploadRequest({
    required this.type,
    required this.content,
    required this.title,
    required this.mediaPaths,
    this.videoPath,
    this.thumbnailPath,
    this.cleanupPaths = const <String>[],
    this.textBgColor,
  });

  final UploadType type;
  final String content;
  final String title;
  final List<String> mediaPaths;
  final String? videoPath;
  final String? thumbnailPath;
  final List<String> cleanupPaths;
  final int? textBgColor;
}

class PendingUploadService {
  static final ValueNotifier<List<PendingUpload>> uploads =
      ValueNotifier<List<PendingUpload>>([]);
  static final Map<String, PostUploadRequest> _requests = {};

  static String enqueuePostUpload(PostUploadRequest request) {
    final upload = PendingUpload(
      id: ID.unique(),
      title: switch (request.type) {
        UploadType.video => 'Uploading video',
        UploadType.reel => 'Uploading reel',
        UploadType.news => 'Publishing article',
        _ => 'Uploading post',
      },
      request: request,
    );
    _requests[upload.id] = request;
    _addUpload(upload);
    _processPostUpload(upload, request);
    return upload.id;
  }

  static void _addUpload(PendingUpload upload) {
    uploads.value = [...uploads.value, upload];
  }

  static void _notify() {
    uploads.value = List<PendingUpload>.from(uploads.value);
  }

  static Future<void> retry(String uploadId) async {
    final uploadIndex = uploads.value.indexWhere((u) => u.id == uploadId);
    if (uploadIndex == -1) return;
    final request = _requests[uploadId];
    if (request == null) return;
    final upload = uploads.value[uploadIndex];
    upload.failed = false;
    upload.error = null;
    upload.progress = 0.0;
    upload.completed = false;
    upload.status = 'Retrying...';
    _notify();
    await _processPostUpload(upload, request);
  }

  static Future<void> _processPostUpload(
      PendingUpload upload, PostUploadRequest request) async {
    const int maxAttempts = 3;
    for (int i = 0; i < maxAttempts; i++) {
      upload.attempt = i + 1;
      upload.failed = false;
      upload.error = null;
      try {
        upload.status = i == 0 ? 'Preparing media' : 'Retrying (${upload.attempt}/$maxAttempts)';
        upload.progress = 0.05;
        _notify();
        final user = await AppwriteService.getCurrentUser();
        if (user == null) {
          throw Exception('Login required');
        }

      String? avatarUrl;
      try {
        final profile = await AppwriteService.getProfileByUserId(user.$id);
        avatarUrl = profile?.data['avatarUrl'] as String?;
      } catch (_) {}

        final List<String> uploadedMedia = [];
        String? thumbnailUrl;
        if (request.type == UploadType.video || request.type == UploadType.reel) {
          if (request.videoPath != null) {
            upload.status = 'Uploading video';
            upload.progress = 0.2;
            _notify();
            final file = File(request.videoPath!);
            if (!file.existsSync()) {
              throw Exception('Video file missing at ${file.path}');
            }
            final ext = p.extension(file.path);
            final key =
                'videos/${user.$id}/${ID.unique()}${ext.isNotEmpty ? ext : '.mp4'}';
            final storedPath = await WasabiService.uploadFileAtPath(file, key);
            uploadedMedia.add(storedPath);
          } else {
            throw Exception('Missing video file');
          }

          if (request.type == UploadType.video &&
              request.thumbnailPath != null &&
              request.thumbnailPath!.isNotEmpty) {
            upload.status = 'Uploading thumbnail';
            upload.progress = 0.35;
            _notify();
            final thumbFile = File(request.thumbnailPath!);
            final ext = p.extension(thumbFile.path);
            final key =
                'videos/${user.$id}/thumb_${ID.unique()}${ext.isNotEmpty ? ext : '.png'}';
            final storedThumb =
                await WasabiService.uploadFileAtPath(thumbFile, key);
            thumbnailUrl = storedThumb;
          } else {
            upload.status = 'Generating thumbnail';
            upload.progress = 0.35;
            _notify();
            try {
              final thumbPath = await VideoThumbnail.thumbnailFile(
                video: request.videoPath!,
                imageFormat: ImageFormat.PNG,
                maxHeight: 480,
                quality: 75,
              );
              if (thumbPath != null) {
                final thumbFile = File(thumbPath);
                if (!thumbFile.existsSync()) {
                  throw Exception('Generated thumbnail file missing');
                }
                final ext = p.extension(thumbFile.path);
                final key =
                    'videos/${user.$id}/thumb_${ID.unique()}${ext.isNotEmpty ? ext : '.png'}';
                final storedThumb =
                    await WasabiService.uploadFileAtPath(thumbFile, key);
                thumbnailUrl = storedThumb;
              }
            } catch (_) {
              // If thumbnail generation fails, continue without blocking upload.
              thumbnailUrl = null;
            }
          }
        } else if (request.mediaPaths.isNotEmpty) {
          upload.status = 'Uploading media';
          upload.progress = 0.2;
          _notify();
          for (final path in request.mediaPaths) {
            final file = File(path);
            final ext = p.extension(file.path);
            final key =
                'posts/${user.$id}/media_${DateTime.now().millisecondsSinceEpoch}$ext';
            final storedPath = await WasabiService.uploadFileAtPath(file, key);
            uploadedMedia.add(storedPath);
          }
        }

        upload.status = 'Publishing post';
        upload.progress = 0.8;
        _notify();

        String? postType;
        switch (request.type) {
          case UploadType.standard:
            postType = null;
            break;
          case UploadType.video:
            postType = 'video';
            break;
          case UploadType.reel:
            postType = 'reel';
            break;
          case UploadType.news:
            postType = 'news';
            break;
        }

        final data = <String, dynamic>{
          'userId': user.$id,
          'username': user.name,
          if (avatarUrl != null && avatarUrl.isNotEmpty) 'userAvatar': avatarUrl,
          'content': request.content,
          if (request.textBgColor != null) 'textBgColor': request.textBgColor,
          'likes': 0,
          'comments': 0,
          'reposts': 0,
          'impressions': 0,
          'createdAt': DateTime.now().toIso8601String(),
          'mediaUrls': uploadedMedia,
          if (postType != null) 'postType': postType,
          if (request.type == UploadType.video) 'title': request.title.trim(),
          if (postType == 'video' || postType == 'reel') 'thumbnailUrl': thumbnailUrl,
        };

        await AppwriteService.createPost(data);

        upload.status = 'Completed';
        upload.progress = 1.0;
        upload.completed = true;
        _notify();
        // Cleanup temp files
        for (final path in request.cleanupPaths) {
          try {
            final f = File(path);
            if (await f.exists()) {
              await f.delete();
            }
          } catch (_) {}
        }
        return;
      } catch (e) {
        upload.failed = i + 1 >= maxAttempts;
        upload.error = e.toString();
        upload.status = upload.failed ? 'Failed: ${e.toString()}' : 'Retrying...';
        _notify();
        if (upload.failed) return;
        await Future.delayed(const Duration(seconds: 2));
      }
    }
  }
}
