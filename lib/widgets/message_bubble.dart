import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

import '../models/attachment.dart';
import '../models/message.dart';
import '../models/stream_element.dart';
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
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
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
              Text(message.content,
                  style: Theme.of(context).textTheme.bodyMedium)
            else
              _AssistantMessageContent(
                message: message,
                isDark: isDark,
              ),
            if (onCopy != null || (!isUser && onRetry != null)) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  if (onCopy != null)
                    IconButton(
                      onPressed: onCopy,
                      icon: const Icon(Icons.copy, size: 18),
                      tooltip: 'Copy',
                    ),
                  if (!isUser && onRetry != null)
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

class _AssistantMessageContent extends StatelessWidget {
  const _AssistantMessageContent({
    required this.message,
    required this.isDark,
  });

  final Message message;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    if (message.streamElements.isEmpty) {
      return _EnhancedMarkdown(
        content: message.content.isEmpty && message.isStreaming
            ? '...'
            : message.content,
        isDark: isDark,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in _buildRenderItems(message.streamElements))
          _buildRenderItem(item),
      ],
    );
  }

  List<_StreamRenderItem> _buildRenderItems(List<StreamElement> elements) {
    final items = <_StreamRenderItem>[];
    final functionItemIndexById = <String, int>{};

    for (final element in elements) {
      final isFunction = element.type == StreamElementType.functionCall ||
          element.type == StreamElementType.functionResult;
      final functionId = element.metadata?['functionId']?.toString();
      final canPair = isFunction && functionId != null && functionId.isNotEmpty;

      if (!canPair) {
        items.add(_StreamRenderItem(element: element));
        continue;
      }

      final existingIndex = functionItemIndexById[functionId];
      if (existingIndex == null) {
        items.add(_StreamRenderItem(
          element: element,
          functionId: functionId,
          functionCall:
              element.type == StreamElementType.functionCall ? element : null,
          functionResult:
              element.type == StreamElementType.functionResult ? element : null,
        ));
        functionItemIndexById[functionId] = items.length - 1;
        continue;
      }

      final existing = items[existingIndex];
      if (element.type == StreamElementType.functionCall) {
        existing.functionCall = element;
      } else if (element.type == StreamElementType.functionResult) {
        existing.functionResult = element;
      }

      // 默认 result 覆盖 call；若还没有 result，则显示 call
      existing.element =
          existing.functionResult ?? existing.functionCall ?? element;
    }

    return items;
  }

  Widget _buildRenderItem(_StreamRenderItem item) {
    final pairedFunction = item.functionId != null &&
        (item.functionCall != null || item.functionResult != null);
    if (pairedFunction) {
      return _FunctionTimelineBlock(
        item: item,
        isDark: isDark,
      );
    }
    return _buildElement(item.element);
  }

  Widget _buildElement(StreamElement element) {
    final codeFence = switch (element.type) {
      StreamElementType.text => null,
      StreamElementType.functionCall => 'function_call',
      StreamElementType.functionResult => 'function_result',
      StreamElementType.thinking => 'thinking',
      StreamElementType.insightStart => 'insight_start',
      StreamElementType.insightEnd => 'insight_end',
      StreamElementType.edge => 'edge',
    };

    if (element.type == StreamElementType.thinking) {
      return _ThinkingToolBlock(
        content: element.content,
        isComplete: element.isComplete,
        isDark: isDark,
      );
    }

    if (codeFence == null) {
      return _EnhancedMarkdown(
        content: element.content,
        isDark: isDark,
      );
    }

    return _EnhancedMarkdown(
      content: '```$codeFence\n${element.content}\n```',
      isDark: isDark,
    );
  }
}

class _StreamRenderItem {
  _StreamRenderItem({
    required this.element,
    this.functionId,
    this.functionCall,
    this.functionResult,
  });

  StreamElement element;
  final String? functionId;
  StreamElement? functionCall;
  StreamElement? functionResult;
}

class _FunctionTimelineBlock extends StatefulWidget {
  const _FunctionTimelineBlock({
    required this.item,
    required this.isDark,
  });

  final _StreamRenderItem item;
  final bool isDark;

  @override
  State<_FunctionTimelineBlock> createState() => _FunctionTimelineBlockState();
}

