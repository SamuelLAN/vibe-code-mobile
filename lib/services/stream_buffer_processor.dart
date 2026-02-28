import 'dart:convert';

import '../models/stream_element.dart';

class BufferProcessorConfig {
  const BufferProcessorConfig({this.debug = false});

  final bool debug;
}

class _Tags {
  static const functionCall = '```function_call\n';
  static const functionResult = '```function_result\n';
  static const insightStart = '```insight_start\n';
  static const insightEnd = '```insight_end\n';
  static const edge = '```edge\n';
  static const thinking = '```thinking\n';
  static const closing = '```';
}

class _ExtractResult {
  const _ExtractResult({
    required this.found,
    required this.content,
    required this.endIndex,
  });

  final bool found;
  final String content;
  final int endIndex;
}

class StreamBufferProcessor {
  StreamBufferProcessor({this.config = const BufferProcessorConfig()});

  String _buffer = '';
  bool _inThinking = false;
  String _thinkingContent = '';
  final BufferProcessorConfig config;

  List<StreamElement> processChunk(String chunk) {
    _buffer += chunk;
    final elements = <StreamElement>[];

    var i = 0;
    while (i < _buffer.length) {
      if (_startsWithAt(_Tags.functionCall, i)) {
        final result = _extractBlock(i, _Tags.functionCall.length, true);
        if (result.found) {
          final element = _createElement(
              StreamElementType.functionCall, result.content, true);
          if (element != null) elements.add(element);
          i = result.endIndex;
          continue;
        }
      }

      if (_startsWithAt(_Tags.functionResult, i)) {
        final result = _extractBlock(i, _Tags.functionResult.length, true);
        if (result.found) {
          final element = _createElement(
              StreamElementType.functionResult, result.content, true);
          if (element != null) elements.add(element);
          i = result.endIndex;
          continue;
        }
      }

      if (_startsWithAt(_Tags.insightStart, i)) {
        final result = _extractBlock(i, _Tags.insightStart.length, true);
        if (result.found) {
          final element = _createElement(
              StreamElementType.insightStart, result.content, true);
          if (element != null) elements.add(element);
          i = result.endIndex;
          continue;
        }
      }

      if (_startsWithAt(_Tags.insightEnd, i)) {
        final result = _extractBlock(i, _Tags.insightEnd.length, true);
        if (result.found) {
          final element = _createElement(
              StreamElementType.insightEnd, result.content, true);
          if (element != null) elements.add(element);
          i = result.endIndex;
          continue;
        }
      }

      if (_startsWithAt(_Tags.edge, i)) {
        final result = _extractBlock(i, _Tags.edge.length, true);
        if (result.found) {
          final element =
              _createElement(StreamElementType.edge, result.content, true);
          if (element != null) elements.add(element);
          i = result.endIndex;
          continue;
        }
      }

      if (_startsWithAt(_Tags.thinking, i)) {
        final startIndex = i + _Tags.thinking.length;
        final endIndex = _buffer.indexOf(_Tags.closing, startIndex);
        if (endIndex != -1) {
          final content = _buffer.substring(startIndex, endIndex).trim();
          final element =
              _createElement(StreamElementType.thinking, content, true);
          if (element != null) elements.add(element);
          _inThinking = false;
          _thinkingContent = '';
          i = endIndex + _Tags.closing.length;
          continue;
        } else {
          final content = _buffer.substring(startIndex).trim();
          if (content.isNotEmpty) {
            final element =
                _createElement(StreamElementType.thinking, content, false);
            if (element != null) elements.add(element);
          }
          _inThinking = true;
          _thinkingContent = content;
          _buffer = _buffer.substring(i);
          break;
        }
      }

      if (_inThinking) {
        final endIndex = _buffer.indexOf(_Tags.closing, i);
        if (endIndex != -1) {
          final content = _buffer.substring(i, endIndex).trim();
          final finalContent = _thinkingContent +
              (_thinkingContent.isNotEmpty ? '\n' : '') +
              content;
          final element =
              _createElement(StreamElementType.thinking, finalContent, true);
          if (element != null) elements.add(element);
          _inThinking = false;
          _thinkingContent = '';
          i = endIndex + _Tags.closing.length;
          continue;
        } else {
          final newContent = _buffer.substring(i);
          _thinkingContent +=
              (_thinkingContent.isNotEmpty ? '\n' : '') + newContent;
          _buffer = '';
          break;
        }
      }

      final nextTagIndex = _findNextTag(i);
      if (nextTagIndex == -1) {
        final textContent = _trimExceptNewlines(_buffer.substring(i));
        if (textContent.isNotEmpty && !_inThinking) {
          final element =
              _createElement(StreamElementType.text, textContent, false);
          if (element != null) elements.add(element);
        }
        _buffer = '';
        break;
      } else if (nextTagIndex > i) {
        final textContent =
            _trimExceptNewlines(_buffer.substring(i, nextTagIndex));
        if (textContent.isNotEmpty && !_inThinking) {
          final element =
              _createElement(StreamElementType.text, textContent, false);
          if (element != null) elements.add(element);
        }
        i = nextTagIndex;
        continue;
      }

      i++;
    }

    return elements;
  }

