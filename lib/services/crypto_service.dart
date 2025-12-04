import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'appwrite_service.dart';

/// Handles end-to-end encryption for chats.
/// - Generates a per-device identity key pair (X25519).
/// - Publishes the public key into the user's profile (publicKey).
/// - Derives a per-chat symmetric key via ECDH + HKDF.
/// - Encrypts/decrypts message content using AES-GCM.
class CryptoService {
  static final _storage = const FlutterSecureStorage();
  static const _identityPrivateKeyKey = 'identity_private_key';

  static final _x25519 = X25519();
  static final _kdf = Hkdf(
    hmac: Hmac.sha256(),
    outputLength: 32,
  );
  static final _cipher = AesGcm.with256bits();

  /// Ensure we have an identity key pair and that our public key is
  /// stored in the user's profile (publicKey column).
  static Future<KeyPair?> ensureIdentityKeysAndPublish() async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return null;

    // Load or generate key pair.
    SimpleKeyPair keyPair;
    final storedPriv = await _storage.read(key: _identityPrivateKeyKey);
    if (storedPriv != null) {
      final privBytes = base64Decode(storedPriv);
      keyPair = await _x25519.newKeyPairFromSeed(privBytes);
    } else {
      // Generate a random seed and derive the key pair from it so we
      // can reconstruct the same keypair later from the stored seed.
      final secretKey = await _cipher.newSecretKey();
      final seed = await secretKey.extractBytes();
      keyPair = await _x25519.newKeyPairFromSeed(seed);
      await _storage.write(
        key: _identityPrivateKeyKey,
        value: base64Encode(seed),
      );
    }

    // Publish public key to profile if not set.
    try {
      final pub = await keyPair.extractPublicKey();
      final pubB64 = base64Encode(pub.bytes);
      final profile = await AppwriteService.getProfileByUserId(me.$id);
      final existing = profile?.data['publicKey'] as String?;
      if (existing == null || existing.isEmpty) {
        await AppwriteService.updateUserProfile(me.$id, {'publicKey': pubB64});
      }
    } catch (_) {}

    return keyPair;
  }

  /// Derive or load a symmetric key for a chat using ECDH with the
  /// partner's public key.
  static Future<SecretKey?> getChatKey({
    required String chatId,
    required String partnerUserId,
  }) async {
    final me = await AppwriteService.getCurrentUser();
    if (me == null) return null;

    // Cache per-chat key in secure storage to avoid recomputing.
    final cacheKey = 'chat_key_$chatId';
    final cached = await _storage.read(key: cacheKey);
    if (cached != null) {
      return SecretKey(base64Decode(cached));
    }

    final myKeys = await ensureIdentityKeysAndPublish();
    if (myKeys == null) return null;

    // Load partner public key from profile.
    final partnerProfile =
        await AppwriteService.getProfileByUserId(partnerUserId);
    final partnerPubB64 = partnerProfile?.data['publicKey'] as String?;
    if (partnerPubB64 == null || partnerPubB64.isEmpty) {
      // Partner has not published a key yet; cannot do E2EE.
      return null;
    }
    final partnerPub = SimplePublicKey(
      base64Decode(partnerPubB64),
      type: KeyPairType.x25519,
    );

    final shared = await _x25519.sharedSecretKey(
      keyPair: myKeys,
      remotePublicKey: partnerPub,
    );
    final salt = utf8.encode(chatId);
    final derived = await _kdf.deriveKey(
      secretKey: shared,
      nonce: salt,
      info: utf8.encode('xapzap-chat'),
    );

    final raw = await derived.extractBytes();
    await _storage.write(key: cacheKey, value: base64Encode(raw));
    return derived;
  }

  static Future<Map<String, String>?> encryptMessage({
    required String chatId,
    required String partnerUserId,
    required String plaintext,
  }) async {
    final key = await getChatKey(chatId: chatId, partnerUserId: partnerUserId);
    if (key == null) {
      // Fallback: no key available.
      return null;
    }
    final nonce = _cipher.newNonce();
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: key,
      nonce: nonce,
    );
    return {
      'ciphertext': base64Encode(secretBox.cipherText),
      'nonce': base64Encode(secretBox.nonce),
    };
  }

  static Future<String?> decryptMessage({
    required String chatId,
    required String partnerUserId,
    required String ciphertextB64,
    required String nonceB64,
  }) async {
    final key = await getChatKey(chatId: chatId, partnerUserId: partnerUserId);
    if (key == null) return null;

    try {
      final cipherBytes = base64Decode(ciphertextB64);
      final nonce = base64Decode(nonceB64);
      final box = SecretBox(cipherBytes, nonce: nonce, mac: Mac.empty);
      final clearBytes = await _cipher.decrypt(box, secretKey: key);
      return utf8.decode(clearBytes);
    } catch (_) {
      return null;
    }
  }
}