class _FunctionTimelineBlockState extends State<_FunctionTimelineBlock> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final summary = _buildSummary(widget.item);
    final borderColor = Colors.blueGrey.withValues(alpha: 0.35);
    final bgColor =
        widget.isDark ? Colors.blueGrey[900]! : Colors.blueGrey[50]!;
    final titleColor = widget.isDark ? Colors.grey[200] : Colors.blueGrey[800];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: subColor,
                  ),
                  const SizedBox(width: 4),
                  Icon(summary.icon, size: 15, color: subColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      summary.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            if (summary.subtitle != null && summary.subtitle!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
                child: Text(
                  summary.subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: subColor,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: _buildExpandedContent(widget.item, widget.isDark),
            ),
          ],
        ],
      ),
    );
  }

  _FunctionSummary _buildSummary(_StreamRenderItem item) {
    final callParsed = item.functionCall != null
        ? _tryParseJson(item.functionCall!.content)
        : null;
    final resultParsed = item.functionResult != null
        ? _tryParseJson(item.functionResult!.content)
        : null;
    final functionName = (item.functionResult?.metadata?['functionName'] ??
            item.functionCall?.metadata?['functionName'] ??
            'function')
        .toString();

    if (functionName == 'gsearch') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final query = args is Map ? args['query']?.toString() : null;
      int? count;
      final response = resultParsed?['response'];
      if (response is Map && response['organic'] is List) {
        count = (response['organic'] as List).length;
      }
      return _FunctionSummary(
        icon: Icons.search,
        title: query == null || query.isEmpty ? 'Search' : 'Search $query',
        subtitle: count == null ? null : '$count results',
      );
    }

    if (functionName == 'navigate_to') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final url = args is Map ? args['url']?.toString() : null;
      final lookingFor = args is Map ? args['looking_for']?.toString() : null;
      return _FunctionSummary(
        icon: Icons.open_in_browser,
        title: (url == null || url.isEmpty)
            ? 'Navigate to page'
            : 'Navigate to $url',
        subtitle: lookingFor == null || lookingFor.isEmpty
            ? null
            : 'Looking for: $lookingFor',
      );
    }

    if (functionName == 'restore_memory') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final lookingFor = args is Map ? args['looking_for']?.toString() : null;
      return _FunctionSummary(
        icon: Icons.memory_outlined,
        title: 'Restore memory',
        subtitle: lookingFor == null || lookingFor.isEmpty
            ? null
            : 'Looking for: $lookingFor',
      );
    }

    if (functionName == 'read_files') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final argPaths = _extractReadFilePaths(args);
      final response = resultParsed?['response'];
      final resultFilesCount = _extractReadFilesCount(response);
      final effectiveCount = resultFilesCount ?? argPaths.length;
      final firstName = argPaths.isNotEmpty ? p.basename(argPaths.first) : null;

      return _FunctionSummary(
        icon: Icons.description_outlined,
        title: effectiveCount <= 1 && firstName != null
            ? 'Read $firstName'
            : effectiveCount > 0
                ? 'Explored $effectiveCount files'
                : 'Read files',
        subtitle: effectiveCount > 1 && argPaths.isNotEmpty
            ? argPaths.take(2).map((e) => p.basename(e)).join(' · ')
            : null,
      );
    }

    if (functionName == 'search_files') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final userIntent = args is Map ? args['user_intent']?.toString() : null;
      final response = resultParsed?['response'];
      final files = _extractSearchFilesItems(response);
      return _FunctionSummary(
        icon: Icons.manage_search,
        title: userIntent == null || userIntent.isEmpty
            ? 'Search files'
            : 'Search files $userIntent',
        subtitle: files.isEmpty ? null : 'Found ${files.length} relevant files',
      );
    }

    if (functionName == 'pass_coding_mind_map') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final intent = args is Map ? args['coding_intent']?.toString() : null;
      final roots = _extractCodingMindMapRoots(args);
      return _FunctionSummary(
        icon: Icons.account_tree_outlined,
        title: 'Coding mind map',
        subtitle: (intent != null && intent.isNotEmpty)
            ? intent
            : (roots.isNotEmpty ? roots.first.title : null),
      );
    }

    if (functionName == 'apply_diff') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final response = resultParsed?['response'];
      final path = args is Map ? args['file_path']?.toString() : null;
      final stats = _extractApplyDiffStats(args, response);
      final basename =
          (path != null && path.isNotEmpty) ? p.basename(path) : null;
      return _FunctionSummary(
        icon: Icons.auto_fix_high,
        title: basename == null ? 'Apply diff' : basename,
        subtitle: _formatApplyDiffSummaryLine(stats, response),
      );
    }

    if (functionName == 'check_linter') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final paths = _extractLinterRequestPaths(args);
      final results = _extractLinterResults(resultParsed?['response']);
      final firstName = paths.isNotEmpty ? p.basename(paths.first) : null;
      return _FunctionSummary(
        icon: Icons.rule,
        title: (paths.length <= 1 && firstName != null)
            ? 'Lint $firstName'
            : (paths.isNotEmpty
                ? 'Lint ${paths.length} files'
                : 'Check linter'),
        subtitle: results.isEmpty ? null : _formatLinterSummary(results),
      );
    }

    if (functionName == 'write_file') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final response = resultParsed?['response'];
      final path = (response is Map ? response['path'] : null)?.toString() ??
          (args is Map ? args['file_path']?.toString() : null);
      final size = response is Map && response['size'] is num
          ? (response['size'] as num).toInt()
          : null;
      final lines = response is Map && response['lines'] is num
          ? (response['lines'] as num).toInt()
          : null;
      final parts = <String>[
        if (lines != null) '$lines lines',
        if (size != null) '${_formatBytes(size)}',
      ];
      return _FunctionSummary(
        icon: Icons.edit_note,
        title: path == null || path.isEmpty ? 'Write file' : p.basename(path),
        subtitle: parts.isEmpty ? null : parts.join(' · '),
      );
    }

    if (functionName == 'list_dir') {
      final args = (callParsed?['args'] ?? callParsed?['arguments']);
      final dirPath = args is Map ? args['dir_path']?.toString() : null;
      final response = resultParsed?['response'];
      final summary = _extractListDirSummary(response);
      return _FunctionSummary(
        icon: Icons.folder_open,
        title: dirPath == null || dirPath.isEmpty
            ? 'List directory'
            : 'List ${p.basename(dirPath.endsWith('/') ? dirPath.substring(0, dirPath.length - 1) : dirPath)}',
        subtitle: summary ?? (dirPath?.isNotEmpty == true ? dirPath : null),
      );
    }

    return _FunctionSummary(
      icon: Icons.extension,
      title: functionName,
    );
  }

  Widget _buildExpandedContent(_StreamRenderItem item, bool isDark) {
    final functionName = (item.functionResult?.metadata?['functionName'] ??
            item.functionCall?.metadata?['functionName'])
        ?.toString();
    final callParsed = item.functionCall != null
        ? _tryParseJson(item.functionCall!.content)
        : null;
    final resultParsed = item.functionResult != null
        ? _tryParseJson(item.functionResult!.content)
        : null;

    if (functionName == 'gsearch') {
      final body = _buildGSearchExpandedBody(resultParsed, isDark);
      if (body != null) return body;
    }

    if (functionName == 'navigate_to') {
      final body = _buildNavigateExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'restore_memory') {
      final body =
          _buildRestoreMemoryExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'read_files') {
      final body =
          _buildReadFilesExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'search_files') {
      final body =
          _buildSearchFilesExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'pass_coding_mind_map') {
      final body = _buildPassCodingMindMapExpandedBody(callParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'apply_diff') {
      final body =
          _buildApplyDiffExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'check_linter') {
      final body =
          _buildCheckLinterExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'write_file') {
      final body =
          _buildWriteFileExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }
    if (functionName == 'list_dir') {
      final body = _buildListDirExpandedBody(callParsed, resultParsed, isDark);
      if (body != null) return body;
    }

    final preferred = item.functionResult ?? item.functionCall ?? item.element;
    final codeFence = switch (preferred.type) {
      StreamElementType.functionCall => 'function_call',
      StreamElementType.functionResult => 'function_result',
      StreamElementType.text => null,
      StreamElementType.thinking => 'thinking',
      StreamElementType.insightStart => 'insight_start',
      StreamElementType.insightEnd => 'insight_end',
      StreamElementType.edge => 'edge',
    };

    if (codeFence == null) {
      return _EnhancedMarkdown(content: preferred.content, isDark: isDark);
    }

    return _EnhancedMarkdown(
      content: '```$codeFence\n${preferred.content}\n```',
      isDark: isDark,
    );
  }

  Widget? _buildGSearchExpandedBody(
      Map<String, dynamic>? resultParsed, bool isDark) {
    final response = resultParsed?['response'];
    if (response is! Map) return null;
    final organic = response['organic'];
    if (organic is! List) return null;

    final items = organic
        .whereType<Map>()
        .map((item) => _SearchResultItem(
              title: item['title']?.toString() ?? '',
              link: item['link']?.toString() ?? '',
              snippet: item['snippet']?.toString(),
              date: item['date']?.toString(),
              source: _timelineHostFromUrl(item['link']?.toString()),
            ))
        .where((e) => e.title.isNotEmpty)
        .toList();

    if (items.isEmpty) return null;

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.2) : Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: _SearchResultsListBody(items: items, isDark: isDark),
    );
  }

  Widget? _buildNavigateExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final response = resultParsed?['response'];
    String? responseText;
    if (response is String) {
      responseText = response;
    } else if (response is Map || response is List) {
      responseText = const JsonEncoder.withIndent('  ').convert(response);
    }

    // 如果还没有 result，回退显示 call 的 args
    if ((responseText == null || responseText.isEmpty) && callParsed != null) {
      final args = callParsed['args'] ?? callParsed['arguments'] ?? callParsed;
      responseText = const JsonEncoder.withIndent('  ').convert(args);
    }
    if (responseText == null || responseText.isEmpty) return null;

    final isError = responseText.toLowerCase().startsWith('error:');
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color:
              (isError ? Colors.red : Colors.blueGrey).withValues(alpha: 0.25),
        ),
      ),
      child: _EnhancedMarkdown(
        content: responseText,
        isDark: isDark,
      ),
    );
  }

  Widget? _buildRestoreMemoryExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final response = resultParsed?['response'];
    String? responseText;
    if (response is String) {
      responseText = response;
    } else if (response is Map || response is List) {
      responseText = const JsonEncoder.withIndent('  ').convert(response);
    }

    if ((responseText == null || responseText.isEmpty) && callParsed != null) {
      final args = callParsed['args'] ?? callParsed['arguments'] ?? callParsed;
      responseText = const JsonEncoder.withIndent('  ').convert(args);
    }
    if (responseText == null || responseText.isEmpty) return null;

    final lower = responseText.toLowerCase();
    final isWarning = lower.contains('no memory found');
    final isError = lower.startsWith('error:');
    final toneColor =
        isError ? Colors.red : (isWarning ? Colors.orange : Colors.blueGrey);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.25) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: toneColor.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError
                ? Icons.error_outline
                : (isWarning ? Icons.info_outline : Icons.memory_outlined),
            size: 16,
            color: toneColor,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _EnhancedMarkdown(
              content: responseText,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildReadFilesExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final response = resultParsed?['response'];
    final filesMap = response is Map ? response['files'] : null;

    final items = <_ReadFileSummaryItem>[];
    if (filesMap is Map) {
      filesMap.forEach((key, value) {
        final path = key.toString();
        final data = value is Map ? value : const {};
        items.add(
          _ReadFileSummaryItem(
            path: path,
            lines:
                (data['lines'] is num) ? (data['lines'] as num).toInt() : null,
            size: (data['size'] is num) ? (data['size'] as num).toInt() : null,
          ),
        );
      });
    }

    if (items.isEmpty) {
      final args = callParsed?['args'] ?? callParsed?['arguments'];
      final paths = _extractReadFilePaths(args);
      if (paths.isEmpty) return null;
      items.addAll(paths.map((e) => _ReadFileSummaryItem(path: e)));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.blueGrey.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            items.length == 1 ? 'Read file' : 'Explored ${items.length} files',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.blueGrey[700],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++) ...[
            _ReadFileSummaryRow(item: items[i], isDark: isDark),
            if (i != items.length - 1)
              Divider(
                height: 10,
                color: Colors.blueGrey.withValues(alpha: 0.18),
              ),
          ],
        ],
      ),
    );
  }

  Widget? _buildSearchFilesExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final response = resultParsed?['response'];
    final items = _extractSearchFilesItems(response);
    final graphText = response is Map
        ? response['file_relationship_graph']?.toString()
        : null;
    final found = response is Map ? response['found'] == true : false;

    final args = callParsed?['args'] ?? callParsed?['arguments'];
    final userIntent = args is Map ? args['user_intent']?.toString() : null;

    if (items.isEmpty && (graphText == null || graphText.isEmpty)) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (userIntent != null && userIntent.isNotEmpty)
            Text(
              userIntent,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[400] : Colors.blueGrey[600],
              ),
            ),
          if (items.isNotEmpty) ...[
            if (userIntent != null && userIntent.isNotEmpty)
              const SizedBox(height: 8),
            Text(
              found
                  ? 'Found ${items.length} relevant files'
                  : '${items.length} files',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[300] : Colors.blueGrey[700],
              ),
            ),
            const SizedBox(height: 8),
            _SearchFilesTreeList(items: items, isDark: isDark),
          ],
          if (graphText != null && graphText.isNotEmpty) ...[
            const SizedBox(height: 10),
            _SearchFilesGraphPreview(text: graphText, isDark: isDark),
          ],
        ],
      ),
    );
  }

  Widget? _buildPassCodingMindMapExpandedBody(
      Map<String, dynamic>? callParsed, bool isDark) {
    final args = callParsed?['args'] ?? callParsed?['arguments'];
    final roots = _extractCodingMindMapRoots(args);
    if (roots.isEmpty) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: _CodingMindMapTreeCard(
        roots: roots,
        isDark: isDark,
      ),
    );
  }

  Widget? _buildApplyDiffExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final args = callParsed?['args'] ?? callParsed?['arguments'];
    if (args is! Map) return null;
    final response = resultParsed?['response'];
    final path = args['file_path']?.toString() ?? '';
    final stats = _extractApplyDiffStats(args, response);
    final preview = _buildApplyDiffPreview(
      search: args['search']?.toString() ?? '',
      replace: args['replace']?.toString() ?? '',
    );
    final lineRanges = _extractApplyDiffLineRanges(response);
    final success = response is Map ? response['success'] == true : null;
    final message = response is Map ? response['message']?.toString() : null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  path.isEmpty ? 'apply_diff' : p.basename(path),
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.grey[200] : Colors.blueGrey[800],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              _DiffCountChip(label: '+${stats.added}', color: Colors.green),
              const SizedBox(width: 6),
              _DiffCountChip(label: '-${stats.removed}', color: Colors.red),
            ],
          ),
          if (path.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              path,
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.grey[400] : Colors.blueGrey[600],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                fontSize: 10.5,
                color: success == false
                    ? (isDark ? Colors.red[300] : Colors.red[700])
                    : (isDark ? Colors.grey[300] : Colors.blueGrey[700]),
              ),
            ),
          ],
          if (lineRanges.isNotEmpty) ...[
            const SizedBox(height: 6),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final r in lineRanges)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      'L${r.$1}-${r.$2}',
                      style: TextStyle(
                        fontSize: 10,
                        color: isDark ? Colors.grey[300] : Colors.blueGrey[700],
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (preview != null) ...[
            const SizedBox(height: 8),
            _ApplyDiffPreviewCard(
              preview: preview,
              isDark: isDark,
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildCheckLinterExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final args = callParsed?['args'] ?? callParsed?['arguments'];
    final requestedPaths = _extractLinterRequestPaths(args);
    final results = _extractLinterResults(resultParsed?['response']);

    final items = results.isNotEmpty
        ? results
        : requestedPaths
            .map((path) => _LinterFileResult(
                  path: path,
                  linter: null,
                  success: null,
                  fixed: null,
                  clean: null,
                  output: null,
                ))
            .toList();

    if (items.isEmpty) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            items.length == 1
                ? 'Linter check'
                : 'Linter checks (${items.length})',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.blueGrey[700],
            ),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < items.length; i++) ...[
            _LinterResultRow(item: items[i], isDark: isDark),
            if (i != items.length - 1)
              Divider(
                height: 10,
                color: Colors.blueGrey.withValues(alpha: 0.18),
              ),
          ],
        ],
      ),
    );
  }

  Widget? _buildWriteFileExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final args = callParsed?['args'] ?? callParsed?['arguments'];
    if (args is! Map) return null;
    final response = resultParsed?['response'];

    final path = (response is Map ? response['path'] : null)?.toString() ??
        args['file_path']?.toString() ??
        '';
    final message = response is Map ? response['message']?.toString() : null;
    final size = response is Map && response['size'] is num
        ? (response['size'] as num).toInt()
        : null;
    final lines = response is Map && response['lines'] is num
        ? (response['lines'] as num).toInt()
        : null;
    final success = response is Map ? response['success'] == true : null;
    final content = args['content']?.toString() ?? '';

    if (path.isEmpty && content.isEmpty && message == null) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                success == false
                    ? Icons.error_outline
                    : Icons.insert_drive_file_outlined,
                size: 16,
                color: success == false ? Colors.red : Colors.blueGrey,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  path.isEmpty ? 'write_file' : p.basename(path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.grey[200] : Colors.blueGrey[800],
                  ),
                ),
              ),
              if (lines != null)
                _LinterBadge(label: '$lines lines', color: Colors.blueGrey),
              if (lines != null && size != null) const SizedBox(width: 6),
              if (size != null)
                _LinterBadge(label: _formatBytes(size), color: Colors.blueGrey),
            ],
          ),
          if (path.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              path,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5,
                color: isDark ? Colors.grey[400] : Colors.blueGrey[600],
              ),
            ),
          ],
          if (message != null && message.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              message,
              style: TextStyle(
                fontSize: 10.5,
                color: success == false
                    ? (isDark ? Colors.red[300] : Colors.red[700])
                    : (isDark ? Colors.grey[300] : Colors.blueGrey[700]),
              ),
            ),
          ],
          if (content.isNotEmpty) ...[
            const SizedBox(height: 8),
            _WriteFileContentPreview(content: content, isDark: isDark),
          ],
        ],
      ),
    );
  }

  Widget? _buildListDirExpandedBody(Map<String, dynamic>? callParsed,
      Map<String, dynamic>? resultParsed, bool isDark) {
    final args = callParsed?['args'] ?? callParsed?['arguments'];
    final requestedDir = args is Map ? args['dir_path']?.toString() : null;
    final response = resultParsed?['response'];
    if (response is! Map) return null;

    final path = response['path']?.toString() ?? requestedDir ?? '';
    final tree = response['tree']?.toString() ?? '';
    final summaryMap = response['summary'];
    final summary = summaryMap is Map ? summaryMap : null;

    if (path.isEmpty && tree.isEmpty && summary == null) return null;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? Colors.black.withValues(alpha: 0.22) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.blueGrey.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (path.isNotEmpty)
            Row(
              children: [
                const Icon(Icons.folder_open, size: 14, color: Colors.blueGrey),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: isDark ? Colors.grey[300] : Colors.blueGrey[700],
                    ),
                  ),
                ),
              ],
            ),
          if (summary != null) ...[
            if (path.isNotEmpty) const SizedBox(height: 8),
            _ListDirSummaryChips(summary: summary, isDark: isDark),
          ],
          if (tree.isNotEmpty) ...[
            const SizedBox(height: 8),
            _ListDirTreePreview(tree: tree, isDark: isDark),
          ],
        ],
      ),
    );
  }

  List<String> _extractReadFilePaths(dynamic args) {
    if (args is! Map) return const [];
    final filePaths = args['file_paths'];
    if (filePaths is! List) return const [];
    return filePaths
        .map((e) => e.toString())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  int? _extractReadFilesCount(dynamic response) {
    if (response is! Map) return null;
    final files = response['files'];
    if (files is Map) return files.length;
    return null;
  }

  List<_SearchFilesItem> _extractSearchFilesItems(dynamic response) {
    if (response is! Map) return const [];
    final raw = response['all_relevant_paths_to_user_intent'];
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((entry) {
          return _SearchFilesItem(
            filePath: entry['file_path']?.toString() ?? '',
            whatToChange: entry['what_to_change']?.toString() ?? '',
          );
        })
        .where((item) => item.filePath.isNotEmpty)
        .toList();
  }

  List<_CodingMindMapNodeItem> _extractCodingMindMapRoots(dynamic args) {
    if (args is! Map) return const [];
    final rootRaw = args['mind_map_root'];
    if (rootRaw is! List) return const [];
    return rootRaw
        .map((e) => _parseCodingMindMapNode(e))
        .whereType<_CodingMindMapNodeItem>()
        .toList();
  }

  _CodingMindMapNodeItem? _parseCodingMindMapNode(dynamic raw) {
    if (raw is! Map) return null;
    final title =
        (raw['coding_topic'] ?? raw['topic'] ?? raw['id'])?.toString();
    if (title == null || title.isEmpty) return null;
    final subtitle = (raw['coding_intent'] ?? raw['reason'])?.toString();
    final path = raw['path']?.toString();
    final action = raw['action']?.toString();

    final childrenRaw = raw['children'];
    final children = childrenRaw is List
        ? childrenRaw
            .map((e) => _parseCodingMindMapNode(e))
            .whereType<_CodingMindMapNodeItem>()
            .toList()
        : <_CodingMindMapNodeItem>[];

    final affectedRaw = raw['affected_files'];
    final affectedChildren = affectedRaw is List
        ? affectedRaw.whereType<Map>().map((e) {
            return _CodingMindMapNodeItem(
              title: p.basename(e['path']?.toString() ?? 'file'),
              subtitle: e['reason']?.toString(),
              path: e['path']?.toString(),
              action: e['action']?.toString(),
              children: const [],
            );
          }).toList()
        : <_CodingMindMapNodeItem>[];

    return _CodingMindMapNodeItem(
      title: title,
      subtitle: subtitle,
      path: path,
      action: action,
      children: [...children, ...affectedChildren],
    );
  }

  _ApplyDiffStats _extractApplyDiffStats(dynamic args, dynamic response) {
    final search = args is Map ? (args['search']?.toString() ?? '') : '';
    final replace = args is Map ? (args['replace']?.toString() ?? '') : '';
    final preview = _buildApplyDiffPreview(search: search, replace: replace);
    if (preview != null) {
      return _ApplyDiffStats(
        added: preview.addedLines.length,
        removed: preview.removedLines.length,
      );
    }

    if (response is Map) {
      final changes = response['changes'];
      if (changes is Map) {
        final replaced = (changes['replaced'] is num)
            ? (changes['replaced'] as num).toInt()
            : 0;
        return _ApplyDiffStats(added: replaced, removed: replaced);
      }
    }
    return const _ApplyDiffStats(added: 0, removed: 0);
  }

  String? _formatApplyDiffSummaryLine(_ApplyDiffStats stats, dynamic response) {
    final parts = <String>[];
    parts.add('+${stats.added}');
    parts.add('-${stats.removed}');
    if (response is Map && response['success'] != null) {
      parts.add(response['success'] == true ? 'success' : 'failed');
    }
    return parts.join('  ');
  }

  List<(int, int)> _extractApplyDiffLineRanges(dynamic response) {
    if (response is! Map) return const [];
    final changes = response['changes'];
    if (changes is! Map) return const [];
    final raw = changes['line_ranges'];
    if (raw is! List) return const [];
    final ranges = <(int, int)>[];
    for (final item in raw) {
      if (item is List &&
          item.length >= 2 &&
          item[0] is num &&
          item[1] is num) {
        ranges.add(((item[0] as num).toInt(), (item[1] as num).toInt()));
      }
    }
    return ranges;
  }

  _ApplyDiffPreview? _buildApplyDiffPreview({
    required String search,
    required String replace,
  }) {
    if (search.isEmpty && replace.isEmpty) return null;
    final before = search.replaceAll('\r\n', '\n').split('\n');
    final after = replace.replaceAll('\r\n', '\n').split('\n');

    var prefix = 0;
    while (prefix < before.length &&
        prefix < after.length &&
        before[prefix] == after[prefix]) {
      prefix++;
    }

    var suffix = 0;
    while (suffix < before.length - prefix &&
        suffix < after.length - prefix &&
        before[before.length - 1 - suffix] ==
            after[after.length - 1 - suffix]) {
      suffix++;
    }

    final removed = before.sublist(prefix, before.length - suffix);
    final added = after.sublist(prefix, after.length - suffix);
    if (removed.isEmpty && added.isEmpty) return null;

    return _ApplyDiffPreview(
      removedLines: removed.take(12).toList(),
      addedLines: added.take(12).toList(),
    );
  }

  List<String> _extractLinterRequestPaths(dynamic args) {
    if (args is! Map) return const [];
    final raw = args['file_paths'];
    if (raw is String && raw.isNotEmpty) return [raw];
    if (raw is List) {
      return raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    }
    return const [];
  }

  List<_LinterFileResult> _extractLinterResults(dynamic response) {
    if (response is! Map) return const [];
    final rawResults = response['results'];
    if (rawResults is! Map) return const [];

    final items = <_LinterFileResult>[];
    rawResults.forEach((key, value) {
      final path = key.toString();
      final data = value is Map ? value : const {};
      items.add(_LinterFileResult(
        path: path,
        linter: data['linter']?.toString(),
        success: data['success'] is bool ? data['success'] as bool : null,
        fixed: data['fixed'] is bool ? data['fixed'] as bool : null,
        clean: data['clean'] is bool ? data['clean'] as bool : null,
        output: data['output']?.toString(),
      ));
    });
    return items;
  }

  String _formatLinterSummary(List<_LinterFileResult> results) {
    final successCount = results.where((e) => e.success == true).length;
    final cleanCount = results.where((e) => e.clean == true).length;
    final fixedCount = results.where((e) => e.fixed == true).length;
    return '$successCount/${results.length} success · $cleanCount clean · $fixedCount fixed';
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(1)}MB';
  }

  String? _extractListDirSummary(dynamic response) {
    if (response is! Map) return null;
    final summary = response['summary'];
    if (summary is! Map) return null;
    final totalFiles = summary['total_files'] is num
        ? (summary['total_files'] as num).toInt()
        : null;
    final totalDirs = summary['total_dirs'] is num
        ? (summary['total_dirs'] as num).toInt()
        : null;
    final sizeFormatted = summary['total_size_formatted']?.toString();
    final parts = <String>[
      if (totalFiles != null) '$totalFiles files',
      if (totalDirs != null) '$totalDirs dirs',
      if (sizeFormatted != null && sizeFormatted.isNotEmpty) sizeFormatted,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  String? _timelineHostFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return null;
    }
  }
}

