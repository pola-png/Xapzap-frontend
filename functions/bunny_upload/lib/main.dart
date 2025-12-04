import 'dart:convert';
import 'dart:io';

/// Dart entrypoint for the `bunny-upload` Appwrite function.
///
/// Expects a JSON body:
/// {
///   "path": "profiles/<userId>/avatar_123.png",
///   "fileBase64": "<base64 bytes>"
/// }
///
/// Uses environment variables set in the Appwrite function:
/// - BUNNY_STORAGE_ZONE
/// - BUNNY_STORAGE_KEY
/// - BUNNY_STORAGE_HOST
/// - BUNNY_CDN_BASE_URL
Future<void> main(List<String> args) async {
  final server = await HttpServer.bind(InternetAddress.anyIPv4, 3000);
  await for (final HttpRequest request in server) {
    if (request.method != 'POST') {
      request.response
        ..statusCode = HttpStatus.methodNotAllowed
        ..write('Only POST allowed')
        ..close();
      continue;
    }

    try {
      final body = await utf8.decoder.bind(request).join();
      final data = jsonDecode(body) as Map<String, dynamic>;

      final objectPath = data['path'] as String?;
      final fileBase64 = data['fileBase64'] as String?;

      if (objectPath == null || fileBase64 == null) {
        request.response
          ..statusCode = HttpStatus.badRequest
          ..write(jsonEncode({'error': 'path and fileBase64 are required'}))
          ..close();
        continue;
      }

      final zone = Platform.environment['BUNNY_STORAGE_ZONE'];
      final key = Platform.environment['BUNNY_STORAGE_KEY'];
      final host =
          Platform.environment['BUNNY_STORAGE_HOST'] ?? 'storage.bunnycdn.com';
      final cdnBase = Platform.environment['BUNNY_CDN_BASE_URL'];

      if (zone == null || key == null || cdnBase == null) {
        request.response
          ..statusCode = HttpStatus.internalServerError
          ..write(jsonEncode({'error': 'Bunny configuration missing'}))
          ..close();
        continue;
      }

      final bytes = base64Decode(fileBase64);
      final uri = Uri.https(host, '$zone/$objectPath');

      final httpClient = HttpClient();
      final httpReq = await httpClient.putUrl(uri);
      httpReq.headers.set('AccessKey', key);
      httpReq.headers.set('Content-Type', 'application/octet-stream');
      httpReq.add(bytes);
      final httpRes = await httpReq.close();

      if (httpRes.statusCode < 200 || httpRes.statusCode >= 300) {
        final errorBody = await utf8.decoder.bind(httpRes).join();
        request.response
          ..statusCode = HttpStatus.badGateway
          ..write(
            jsonEncode({
              'error': 'Bunny upload failed',
              'status': httpRes.statusCode,
              'body': errorBody,
            }),
          )
          ..close();
        continue;
      }

      final cleanBase =
          cdnBase.endsWith('/') ? cdnBase.substring(0, cdnBase.length - 1) : cdnBase;
      final cleanPath =
          objectPath.startsWith('/') ? objectPath.substring(1) : objectPath;
      final cdnUrl = '$cleanBase/$cleanPath';

      request.response
        ..statusCode = HttpStatus.ok
        ..write(jsonEncode({'path': objectPath, 'url': cdnUrl}))
        ..close();
    } catch (e) {
      request.response
        ..statusCode = HttpStatus.internalServerError
        ..write(jsonEncode({'error': 'Upload failed', 'detail': '$e'}))
        ..close();
    }
  }
}

