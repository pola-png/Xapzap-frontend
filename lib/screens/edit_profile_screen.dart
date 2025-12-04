import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../services/appwrite_service.dart';
import '../services/storage_service.dart';
import '../services/avatar_cache.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _usernameController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _websiteController = TextEditingController();
  final _phoneController = TextEditingController();
  final _dobController = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  XFile? _selectedImage;
  XFile? _selectedCover;
  String? _avatarUrl;
  String? _coverUrl;
  bool _hasChanges = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) {
        setState(() => _loading = false);
        return;
      }
      final prof = await AppwriteService.getProfileByUserId(user.$id);
      final userMeta = await AppwriteService.getUserMetaByUserId(user.$id);
      final data = prof?.data ?? <String, dynamic>{};
      final meta = userMeta?.data ?? <String, dynamic>{};

      _usernameController.text = (data['username'] as String?) ??
          (meta['username'] as String?) ??
          '';
      _displayNameController.text =
          (data['displayName'] as String?)?.trim().isNotEmpty == true
              ? data['displayName'] as String
              : ((meta['username'] as String?) ?? user.name);
      _bioController.text = (data['bio'] as String?) ?? '';
      _websiteController.text = (data['website'] as String?) ?? '';
      _phoneController.text = (data['phone'] as String?) ?? '';
      _dobController.text = (data['dateOfBirth'] as String?) ?? '';
      _avatarUrl = await _resolveAvatarUrl(user.$id, data['avatarUrl'] as String?);
      _coverUrl = await _resolveCoverUrl(data['coverUrl'] as String?);
    } catch (_) {
      // Ignore load errors; user can still edit.
    } finally {
      if (mounted) {
        setState(() {
          _hasChanges = false;
          _loading = false;
        });
      }
    }
  }

  Future<String?> _resolveAvatarUrl(String userId, String? raw) async {
    // Prefer the raw path/url if present.
    if (raw != null && raw.isNotEmpty) {
      try {
        final signed = await WasabiService.getSignedUrl(raw);
        await AvatarCache.setForUserId(userId, signed);
        return signed;
      } catch (_) {
        return raw;
      }
    }
    // Fallback to cache.
    final cached = AvatarCache.getForUserId(userId);
    if (cached != null) return cached;
    return null;
  }

  Future<String?> _resolveCoverUrl(String? raw) async {
    if (raw == null || raw.isEmpty) return null;
    try {
      final signed = await WasabiService.getSignedUrl(raw);
      return signed;
    } catch (_) {
      return raw;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: theme.colorScheme.surface,
        elevation: 1,
        leadingWidth: 80,
        leading: TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Cancel',
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        centerTitle: true,
        title: Text(
          'Edit Profile',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
        actions: [
          TextButton(
            onPressed: _hasChanges ? _saveProfile : null,
            child: Text(
              'Done',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _hasChanges
                    ? const Color(0xFF29ABE2)
                    : theme.colorScheme.onSurface.withOpacity(0.4),
              ),
            ),
          ),
        ],
      ),
      body: _buildForm(theme),
    );
  }

  Widget _buildForm(ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildProfilePicture(theme),
        const SizedBox(height: 16),
        _buildBannerPreview(theme),
        const SizedBox(height: 32),
        _buildField(
          theme,
          '@Username',
          _usernameController,
          required: true,
        ),
        const SizedBox(height: 16),
        _buildField(theme, 'Display Name', _displayNameController),
        const SizedBox(height: 16),
        _buildBioField(theme),
        const SizedBox(height: 16),
        _buildField(theme, 'Website', _websiteController, required: false),
        const SizedBox(height: 16),
        _buildField(
          theme,
          'Phone',
          _phoneController,
          required: false,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 16),
        _buildField(
          theme,
          'Date of birth (YYYY-MM-DD)',
          _dobController,
          required: false,
          keyboardType: TextInputType.datetime,
        ),
      ],
    );
  }

  Widget _buildProfilePicture(ThemeData theme) {
    return Column(
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.primary,
            image: _selectedImage != null
                ? DecorationImage(
                    image: FileImage(File(_selectedImage!.path)),
                    fit: BoxFit.cover,
                  )
                : (_avatarUrl != null
                    ? DecorationImage(
                        image: NetworkImage(_avatarUrl!),
                        fit: BoxFit.cover,
                      )
                    : null),
          ),
          child: _selectedImage == null && _avatarUrl == null
              ? const Icon(Icons.person, color: Colors.white, size: 48)
              : null,
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _changePhoto,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: const [
              Icon(
                Icons.camera_alt_outlined,
                size: 16,
                color: Color(0xFF29ABE2),
              ),
              SizedBox(width: 6),
              Text(
                'Change Photo',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: Color(0xFF29ABE2),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBannerPreview(ThemeData theme) {
    final borderRadius = BorderRadius.circular(16);
    Widget? imageChild;
    if (_selectedCover != null) {
      imageChild = ClipRRect(
        borderRadius: borderRadius,
        child: Image.file(
          File(_selectedCover!.path),
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    } else if (_coverUrl != null && _coverUrl!.isNotEmpty) {
      imageChild = ClipRRect(
        borderRadius: borderRadius,
        child: Image.network(
          _coverUrl!,
          height: 140,
          width: double.infinity,
          fit: BoxFit.cover,
        ),
      );
    }

    return GestureDetector(
      onTap: _changeBanner,
      child: Container(
        height: 140,
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: borderRadius,
          border: Border.all(color: theme.dividerColor),
        ),
        child: Stack(
          children: [
            if (imageChild != null)
              Positioned.fill(child: imageChild)
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.image_outlined,
                        size: 32, color: theme.colorScheme.onSurfaceVariant),
                    const SizedBox(height: 6),
                    Text(
                      'Add banner',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            Positioned(
              right: 12,
              bottom: 12,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.55),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.camera_alt_outlined,
                        size: 14, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'Change banner',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
    ThemeData theme,
    String label,
    TextEditingController controller, {
    bool required = true,
    TextInputType? keyboardType,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: required ? 'Required' : 'Optional',
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide(color: Color(0xFF29ABE2)),
            ),
          ),
          onChanged: (value) => setState(() => _hasChanges = true),
        ),
      ],
    );
  }

  Widget _buildBioField(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Bio',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: theme.colorScheme.onSurface,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: _bioController,
          maxLines: 4,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: theme.dividerColor),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(8)),
              borderSide: BorderSide(color: Color(0xFF29ABE2)),
            ),
            alignLabelWithHint: true,
          ),
          onChanged: (value) => setState(() => _hasChanges = true),
        ),
      ],
    );
  }

  Future<void> _changePhoto() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image =
                    await _picker.pickImage(source: ImageSource.camera);
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                    _hasChanges = true;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image =
                    await _picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  setState(() {
                    _selectedImage = image;
                    _hasChanges = true;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _changeBanner() async {
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: const Text('Take Photo'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image =
                    await _picker.pickImage(source: ImageSource.camera);
                if (image != null) {
                  setState(() {
                    _selectedCover = image;
                    _hasChanges = true;
                  });
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () async {
                Navigator.pop(context);
                final XFile? image =
                    await _picker.pickImage(source: ImageSource.gallery);
                if (image != null) {
                  setState(() {
                    _selectedCover = image;
                    _hasChanges = true;
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveProfile() async {
    try {
      final user = await AppwriteService.getCurrentUser();
      if (user == null) return;

      final rawUsername = _usernameController.text.trim();
      if (rawUsername.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username is required')),
        );
        return;
      }
      // Ensure username uniqueness (except for current user).
      final existingProfile =
          await AppwriteService.getProfileByUsername(rawUsername);
      if (existingProfile != null && existingProfile.$id != user.$id) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Username already taken')),
        );
        return;
      }

      // Normalize and validate website (Appwrite `url` type).
      String website = _websiteController.text.trim();
      if (website.isNotEmpty &&
          !website.startsWith('http://') &&
          !website.startsWith('https://')) {
        website = 'https://$website';
      }
      if (website.isNotEmpty) {
        final uri = Uri.tryParse(website);
        if (uri == null || uri.host.isEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Website must be a valid URL')),
          );
          return;
        }
      }

      // Normalize date of birth to ISO for datetime column.
      final dobRaw = _dobController.text.trim();
      String? dobIso;
      if (dobRaw.isNotEmpty) {
        final parsed = DateTime.tryParse(dobRaw);
        if (parsed == null) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Date of birth must be YYYY-MM-DD')),
          );
          return;
        }
        dobIso = parsed.toIso8601String();
      }

      String? avatarUrl;
      String? coverUrl;
      if (_selectedImage != null) {
        avatarUrl =
            await WasabiService.uploadProfileImage(_selectedImage!, user.$id);
      }
      if (_selectedCover != null) {
        coverUrl =
            await WasabiService.uploadProfileCover(_selectedCover!, user.$id);
      }

      await AppwriteService.updateUserProfile(user.$id, {
        'username': rawUsername,
        'displayName': _displayNameController.text.trim(),
        'bio': _bioController.text.trim(),
        if (website.isNotEmpty) 'website': website,
        'phone': _phoneController.text.trim(),
        if (dobIso != null) 'dateOfBirth': dobIso,
        if (avatarUrl != null) 'avatarUrl': avatarUrl,
        if (coverUrl != null) 'coverUrl': coverUrl,
      });

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Profile updated successfully!'),
          backgroundColor: Color(0xFF10B981),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating profile: $e'),
          backgroundColor: const Color(0xFFEF4444),
        ),
      );
    }
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    _websiteController.dispose();
    _phoneController.dispose();
    _dobController.dispose();
    super.dispose();
  }
}