class _FunctionSummary {
  const _FunctionSummary({
    required this.icon,
    required this.title,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
}

class _ReadFileSummaryItem {
  const _ReadFileSummaryItem({
    required this.path,
    this.lines,
    this.size,
  });

  final String path;
  final int? lines;
  final int? size;
}

class _ReadFileSummaryRow extends StatelessWidget {
  const _ReadFileSummaryRow({
    required this.item,
    required this.isDark,
  });

  final _ReadFileSummaryItem item;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.grey[200] : Colors.blueGrey[800];
    final metaColor = isDark ? Colors.grey[400] : Colors.blueGrey[600];
    final parts = <String>[
      if (item.lines != null) '${item.lines} lines',
      if (item.size != null) '${item.size} B',
    ];

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.chevron_right, size: 16, color: metaColor),
        const SizedBox(width: 2),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.basename(item.path),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: titleColor,
                ),
              ),
              Text(
                item.path,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: metaColor,
                ),
              ),
              if (parts.isNotEmpty)
                Text(
                  parts.join('  •  '),
                  style: TextStyle(
                    fontSize: 10.5,
                    color: metaColor,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SearchFilesItem {
  const _SearchFilesItem({
    required this.filePath,
    required this.whatToChange,
  });

  final String filePath;
  final String whatToChange;
}

class _SearchFilesTreeList extends StatelessWidget {
  const _SearchFilesTreeList({
    required this.items,
    required this.isDark,
  });

  final List<_SearchFilesItem> items;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.blueGrey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.08 : 0.12),
        ),
      ),
      padding: const EdgeInsets.all(8),
      child: Column(
        children: [
          for (var i = 0; i < items.length; i++) ...[
            _SearchFilesTreeRow(
              item: items[i],
              isDark: isDark,
              accentIndex: i,
            ),
            if (i != items.length - 1)
              Divider(
                height: 10,
                color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.1),
              ),
          ],
        ],
      ),
    );
  }
}

