import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/story.dart';

class StoryAvatar extends StatelessWidget {
  final Story story;
  final bool isCurrentUser;

  const StoryAvatar({super.key, required this.story, this.isCurrentUser = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final textColor = theme.textTheme.bodySmall?.color ?? theme.colorScheme.onBackground;
    final innerBgColor = isDark ? theme.colorScheme.background : Colors.white;
    final innerBorderColor = theme.colorScheme.background;

    return Container(
      width: 72,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: isCurrentUser
                      ? null
                      : story.isViewed
                          ? null
                          : const LinearGradient(
                              colors: [
                                Color(0xFFFEDA75),
                                Color(0xFFF58529),
                                Color(0xFFDD2A7B),
                                Color(0xFF8134AF),
                                Color(0xFF515BD4)
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                  color: story.isViewed ? Colors.black : null,
                ),
              ),
              Container(
                width: 62,
                height: 62,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: innerBgColor,
                  border: Border.all(color: innerBorderColor, width: 2),
                ),
                child: _buildAvatarImage(story.imageUrl),
              ),
              if (isCurrentUser)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: const Color(0xFF1DA1F2),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 2),
                    ),
                    child: const Icon(Icons.add, color: Colors.white, size: 16),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            isCurrentUser ? 'Your Story' : story.username,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: textColor),
          ),
        ],
      ),
    );
  }
}

Widget _buildAvatarImage(String url) {
  if (url.isEmpty) {
    return const CircleAvatar(
      radius: 34,
      backgroundColor: Colors.transparent,
      child: Icon(Icons.person, color: Colors.grey),
    );
  }
  return CircleAvatar(
    radius: 34,
    backgroundColor: Colors.transparent,
    backgroundImage: CachedNetworkImageProvider(url),
  );
}