  bool _startsWithAt(String needle, int index) {
    if (index + needle.length > _buffer.length) return false;
    return _buffer.substring(index, index + needle.length) == needle;
  }

  _ExtractResult _extractBlock(
      int startIndex, int tagLength, bool skipFirstLine) {
    final contentStart = startIndex + tagLength;
    var searchStart = contentStart;

    if (skipFirstLine) {
      final firstNewLine = _buffer.indexOf('\n', contentStart);
      if (firstNewLine == -1) {
        return _ExtractResult(found: false, content: '', endIndex: startIndex);
      }
      searchStart = firstNewLine + 1;
    }

    final endIndex = _findClosingFenceIndex(searchStart);
    if (endIndex == -1) {
      return _ExtractResult(found: false, content: '', endIndex: startIndex);
    }

    final content = _buffer.substring(contentStart, endIndex).trim();
    _buffer = _buffer.substring(0, startIndex) +
        _buffer.substring(endIndex + _Tags.closing.length);

    return _ExtractResult(found: true, content: content, endIndex: startIndex);
  }

  int _findClosingFenceIndex(int searchStart) {
    // Prefer a line-start closing fence (\\n```), which avoids matching
    // backticks that may appear in JSON string fields (for example args.text).
    final lineStartFence = _buffer.indexOf('\n${_Tags.closing}', searchStart);
    if (lineStartFence != -1) {
      return lineStartFence + 1;
    }
    return _buffer.indexOf(_Tags.closing, searchStart);
  }

  String _trimExceptNewlines(String str) {
    var start = 0;
    while (start < str.length && (str[start] == ' ' || str[start] == '\t')) {
      start++;
    }

    var end = str.length;
    while (end > start && (str[end - 1] == ' ' || str[end - 1] == '\t')) {
      end--;
    }
    return str.substring(start, end);
  }

  int _findNextTag(int startIndex) {
    final tags = [
      _Tags.functionCall,
      _Tags.functionResult,
      _Tags.insightStart,
      _Tags.insightEnd,
      _Tags.edge,
      _Tags.thinking,
    ];

    var minIndex = -1;
    for (final tag in tags) {
      final index = _buffer.indexOf(tag, startIndex);
      if (index != -1 && (minIndex == -1 || index < minIndex)) {
        minIndex = index;
      }
    }
    return minIndex;
  }

  StreamElement? _createElement(
      StreamElementType type, String content, bool isComplete) {
    if (content.isEmpty && type != StreamElementType.text) {
      return null;
    }

    final element = StreamElement(
      id: generateStreamElementId(),
      type: type,
      content: content,
      isComplete: isComplete,
    );

    if (type == StreamElementType.functionCall ||
        type == StreamElementType.functionResult) {
      try {
        final parsed = jsonDecode(content);
        if (parsed is Map<String, dynamic>) {
          final functionName = (parsed['name'] ?? 'unknown').toString();
          final functionId =
              (parsed['id'] ?? parsed['function_id'])?.toString();
          dynamic resultData;
          if (type == StreamElementType.functionResult) {
            final response = parsed['response'] ?? parsed;
            if (response is String) {
              try {
                resultData = jsonDecode(response);
              } catch (_) {
                resultData = response;
              }
            } else {
              resultData = response;
            }
          }
          element.metadata = {
            'functionName': functionName,
            'functionId': functionId,
            'isResult': type == StreamElementType.functionResult,
            if (type == StreamElementType.functionCall)
              'callData': parsed['args'] ?? parsed['arguments'] ?? parsed,
            if (type == StreamElementType.functionResult)
              'resultData': resultData,
          };
          if (config.debug) {
            // ignore: avoid_print
            print('[StreamBuffer] ${type.name}: $functionName - $functionId');
          }
        }
      } catch (_) {
        element.metadata = {
          'functionName': 'unknown',
          'functionId': null,
          'isResult': type == StreamElementType.functionResult,
        };
      }
    }

    if (type == StreamElementType.insightStart ||
        type == StreamElementType.insightEnd) {
      try {
        final parsed = jsonDecode(content);
        if (parsed is Map<String, dynamic>) {
          element.metadata = {
            ...?element.metadata,
            'insightId': parsed['insight_id']?.toString(),
            'isInsightStart': type == StreamElementType.insightStart,
          };
        }
      } catch (_) {
        element.metadata = {
          ...?element.metadata,
          'insightId': null,
          'isInsightStart': type == StreamElementType.insightStart,
        };
      }
    }

    if (type == StreamElementType.edge) {
      try {
        final parsed = jsonDecode(content);
        if (parsed is Map<String, dynamic>) {
          element.metadata = {
            ...?element.metadata,
            'edgeId': parsed['edge_id']?.toString(),
            'sourceInsightId': parsed['source_insight_id']?.toString(),
            'targetInsightId': parsed['target_insight_id']?.toString(),
          };
        }
      } catch (_) {}
    }

    return element;
  }

  String getBuffer() => _buffer;

  void reset() {
    _buffer = '';
    _inThinking = false;
    _thinkingContent = '';
  }

  bool isInThinking() => _inThinking;
}