class _SearchFilesTreeRow extends StatefulWidget {
  const _SearchFilesTreeRow({
    required this.item,
    required this.isDark,
    required this.accentIndex,
  });

  final _SearchFilesItem item;
  final bool isDark;
  final int accentIndex;

  @override
  State<_SearchFilesTreeRow> createState() => _SearchFilesTreeRowState();
}

class _SearchFilesTreeRowState extends State<_SearchFilesTreeRow> {
  bool _open = false;

  static const _accents = <Color>[
    Color(0xFFF87171),
    Color(0xFFF59E0B),
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFF38BDF8),
    Color(0xFFF472B6),
  ];

  @override
  Widget build(BuildContext context) {
    final accent = _accents[widget.accentIndex % _accents.length];
    final titleColor = widget.isDark ? Colors.grey[200] : Colors.blueGrey[800];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 2.5,
                  height: 22,
                  margin: const EdgeInsets.only(top: 2, right: 8),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.basename(widget.item.filePath),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      Text(
                        widget.item.filePath,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10.5,
                          color: subColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: Colors.white
                        .withValues(alpha: widget.isDark ? 0.08 : 0.18),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 14,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: widget.isDark
                    ? Colors.black.withValues(alpha: 0.22)
                    : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Colors.white
                      .withValues(alpha: widget.isDark ? 0.08 : 0.12),
                ),
              ),
              child: _EnhancedMarkdown(
                content: widget.item.whatToChange,
                isDark: widget.isDark,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchFilesGraphPreview extends StatefulWidget {
  const _SearchFilesGraphPreview({
    required this.text,
    required this.isDark,
  });

  final String text;
  final bool isDark;

  @override
  State<_SearchFilesGraphPreview> createState() =>
      _SearchFilesGraphPreviewState();
}

class _SearchFilesGraphPreviewState extends State<_SearchFilesGraphPreview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final titleColor = widget.isDark ? Colors.grey[300] : Colors.blueGrey[700];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.blueGrey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: widget.isDark ? 0.06 : 0.1),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(Icons.account_tree_outlined, size: 15, color: subColor),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'File relationship graph',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: subColor,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  widget.text,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.35,
                    fontFamily: 'monospace',
                    color: subColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CodingMindMapNodeItem {
  const _CodingMindMapNodeItem({
    required this.title,
    this.subtitle,
    this.path,
    this.action,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final String? path;
  final String? action;
  final List<_CodingMindMapNodeItem> children;
}

class _CodingMindMapTreeCard extends StatelessWidget {
  const _CodingMindMapTreeCard({
    required this.roots,
    required this.isDark,
  });

  final List<_CodingMindMapNodeItem> roots;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.blueGrey.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.12 : 0.12),
        ),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < roots.length; i++) ...[
            _CodingMindMapNodeTile(
              node: roots[i],
              isDark: isDark,
              depth: 0,
              accentIndex: i,
              defaultOpen: true,
            ),
            if (i != roots.length - 1)
              Divider(
                height: 10,
                color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.08),
              ),
          ],
        ],
      ),
    );
  }
}

