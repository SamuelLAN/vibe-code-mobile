import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/attachment.dart';
import '../models/message.dart';
import '../services/audio_player_service.dart';

/// 自定义 Markdown 元素类型
enum CustomBlockType {
  thinking,
  functionCall,
  functionResult,
  insight,
  edge,
}

/// 解析自定义代码块类型
CustomBlockType? _parseCustomBlockType(String language) {
  switch (language.toLowerCase()) {
    case 'thinking':
      return CustomBlockType.thinking;
    case 'function_call':
      return CustomBlockType.functionCall;
    case 'function_result':
      return CustomBlockType.functionResult;
    case 'insight':
      return CustomBlockType.insight;
    case 'edge':
      return CustomBlockType.edge;
    default:
      return null;
  }
}

/// 解析 JSON 字符串
Map<String, dynamic>? _tryParseJson(String text) {
  try {
    return jsonDecode(text) as Map<String, dynamic>;
  } catch (_) {
    final match = RegExp(r'\{[\s\S]*\}').firstMatch(text);
    if (match != null) {
      try {
        return jsonDecode(match.group(0)!) as Map<String, dynamic>;
      } catch (_) {}
    }
    return null;
  }
}

/// 格式化 JSON 用于显示
String _formatJsonDisplay(Map<String, dynamic>? data) {
  if (data == null) return '';
  return const JsonEncoder.withIndent('  ').convert(data);
}

class MessageBubble extends StatelessWidget {
  const MessageBubble({
    super.key,
    required this.message,
    this.onCopy,
    this.onRetry,
    this.audioPlayer,
  });

  final Message message;
  final VoidCallback? onCopy;
  final VoidCallback? onRetry;
  final AudioPlayerService? audioPlayer;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isUser
        ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
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
            if (message.attachments.isNotEmpty) 
              _AttachmentRow(
                attachments: message.attachments, 
                audioPlayer: audioPlayer,
              ),
            if (message.attachments.isNotEmpty) const SizedBox(height: 8),
            if (isUser)
              Text(message.content, style: Theme.of(context).textTheme.bodyMedium)
            else
              _EnhancedMarkdown(
                content: message.content.isEmpty && message.isStreaming ? '...' : message.content,
                isDark: isDark,
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

/// 增强型 Markdown 渲染组件
class _EnhancedMarkdown extends StatelessWidget {
  const _EnhancedMarkdown({
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return MarkdownBody(
      data: content,
      selectable: true,
      styleSheet: _buildStyleSheet(context),
      onTapLink: (text, href, title) => _handleLinkTap(context, href),
      builders: _buildBuilders(context),
    );
  }

  void _handleLinkTap(BuildContext context, String? href) async {
    if (href == null) return;
    final uri = Uri.parse(href);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  MarkdownStyleSheet _buildStyleSheet(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    return MarkdownStyleSheet(
      h1: textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.bold),
      h2: textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
      h3: textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
      h4: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
      h5: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      h6: textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
      p: textTheme.bodyMedium,
      pPadding: const EdgeInsets.symmetric(vertical: 4),
      strong: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
      em: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
      code: TextStyle(
        fontFamily: 'monospace',
        fontSize: 13,
        backgroundColor: isDark ? Colors.grey[800] : Colors.grey[200],
        color: colorScheme.primary,
      ),
      codeblockDecoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      codeblockPadding: const EdgeInsets.all(12),
      blockquote: textTheme.bodyMedium?.copyWith(
        fontStyle: FontStyle.italic,
        color: colorScheme.onSurface.withValues(alpha: 0.8),
      ),
      blockquoteDecoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: colorScheme.primary, width: 4),
        ),
        color: colorScheme.primary.withValues(alpha: 0.08),
      ),
      blockquotePadding: const EdgeInsets.only(left: 16, top: 8, bottom: 8),
      listBullet: textTheme.bodyMedium?.copyWith(color: colorScheme.primary),
      listIndent: 24,
      tableHead: textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
      tableBody: textTheme.bodyMedium,
      tableBorder: TableBorder.all(
        color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        width: 1,
      ),
      tableColumnWidth: const IntrinsicColumnWidth(),
      tableCellsPadding: const EdgeInsets.all(8),
      a: textTheme.bodyMedium?.copyWith(
        color: colorScheme.primary,
        decoration: TextDecoration.underline,
      ),
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: isDark ? Colors.grey[700]! : Colors.grey[300]!, width: 1),
        ),
      ),
    );
  }

  Map<String, MarkdownElementBuilder> _buildBuilders(BuildContext context) {
    return {
      'pre': _PreCodeBlockBuilder(isDark: isDark),
      'code': _InlineCodeBuilder(isDark: isDark),
    };
  }
}

/// 代码块构建器 - 支持自定义块类型
class _PreCodeBlockBuilder extends MarkdownElementBuilder {
  _PreCodeBlockBuilder({required this.isDark});

