import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/attachment.dart';
import '../models/message.dart';

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onRetry,
  });

  final Message message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final background = isUser
        ? Theme.of(context).colorScheme.primary.withOpacity(0.12)
        : Theme.of(context).colorScheme.surface;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (message.attachments.isNotEmpty) _AttachmentRow(attachments: message.attachments),
            if (message.attachments.isNotEmpty) const SizedBox(height: 8),
            if (isUser)
              Text(message.content, style: Theme.of(context).textTheme.bodyMedium)
            else
              MarkdownBody(
                data: message.content.isEmpty && message.isStreaming ? '...' : message.content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  codeblockDecoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surfaceVariant,
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onTapLink: (text, href, title) async {
                  if (href == null) return;
                  final uri = Uri.parse(href);
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                  }
                },
                builders: {
                  'pre': _CodeBlockBuilder(isDark: Theme.of(context).brightness == Brightness.dark),
                },
              ),
            if (!isUser) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  IconButton(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy',
                  ),
                  IconButton(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh, size: 18),
                    tooltip: 'Retry',
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachments});

  final List<Attachment> attachments;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 72,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: attachments.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final attachment = attachments[index];
          if (attachment.type == AttachmentType.voice) {
            return Container(
              width: 120,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  const Icon(Icons.volume_up, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('Voice message', style: TextStyle(fontSize: 12)),
                  ),
                  const Text("0:02", style: TextStyle(fontSize: 10)),
                  const SizedBox(width: 12),
                ],
              ),
            );
          }
          return GestureDetector(
            onTap: attachment.type == AttachmentType.image
                ? () {
                    showDialog<void>(
                      context: context,
                      builder: (context) => Dialog(
                        child: InteractiveViewer(
                          child: Image.file(File(attachment.path)),
                        ),
                      ),
                    );
                  }
                : null,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: attachment.type == AttachmentType.image
                  ? Image.file(File(attachment.path), width: 72, height: 72, fit: BoxFit.cover)
                  : Container(
                      width: 72,
                      height: 72,
                      color: Theme.of(context).colorScheme.surfaceVariant,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.insert_drive_file),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              attachment.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ),
                        ],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

class _CodeBlockBuilder extends MarkdownElementBuilder {
  _CodeBlockBuilder({required this.isDark});

  final bool isDark;

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: SelectableText(
        element.textContent,
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
      ),
    );
  }
}