class _CodingMindMapNodeTile extends StatefulWidget {
  const _CodingMindMapNodeTile({
    required this.node,
    required this.isDark,
    required this.depth,
    required this.accentIndex,
    this.defaultOpen = false,
  });

  final _CodingMindMapNodeItem node;
  final bool isDark;
  final int depth;
  final int accentIndex;
  final bool defaultOpen;

  @override
  State<_CodingMindMapNodeTile> createState() => _CodingMindMapNodeTileState();
}

class _CodingMindMapNodeTileState extends State<_CodingMindMapNodeTile> {
  late bool _open = widget.defaultOpen;

  static const _accents = <Color>[
    Color(0xFFF87171),
    Color(0xFFF59E0B),
    Color(0xFF818CF8),
    Color(0xFF34D399),
    Color(0xFF38BDF8),
    Color(0xFFF472B6),
  ];

  @override
  Widget build(BuildContext context) {
    final hasChildren = widget.node.children.isNotEmpty;
    final accent = _accents[widget.accentIndex % _accents.length];
    final titleColor = widget.isDark ? Colors.grey[200] : Colors.blueGrey[800];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];
    final titleSize = widget.depth == 0 ? 13.0 : 12.0;
    final titleWeight = widget.depth == 0 ? FontWeight.w700 : FontWeight.w600;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasChildren ? () => setState(() => _open = !_open) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: EdgeInsets.only(
              left: widget.depth * 10.0,
              top: 3,
              bottom: 3,
              right: 2,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: widget.depth == 0 ? 2.8 : 2.2,
                  height: widget.depth == 0 ? 22 : 18,
                  margin: const EdgeInsets.only(top: 2, right: 8),
                  decoration: BoxDecoration(
                    color: accent.withValues(
                        alpha: widget.depth == 0 ? 0.95 : 0.8),
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.node.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: titleSize,
                          fontWeight: titleWeight,
                          color: titleColor,
                        ),
                      ),
                      if ((widget.node.subtitle?.isNotEmpty ?? false) ||
                          (widget.node.path?.isNotEmpty ?? false) ||
                          (widget.node.action?.isNotEmpty ?? false))
                        Text(
                          _buildMetaText(widget.node),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5,
                            color: subColor,
                          ),
                        ),
                    ],
                  ),
                ),
                if (hasChildren) ...[
                  const SizedBox(width: 8),
                  Container(
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      color: Colors.white
                          .withValues(alpha: widget.isDark ? 0.08 : 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _open ? Icons.expand_more : Icons.chevron_right,
                      size: 14,
                      color: subColor,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_open && hasChildren) ...[
          const SizedBox(height: 2),
          for (var i = 0; i < widget.node.children.length; i++) ...[
            _CodingMindMapNodeTile(
              node: widget.node.children[i],
              isDark: widget.isDark,
              depth: widget.depth + 1,
              accentIndex: i + widget.accentIndex + 1,
            ),
            if (i != widget.node.children.length - 1)
              Divider(
                height: 8,
                indent: (widget.depth + 1) * 10.0 + 12,
                color:
                    Colors.white.withValues(alpha: widget.isDark ? 0.04 : 0.06),
              ),
          ],
        ],
      ],
    );
  }

  String _buildMetaText(_CodingMindMapNodeItem node) {
    final parts = <String>[
      if (node.action != null && node.action!.isNotEmpty) node.action!,
      if (node.path != null && node.path!.isNotEmpty) p.basename(node.path!),
      if (node.subtitle != null && node.subtitle!.isNotEmpty) node.subtitle!,
    ];
    return parts.join(' · ');
  }
}