  final bool isDark;

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    final codeContent = element.textContent;
    
    // 尝试从 element 获取 language 信息
    String? language;
    if (element.attributes.containsKey('class')) {
      final className = element.attributes['class'] ?? '';
      if (className.contains('language-')) {
        language = className.replaceFirst('language-', '').trim();
      }
    }

    final customType = _parseCustomBlockType(language ?? '');
    if (customType != null) {
      return _buildCustomBlock(customType, codeContent);
    }

    // 标准代码块
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[100],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: SelectableText(
          codeContent,
          style: TextStyle(
            fontFamily: 'monospace',
            fontSize: 13,
            color: isDark ? Colors.grey[300] : Colors.grey[800],
          ),
        ),
      ),
    );
  }

  Widget _buildCustomBlock(CustomBlockType type, String content) {
    switch (type) {
      case CustomBlockType.thinking:
        return _buildThinkingBlock(content);
      case CustomBlockType.functionCall:
        return _buildFunctionCallBlock(content);
      case CustomBlockType.functionResult:
        return _buildFunctionResultBlock(content);
      case CustomBlockType.insight:
        return _buildInsightBlock(content);
      case CustomBlockType.edge:
        return _buildEdgeBlock(content);
    }
  }

  Widget _buildThinkingBlock(String content) {
    final parsed = _tryParseJson(content);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blue.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology, size: 16, color: Colors.blue),
              const SizedBox(width: 6),
              Text(
                'Thinking',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.blue[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (parsed != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _formatJsonDisplay(parsed),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            )
          else
            SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFunctionCallBlock(String content) {
    final parsed = _tryParseJson(content);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.purple.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.code, size: 16, color: Colors.purple),
              const SizedBox(width: 6),
              Text(
                'Function Call',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.purple[700],
                ),
              ),
              if (parsed?['name'] != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    parsed!['name'].toString(),
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 11,
                      color: Colors.purple[700],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          if (parsed?['arguments'] != null)
            _buildArguments(parsed!['arguments'])
          else if (parsed != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _formatJsonDisplay(parsed),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            )
          else
            SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildArguments(dynamic args) {
    String argsText;
    if (args is String) {
      argsText = args;
    } else if (args is Map) {
      argsText = const JsonEncoder.withIndent('  ').convert(args);
    } else {
      argsText = args.toString();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.grey[50],
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        argsText,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 11,
          color: isDark ? Colors.grey[300] : Colors.grey[800],
        ),
      ),
    );
  }

  Widget _buildFunctionResultBlock(String content) {
    final parsed = _tryParseJson(content);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle, size: 16, color: Colors.green),
              const SizedBox(width: 6),
              Text(
                'Function Result',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.green[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (parsed != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _formatJsonDisplay(parsed),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            )
          else
            SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInsightBlock(String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lightbulb, size: 16, color: Colors.amber),
              const SizedBox(width: 6),
              Text(
                'Insight',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.amber[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(
            content,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey[300] : Colors.grey[800],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEdgeBlock(String content) {
    final parsed = _tryParseJson(content);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.teal.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.teal.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link, size: 16, color: Colors.teal),
              const SizedBox(width: 6),
              Text(
                'Edge',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: Colors.teal[700],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (parsed != null)
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[900] : Colors.grey[50],
                borderRadius: BorderRadius.circular(6),
              ),
              child: SelectableText(
                _formatJsonDisplay(parsed),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  color: isDark ? Colors.grey[300] : Colors.grey[800],
                ),
              ),
            )
          else
            SelectableText(
              content,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                color: isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
        ],
      ),
    );
  }
}

/// 内联代码构建器
class _InlineCodeBuilder extends MarkdownElementBuilder {
  _InlineCodeBuilder({required this.isDark});

  final bool isDark;

  @override
  Widget? visitElementAfter(element, TextStyle? preferredStyle) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[200],
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        element.textContent,
        style: TextStyle(
          fontFamily: 'monospace',
          fontSize: 13,
          color: isDark ? Colors.grey[300] : Colors.grey[800],
        ),
      ),
    );
  }
}

class _AttachmentRow extends StatelessWidget {
  const _AttachmentRow({required this.attachments, this.audioPlayer});

