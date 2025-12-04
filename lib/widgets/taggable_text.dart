import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';

class TaggableExpandableText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final void Function(String username)? onMentionTap;
  final void Function(String tag)? onHashtagTap;
  final int maxLines;
  final TextAlign textAlign;

  const TaggableExpandableText({
    super.key,
    required this.text,
    required this.style,
    this.onMentionTap,
    this.onHashtagTap,
    this.maxLines = 3,
    this.textAlign = TextAlign.start,
  });

  @override
  State<TaggableExpandableText> createState() => _TaggableExpandableTextState();
}

class _TaggableExpandableTextState extends State<TaggableExpandableText> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final span = TextSpan(text: widget.text, style: widget.style);
        final tp = TextPainter(
          text: span,
          maxLines: widget.maxLines,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: constraints.maxWidth);
        final overflow = tp.didExceedMaxLines;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text.rich(
              TextSpan(
                children: buildTaggableSpans(
                  widget.text,
                  widget.style,
                  widget.onMentionTap,
                  widget.onHashtagTap,
                ),
              ),
              textAlign: widget.textAlign,
              maxLines: _expanded ? null : widget.maxLines,
              overflow: _expanded ? TextOverflow.visible : TextOverflow.ellipsis,
            ),
            if (overflow)
              GestureDetector(
                onTap: () {
                  setState(() => _expanded = !_expanded);
                },
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    _expanded ? 'See less' : 'See more',
                    style: TextStyle(
                      color: const Color(0xFF1DA1F2),
                      fontSize: (widget.style.fontSize ?? 16) * 0.85,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

List<InlineSpan> buildTaggableSpans(
  String text,
  TextStyle baseStyle,
  void Function(String username)? onMentionTap,
  void Function(String tag)? onHashtagTap,
) {
  final spans = <InlineSpan>[];
  final regex = RegExp(r'([@#][A-Za-z0-9_]+)');
  int start = 0;

  for (final match in regex.allMatches(text)) {
    if (match.start > start) {
      spans.add(TextSpan(text: text.substring(start, match.start), style: baseStyle));
    }
    final token = match.group(0)!;
    if (token.startsWith('@')) {
      spans.add(
        TextSpan(
          text: token,
          style: baseStyle.copyWith(
            color: const Color(0xFF1DA1F2),
            fontWeight: FontWeight.w600,
          ),
          recognizer: onMentionTap == null
              ? null
              : (TapGestureRecognizer()..onTap = () => onMentionTap(token)),
        ),
      );
    } else if (token.startsWith('#')) {
      spans.add(
        TextSpan(
          text: token,
          style: baseStyle.copyWith(
            color: const Color(0xFF1DA1F2),
            fontWeight: FontWeight.w600,
          ),
          recognizer: onHashtagTap == null
              ? null
              : (TapGestureRecognizer()..onTap = () => onHashtagTap(token)),
        ),
      );
    }
    start = match.end;
  }

  if (start < text.length) {
    spans.add(TextSpan(text: text.substring(start), style: baseStyle));
  }

  return spans;
}