class _ApplyDiffStats {
  const _ApplyDiffStats({
    required this.added,
    required this.removed,
  });

  final int added;
  final int removed;
}

class _ApplyDiffPreview {
  const _ApplyDiffPreview({
    required this.removedLines,
    required this.addedLines,
  });

  final List<String> removedLines;
  final List<String> addedLines;
}

class _LinterFileResult {
  const _LinterFileResult({
    required this.path,
    required this.linter,
    required this.success,
    required this.fixed,
    required this.clean,
    required this.output,
  });

  final String path;
  final String? linter;
  final bool? success;
  final bool? fixed;
  final bool? clean;
  final String? output;
}

class _DiffCountChip extends StatelessWidget {
  const _DiffCountChip({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

class _LinterResultRow extends StatefulWidget {
  const _LinterResultRow({
    required this.item,
    required this.isDark,
  });

  final _LinterFileResult item;
  final bool isDark;

  @override
  State<_LinterResultRow> createState() => _LinterResultRowState();
}

class _LinterResultRowState extends State<_LinterResultRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final titleColor = widget.isDark ? Colors.grey[200] : Colors.blueGrey[800];
    final metaColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];
    final output = widget.item.output ?? '';
    final hasOutput = output.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: hasOutput ? () => setState(() => _open = !_open) : null,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  widget.item.success == true ? Icons.check_circle : Icons.rule,
                  size: 14,
                  color: widget.item.success == true
                      ? Colors.green
                      : (widget.isDark
                          ? Colors.grey[400]
                          : Colors.blueGrey[600]),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p.basename(widget.item.path),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                      Text(
                        widget.item.path,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10.5, color: metaColor),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          if (widget.item.linter != null)
                            _LinterBadge(
                              label: widget.item.linter!,
                              color: Colors.blueGrey,
                            ),
                          if (widget.item.success != null)
                            _LinterBadge(
                              label:
                                  widget.item.success! ? 'success' : 'failed',
                              color: widget.item.success!
                                  ? Colors.green
                                  : Colors.red,
                            ),
                          if (widget.item.clean != null)
                            _LinterBadge(
                              label: widget.item.clean! ? 'clean' : 'not clean',
                              color: widget.item.clean!
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                          if (widget.item.fixed != null &&
                              widget.item.fixed == true)
                            const _LinterBadge(
                              label: 'fixed',
                              color: Colors.teal,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                if (hasOutput) ...[
                  const SizedBox(width: 6),
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: metaColor,
                  ),
                ],
              ],
            ),
          ),
        ),
        if (_open && hasOutput)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(left: 20, top: 6),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: widget.isDark
                  ? Colors.black.withValues(alpha: 0.22)
                  : Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color:
                    Colors.white.withValues(alpha: widget.isDark ? 0.08 : 0.12),
              ),
            ),
            child: SelectableText(
              output,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                color: widget.isDark ? Colors.grey[300] : Colors.grey[800],
              ),
            ),
          ),
      ],
    );
  }
}

class _LinterBadge extends StatelessWidget {
  const _LinterBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.18)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _ListDirSummaryChips extends StatelessWidget {
  const _ListDirSummaryChips({
    required this.summary,
    required this.isDark,
  });

  final Map summary;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final chips = <String>[
      if (summary['total_files'] != null) '${summary['total_files']} files',
      if (summary['total_dirs'] != null) '${summary['total_dirs']} dirs',
      if ((summary['total_size_formatted']?.toString().isNotEmpty ?? false))
        summary['total_size_formatted'].toString(),
    ];

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: chips
          .map((label) => Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: Colors.blueGrey.withValues(alpha: 0.16),
                  ),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark ? Colors.grey[300] : Colors.blueGrey[700],
                  ),
                ),
              ))
          .toList(),
    );
  }
}