  final List<Attachment> attachments;
  final AudioPlayerService? audioPlayer;

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
            return _VoiceMessageWidget(
              attachment: attachment,
              audioPlayer: audioPlayer,
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
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
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

/// 语音消息组件，显示转录状态和播放按钮
class _VoiceMessageWidget extends StatefulWidget {
  const _VoiceMessageWidget({required this.attachment, this.audioPlayer});

  final Attachment attachment;
  final AudioPlayerService? audioPlayer;

  @override
  State<_VoiceMessageWidget> createState() => _VoiceMessageWidgetState();
}

class _VoiceMessageWidgetState extends State<_VoiceMessageWidget> {
  @override
  void initState() {
    super.initState();
    widget.audioPlayer?.addListener(_onPlayerStateChanged);
  }

  @override
  void dispose() {
    widget.audioPlayer?.removeListener(_onPlayerStateChanged);
    super.dispose();
  }

  void _onPlayerStateChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  bool get _isCurrentFilePlaying =>
      widget.audioPlayer?.currentFilePath == widget.attachment.path &&
      widget.audioPlayer?.isPlaying == true;

  @override
  Widget build(BuildContext context) {
    final audioPlayer = widget.audioPlayer;
    final isThisFilePlaying = audioPlayer?.currentFilePath == widget.attachment.path;
    final isPlaying = isThisFilePlaying && audioPlayer?.isPlaying == true;

    return GestureDetector(
      onTap: audioPlayer != null
          ? () => audioPlayer.play(widget.attachment.path)
          : null,
      child: Container(
        width: 180,
        height: 48,
        decoration: BoxDecoration(
          color: _getBackgroundColor(context, isPlaying),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const SizedBox(width: 8),
            _buildPlayButton(context, isPlaying, audioPlayer != null),
            const SizedBox(width: 8),
            Expanded(
              child: _buildContent(context, isPlaying),
            ),
            if (isThisFilePlaying && audioPlayer != null) ...[
              _buildProgressIndicator(context),
              const SizedBox(width: 4),
            ],
            const SizedBox(width: 4),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayButton(BuildContext context, bool isPlaying, bool hasPlayer) {
    if (!hasPlayer) {
      return _buildStatusIcon(context);
    }
    
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
      child: Icon(
        isPlaying ? Icons.pause : Icons.play_arrow,
        color: Colors.white,
        size: 20,
      ),
    );
  }

  Widget _buildProgressIndicator(BuildContext context) {
    final player = widget.audioPlayer;
    if (player == null) return const SizedBox.shrink();

    final duration = player.duration;
    final position = player.position;

    if (duration == null || duration.inMilliseconds == 0) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    final progress = position.inMilliseconds / duration.inMilliseconds;
    
    return SizedBox(
      width: 40,
      height: 4,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Color _getBackgroundColor(BuildContext context, bool isPlaying) {
    if (isPlaying) {
      return Theme.of(context).colorScheme.primary.withValues(alpha: 0.2);
    }
    switch (widget.attachment.transcriptionStatus) {
      case TranscriptionStatus.loading:
        return Theme.of(context).colorScheme.primary.withValues(alpha: 0.2);
      case TranscriptionStatus.completed:
        return Colors.green.withValues(alpha: 0.15);
      case TranscriptionStatus.error:
        return Colors.red.withValues(alpha: 0.15);
      default:
        return Theme.of(context).colorScheme.primary.withValues(alpha: 0.1);
    }
  }

  Widget _buildContent(BuildContext context, bool isPlaying) {
    final textStyle = TextStyle(
      fontSize: 12,
      color: Theme.of(context).colorScheme.onSurface,
    );

    // 如果正在播放，显示播放状态
    if (isPlaying) {
      return Row(
        children: [
          const Icon(Icons.volume_up, size: 16),
          const SizedBox(width: 4),
          Text('播放中...', style: textStyle),
        ],
      );
    }

    switch (widget.attachment.transcriptionStatus) {
      case TranscriptionStatus.loading:
        return Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 6),
            Text('转录中...', style: textStyle),
          ],
        );
      case TranscriptionStatus.completed:
        return Row(
          children: [
            const Icon(Icons.check_circle, size: 16, color: Colors.green),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                widget.attachment.transcribedText ?? '转录完成',
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      case TranscriptionStatus.error:
        return Row(
          children: [
            const Icon(Icons.error, size: 16, color: Colors.red),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                '转录失败',
                style: textStyle.copyWith(color: Colors.red),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        );
      default:
        // 没有播放器时显示原始状态，有播放器时显示可点击提示
        if (widget.audioPlayer != null) {
          return Row(
            children: [
              const Icon(Icons.volume_up, size: 16),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  '点击播放',
                  style: textStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          );
        }
        return Text('语音消息', style: textStyle);
    }
  }

  // 保留原有的状态图标方法用于没有播放器的场景
  Widget _buildStatusIcon(BuildContext context) {
    switch (widget.attachment.transcriptionStatus) {
      case TranscriptionStatus.loading:
        return SizedBox(
          width: 16,
          height: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        );
      case TranscriptionStatus.completed:
        return const Icon(Icons.check_circle, size: 20, color: Colors.green);
      case TranscriptionStatus.error:
        return const Icon(Icons.error, size: 20, color: Colors.red);
      default:
        return const Icon(Icons.volume_up, size: 20);
    }
  }
}
