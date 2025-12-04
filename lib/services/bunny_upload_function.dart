import 'dart:convert';
import 'dart:typed_data';

import 'package:appwrite/appwrite.dart';

import 'appwrite_service.dart';

/// Helper to call the Bunny upload Appwrite Function from the client.
class BunnyUploadFunction {
  /// Replace with your actual function ID from the Appwrite console.
  static const String functionId = 'bunny-upload-function-id';

  static Future<String?> uploadBytes(Uint8List bytes, String objectPath) async {
    final client = AppwriteService.account.client;
    final functions = Functions(client);

    final execution = await functions.createExecution(
      functionId: functionId,
      body: jsonEncode({
        'path': objectPath,
        'fileBase64': base64Encode(bytes),
      }),
    );

    if (execution.responseBody.isEmpty) return null;
    final payload = jsonDecode(execution.responseBody) as Map<String, dynamic>;
    return payload['url'] as String?;
  }
}