class _ListDirTreePreview extends StatefulWidget {
  const _ListDirTreePreview({
    required this.tree,
    required this.isDark,
  });

  final String tree;
  final bool isDark;

  @override
  State<_ListDirTreePreview> createState() => _ListDirTreePreviewState();
}

class _ListDirTreePreviewState extends State<_ListDirTreePreview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final titleColor = widget.isDark ? Colors.grey[300] : Colors.blueGrey[700];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];
    final previewLine = widget.tree.split('\n').firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.blueGrey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: widget.isDark ? 0.06 : 0.1),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.account_tree_outlined,
                      size: 15, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _open
                          ? 'Directory tree'
                          : (previewLine.isEmpty
                              ? 'Directory tree'
                              : previewLine),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: subColor,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  widget.tree,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    height: 1.35,
                    color: subColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _WriteFileContentPreview extends StatefulWidget {
  const _WriteFileContentPreview({
    required this.content,
    required this.isDark,
  });

  final String content;
  final bool isDark;

  @override
  State<_WriteFileContentPreview> createState() =>
      _WriteFileContentPreviewState();
}

class _WriteFileContentPreviewState extends State<_WriteFileContentPreview> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final titleColor = widget.isDark ? Colors.grey[300] : Colors.blueGrey[700];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];
    final firstLine = widget.content.split('\n').firstWhere(
          (line) => line.trim().isNotEmpty,
          orElse: () => '',
        );

    return Container(
      decoration: BoxDecoration(
        color: widget.isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.blueGrey.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: widget.isDark ? 0.06 : 0.1),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _open = !_open),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.description_outlined,
                      size: 15, color: Colors.blueGrey),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _open
                          ? 'Written content preview'
                          : (firstLine.isEmpty
                              ? 'Written content preview'
                              : firstLine),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                  Icon(
                    _open ? Icons.expand_more : Icons.chevron_right,
                    size: 16,
                    color: subColor,
                  ),
                ],
              ),
            ),
          ),
          if (_open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SelectableText(
                  _truncateLines(widget.content, 80),
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 10.5,
                    height: 1.35,
                    color: subColor,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _truncateLines(String content, int maxLines) {
    final lines = content.split('\n');
    if (lines.length <= maxLines) return content;
    return '${lines.take(maxLines).join('\n')}\n... (${lines.length - maxLines} more lines)';
  }
}

class _ApplyDiffPreviewCard extends StatelessWidget {
  const _ApplyDiffPreviewCard({
    required this.preview,
    required this.isDark,
  });

  final _ApplyDiffPreview preview;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark
            ? Colors.white.withValues(alpha: 0.02)
            : Colors.blueGrey.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.06 : 0.1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (preview.removedLines.isNotEmpty)
            _DiffBlockSection(
              lines: preview.removedLines,
              color: Colors.red,
              isDark: isDark,
              prefix: '-',
            ),
          if (preview.addedLines.isNotEmpty)
            _DiffBlockSection(
              lines: preview.addedLines,
              color: Colors.green,
              isDark: isDark,
              prefix: '+',
            ),
        ],
      ),
    );
  }
}

class _DiffBlockSection extends StatelessWidget {
  const _DiffBlockSection({
    required this.lines,
    required this.color,
    required this.isDark,
    required this.prefix,
  });

  final List<String> lines;
  final Color color;
  final bool isDark;
  final String prefix;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: isDark ? 0.18 : 0.10),
        border: Border(
          left: BorderSide(color: color.withValues(alpha: 0.85), width: 2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final line in lines)
            Text(
              '$prefix $line',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 10.5,
                height: 1.3,
                color: isDark ? Colors.grey[200] : Colors.grey[900],
              ),
            ),
        ],
      ),
    );
  }
}

class _ThinkingToolBlock extends StatefulWidget {
  const _ThinkingToolBlock({
    required this.content,
    required this.isComplete,
    required this.isDark,
  });

  final String content;
  final bool isComplete;
  final bool isDark;

  @override
  State<_ThinkingToolBlock> createState() => _ThinkingToolBlockState();
}

class _ThinkingToolBlockState extends State<_ThinkingToolBlock> {
  late bool _expanded = !widget.isComplete;

