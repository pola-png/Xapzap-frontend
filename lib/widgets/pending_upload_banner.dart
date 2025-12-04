import 'package:flutter/material.dart';

import '../services/pending_upload_service.dart';

class PendingUploadBanner extends StatelessWidget {
  const PendingUploadBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<PendingUpload>>(
      valueListenable: PendingUploadService.uploads,
      builder: (context, uploads, _) {
        final active = uploads.where((u) => !u.completed).toList();
        if (active.isEmpty) return const SizedBox.shrink();
        final upload = active.first;
        final statusColor = upload.failed
            ? Colors.red
            : theme.colorScheme.primary;
        return Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.dividerColor),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(upload.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    LinearProgressIndicator(
                      value: upload.completed ? 1.0 : upload.progress,
                      color: statusColor,
                      backgroundColor: theme.dividerColor.withOpacity(0.4),
                    ),
                    const SizedBox(height: 4),
                    Text(upload.status, style: theme.textTheme.bodySmall),
                    if (upload.error != null && upload.error!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          upload.error!,
                          style: theme.textTheme.bodySmall?.copyWith(color: Colors.red),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (upload.failed)
                TextButton(
                  onPressed: () async {
                    await PendingUploadService.retry(upload.id);
                  },
                  child: const Text('Retry'),
                )
              else
                Text(
                  '${(upload.progress * 100).clamp(0, 100).toStringAsFixed(0)}%',
                  style: TextStyle(color: statusColor, fontWeight: FontWeight.w600),
                ),
            ],
          ),
        );
      },
    );
  }
}
