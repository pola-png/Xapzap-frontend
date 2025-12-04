import 'package:flutter/material.dart';

import '../services/pending_upload_service.dart';

class PendingUploadsScreen extends StatelessWidget {
  final String? initialUploadId;

  const PendingUploadsScreen({super.key, this.initialUploadId});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending uploads'),
      ),
      body: ValueListenableBuilder<List<PendingUpload>>(
        valueListenable: PendingUploadService.uploads,
        builder: (context, uploads, _) {
          if (uploads.isEmpty) {
            return const Center(
              child: Text('No pending uploads'),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: uploads.length,
            separatorBuilder: (context, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final upload = uploads[index];
              return _buildCard(theme, upload);
            },
          );
        },
      ),
    );
  }

  Widget _buildCard(ThemeData theme, PendingUpload upload) {
    final statusColor = upload.failed
        ? Colors.red
        : upload.completed
            ? Colors.green
            : theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  upload.title,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              Text(
                upload.completed
                    ? 'Done'
                    : upload.failed
                        ? 'Failed'
                        : '${(upload.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: upload.completed || upload.failed ? 1.0 : upload.progress,
            backgroundColor: theme.dividerColor.withOpacity(0.4),
            color: statusColor,
          ),
          const SizedBox(height: 8),
          Text(
            upload.failed && upload.error != null ? upload.error! : upload.status,
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