  @override
  void didUpdateWidget(covariant _ThinkingToolBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isComplete && widget.isComplete) {
      // Thinking completed: auto-collapse as requested.
      _expanded = false;
    } else if (!widget.isComplete && oldWidget.content != widget.content) {
      // Keep incomplete thinking visible while streaming.
      _expanded = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.blue.withValues(alpha: 0.25);
    final bgColor = widget.isDark
        ? Colors.blue.withValues(alpha: 0.08)
        : Colors.blue.withValues(alpha: 0.05);
    final titleColor = widget.isDark ? Colors.blue[200] : Colors.blue[800];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];
    final bodyBg =
        widget.isDark ? Colors.black.withValues(alpha: 0.20) : Colors.white;
    final preview = _buildPreview(widget.content);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: subColor,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.psychology, size: 15, color: Colors.blue),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Thinking',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                  ),
                  if (!widget.isComplete)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.blue.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                            color: Colors.blue.withValues(alpha: 0.18)),
                      ),
                      child: Text(
                        'streaming',
                        style: TextStyle(
                          fontSize: 10,
                          color: titleColor,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!_expanded && preview.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
              child: Text(
                preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  color: subColor,
                ),
              ),
            ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: bodyBg,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.white
                        .withValues(alpha: widget.isDark ? 0.06 : 0.12),
                  ),
                ),
                child: SelectableText(
                  widget.content.isEmpty ? '...' : widget.content,
                  style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.35,
                    color: widget.isDark ? Colors.grey[300] : Colors.grey[800],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _buildPreview(String content) {
    final lines = content
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '';
    return lines.take(2).join(' ');
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
        border:
            Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
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
          top: BorderSide(
              color: isDark ? Colors.grey[700]! : Colors.grey[300]!, width: 1),
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
        border:
            Border.all(color: isDark ? Colors.grey[700]! : Colors.grey[300]!),
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
    final functionName = parsed?['name']?.toString();
    final args = parsed?['arguments'] ?? parsed?['args'];

    if (functionName == 'gsearch') {
      return _buildGSearchCallBlock(parsed, content);
    }
    if (functionName == 'navigate_to') {
      final widget = _buildNavigateToCallBlock(parsed);
      if (widget != null) return widget;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.purple.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: Colors.purple.withValues(alpha: 0.3), width: 1),
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
              if (functionName != null) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    functionName,
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
          if (args != null)
            _buildArguments(args)
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
    final functionName = parsed?['name']?.toString();

    if (functionName == 'gsearch') {
      final gsearchWidget = _buildGSearchResultBlock(parsed, content);
      if (gsearchWidget != null) {
        return gsearchWidget;
      }
    }
    if (functionName == 'navigate_to') {
      final navigateWidget = _buildNavigateToResultBlock(parsed);
      if (navigateWidget != null) {
        return navigateWidget;
      }
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: Colors.green.withValues(alpha: 0.3), width: 1),
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

  Widget _buildGSearchCallBlock(Map<String, dynamic>? parsed, String content) {
    final args = parsed?['args'];
    String? query;
    if (args is Map<String, dynamic>) {
      query = args['query']?.toString();
    } else if (args is Map) {
      query = args['query']?.toString();
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (isDark ? Colors.blueGrey[900] : Colors.blueGrey[50]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.blueGrey.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          const Icon(Icons.search, size: 16, color: Colors.blueGrey),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              query == null || query.isEmpty ? 'Search' : 'Search $query',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.grey[200] : Colors.blueGrey[800],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget? _buildNavigateToCallBlock(Map<String, dynamic>? parsed) {
    if (parsed == null) return null;
    final args = parsed['args'] ?? parsed['arguments'];
    if (args is! Map) return null;
    final url = args['url']?.toString();
    final lookingFor = args['looking_for']?.toString();
    if ((url == null || url.isEmpty) &&
        (lookingFor == null || lookingFor.isEmpty)) {
      return null;
    }

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: (isDark ? Colors.blueGrey[900] : Colors.blueGrey[50]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Colors.blueGrey.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.open_in_browser,
                  size: 16, color: Colors.blueGrey),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  url == null || url.isEmpty
                      ? 'Navigate to page'
                      : 'Navigate to $url',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.grey[200] : Colors.blueGrey[800],
                  ),
                ),
              ),
            ],
          ),
          if (lookingFor != null && lookingFor.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Looking for: $lookingFor',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                color: isDark ? Colors.grey[400] : Colors.blueGrey[600],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget? _buildGSearchResultBlock(
      Map<String, dynamic>? parsed, String content) {
    if (parsed == null) return null;
    final response = parsed['response'];
    if (response is! Map) return null;
    final organic = response['organic'];
    if (organic is! List) return null;

    final items = organic
        .whereType<Map>()
        .map((item) => _SearchResultItem(
              title: item['title']?.toString() ?? '',
              link: item['link']?.toString() ?? '',
              snippet: item['snippet']?.toString(),
              date: item['date']?.toString(),
              source: _hostFromUrl(item['link']?.toString()),
            ))
        .where((e) => e.title.isNotEmpty)
        .toList();

    if (items.isEmpty) return null;

    return _SearchResultsToolBlock(
      items: items,
      title: 'Search results',
      isDark: isDark,
    );
  }

  Widget? _buildNavigateToResultBlock(Map<String, dynamic>? parsed) {
    if (parsed == null) return null;
    final response = parsed['response'];

    String? responseText;
    if (response is String) {
      responseText = response;
    } else if (response is Map || response is List) {
      responseText = const JsonEncoder.withIndent('  ').convert(response);
    }

    if (responseText == null || responseText.isEmpty) return null;
    final isError = responseText.toLowerCase().startsWith('error:');

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: (isDark ? Colors.blueGrey[900] : Colors.blueGrey[50]),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color:
              (isError ? Colors.red : Colors.blueGrey).withValues(alpha: 0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.open_in_new,
                  size: 16,
                  color: isError ? Colors.red : Colors.blueGrey,
                ),
                const SizedBox(width: 8),
                Text(
                  isError ? 'Navigate result (error)' : 'Navigate result',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: isError
                        ? (isDark ? Colors.red[300] : Colors.red[700])
                        : (isDark ? Colors.grey[200] : Colors.blueGrey[800]),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color:
                  isDark ? Colors.black.withValues(alpha: 0.25) : Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _EnhancedMarkdown(
              content: responseText,
              isDark: isDark,
            ),
          ),
        ],
      ),
    );
  }

  String? _hostFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      return Uri.parse(url).host;
    } catch (_) {
      return null;
    }
  }

  Widget _buildInsightBlock(String content) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border:
            Border.all(color: Colors.amber.withValues(alpha: 0.3), width: 1),
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

class _SearchResultItem {
  const _SearchResultItem({
    required this.title,
    required this.link,
    this.snippet,
    this.date,
    this.source,
  });

  final String title;
  final String link;
  final String? snippet;
  final String? date;
  final String? source;
}

class _SearchResultsToolBlock extends StatefulWidget {
  const _SearchResultsToolBlock({
    required this.items,
    required this.title,
    required this.isDark,
  });

  final List<_SearchResultItem> items;
  final String title;
  final bool isDark;

  @override
  State<_SearchResultsToolBlock> createState() =>
      _SearchResultsToolBlockState();
}

class _SearchResultsToolBlockState extends State<_SearchResultsToolBlock> {
  bool _expanded = true;

  @override
  Widget build(BuildContext context) {
    final borderColor = Colors.blueGrey.withValues(alpha: 0.35);
    final bgColor =
        widget.isDark ? Colors.blueGrey[900]! : Colors.blueGrey[50]!;
    final headerColor = widget.isDark ? Colors.grey[200] : Colors.blueGrey[800];
    final subColor = widget.isDark ? Colors.grey[400] : Colors.blueGrey[600];

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    _expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: subColor,
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.search, size: 16, color: Colors.blueGrey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${widget.title} (${widget.items.length} results)',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: headerColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: _SearchResultsListBody(
                items: widget.items,
                isDark: widget.isDark,
                dividerColor: borderColor,
              ),
            ),
        ],
      ),
    );
  }
}

class _SearchResultsListBody extends StatelessWidget {
  const _SearchResultsListBody({
    required this.items,
    required this.isDark,
    this.dividerColor,
  });

  final List<_SearchResultItem> items;
  final bool isDark;
  final Color? dividerColor;

  @override
  Widget build(BuildContext context) {
    final color = dividerColor ?? Colors.blueGrey.withValues(alpha: 0.25);
    return Column(
      children: [
        for (var i = 0; i < items.length; i++) ...[
          _SearchResultRow(item: items[i], isDark: isDark),
          if (i != items.length - 1)
            Divider(
              height: 12,
              color: color,
            ),
        ],
      ],
    );
  }
}

class _SearchResultRow extends StatelessWidget {
  const _SearchResultRow({
    required this.item,
    required this.isDark,
  });

  final _SearchResultItem item;
  final bool isDark;

  Future<void> _openLink() async {
    final uri = Uri.tryParse(item.link);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final titleColor = isDark ? Colors.lightBlue[200] : Colors.blue[800];
    final metaColor = isDark ? Colors.grey[400] : Colors.grey[700];
    final snippetColor = isDark ? Colors.grey[300] : Colors.grey[800];

    final metaParts = <String>[
      if (item.date != null && item.date!.isNotEmpty) item.date!,
      if (item.source != null && item.source!.isNotEmpty) item.source!,
    ];

    return InkWell(
      onTap: _openLink,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item.title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: titleColor,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (metaParts.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                metaParts.join('  •  '),
                style: TextStyle(
                  fontSize: 10.5,
                  color: metaColor,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
            if (item.snippet != null && item.snippet!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                item.snippet!,
                style: TextStyle(
                  fontSize: 11,
                  color: snippetColor,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ],
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
                  ? Image.file(File(attachment.path),
                      width: 72, height: 72, fit: BoxFit.cover)
                  : Container(
                      width: 72,
                      height: 72,
                      color:
                          Theme.of(context).colorScheme.surfaceContainerHighest,
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
    final isThisFilePlaying =
        audioPlayer?.currentFilePath == widget.attachment.path;
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

  Widget _buildPlayButton(
      BuildContext context, bool isPlaying, bool hasPlayer) {
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
