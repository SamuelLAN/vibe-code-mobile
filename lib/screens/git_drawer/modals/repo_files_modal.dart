import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:flutter_highlight/themes/atom-one-dark.dart';
import 'package:flutter_highlight/themes/github.dart';

import '../../../../models/git_models.dart';

class RepoFilesModal extends StatefulWidget {
  const RepoFilesModal({
    super.key,
    required this.onListDir,
    required this.onReadFile,
    required this.onSaveFile,
    required this.onRemoveFile,
    required this.onRemoveDir,
  });

  final Future<List<GitRepoNode>> Function(String relativePath, int depth)
      onListDir;
  final Future<GitReadFileResult> Function(String relativePath) onReadFile;
  final Future<void> Function(String relativePath, String content) onSaveFile;
  final Future<void> Function(String relativePath) onRemoveFile;
  final Future<void> Function(String relativePath) onRemoveDir;

  @override
  State<RepoFilesModal> createState() => _RepoFilesModalState();
}

class _RepoFilesModalState extends State<RepoFilesModal> {
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedPaths = <String>{};
  final Set<String> _loadingDirs = <String>{};

  List<_RepoTreeNode> _roots = const <_RepoTreeNode>[];
  bool _loadingRoot = true;
  bool _readingFile = false;
  String _searchQuery = '';
  String? _error;
  String? _selectedPath;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _loadRoot();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    final next = _searchController.text.trim().toLowerCase();
    if (_searchQuery == next) return;
    setState(() => _searchQuery = next);
  }

  Future<void> _loadRoot() async {
    setState(() {
      _loadingRoot = true;
      _error = null;
    });
    try {
      final roots = await widget.onListDir('', 2);
      if (!mounted) return;
      setState(() {
        _roots = roots.map(_RepoTreeNode.fromApi).toList(growable: false);
        _loadingRoot = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingRoot = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _toggleDirectory(_RepoTreeNode node) async {
    if (!node.isDir) return;
    final path = node.path;
    final expanded = _expandedPaths.contains(path);
    if (expanded) {
      setState(() => _expandedPaths.remove(path));
      return;
    }
    setState(() => _expandedPaths.add(path));
    if (node.didLoadChildrenAttempt) return;

    setState(() => _loadingDirs.add(path));
    try {
      final items = await widget.onListDir(path, 2);
      if (!mounted) return;
      setState(() {
        node.replaceChildren(items.map(_RepoTreeNode.fromApi).toList());
      });
    } finally {
      if (!mounted) return;
      setState(() => _loadingDirs.remove(path));
    }
  }

  Future<void> _openFile(_RepoTreeNode node) async {
    if (node.isDir) return;
    setState(() {
      _selectedPath = node.path;
      _readingFile = true;
    });
    try {
      final result = await widget.onReadFile(node.path);
      if (!mounted) return;
      setState(() => _readingFile = false);
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        enableDrag: true,
        backgroundColor: Colors.transparent,
        builder: (context) => FractionallySizedBox(
          heightFactor: 0.94,
          child: _FilePreviewSheet(
            result: result,
            onSave: (content) async {
              await widget.onSaveFile(result.relativePath, content);
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('File saved')),
              );
              await _loadRoot();
            },
            onDelete: () async {
              final confirmed = await _showRemoveConfirm(
                title: 'Remove file',
                message:
                    'This will permanently remove `${result.relativePath}`. Continue?',
              );
              if (confirmed != true) return;
              await widget.onRemoveFile(result.relativePath);
              if (!mounted) return;
              Navigator.pop(context);
              ScaffoldMessenger.of(this.context).showSnackBar(
                const SnackBar(content: Text('File removed')),
              );
              await _loadRoot();
            },
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _readingFile = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to read file: $e')),
      );
    }
  }

  Future<void> _showItemActions(_RepoTreeNode node) async {
    final isDir = node.isDir;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(height: 6),
                Container(
                  width: 34,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 8),
                ListTile(
                  leading: const Icon(Icons.copy_rounded),
                  title: const Text('Copy relative path'),
                  subtitle: Text(node.path),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: node.path));
                    if (!mounted) return;
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Path copied')),
                    );
                  },
                ),
                if (!isDir)
                  ListTile(
                    leading: const Icon(Icons.edit_rounded),
                    title: const Text('Edit file'),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _openFile(node);
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.delete_outline_rounded,
                      color: Colors.redAccent),
                  title: Text(isDir ? 'Remove directory' : 'Remove file',
                      style: const TextStyle(color: Colors.redAccent)),
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    final confirmed = await _showRemoveConfirm(
                      title: isDir ? 'Remove directory' : 'Remove file',
                      message:
                          'This will permanently remove `${node.path}`. Continue?',
                    );
                    if (confirmed != true) return;
                    try {
                      if (isDir) {
                        await widget.onRemoveDir(node.path);
                      } else {
                        await widget.onRemoveFile(node.path);
                      }
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            isDir ? 'Directory removed' : 'File removed',
                          ),
                        ),
                      );
                      await _loadRoot();
                    } catch (e) {
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Remove failed: $e')),
                      );
                    }
                  },
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool?> _showRemoveConfirm({
    required String title,
    required String message,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm remove'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final visibleNodes = _flattenVisibleNodes(_roots);

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Files',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _loadingRoot ? null : _loadRoot,
                    icon: _loadingRoot
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh_rounded),
                    tooltip: 'Refresh files',
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey[600]),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索文件...',
                  prefixIcon: const Icon(Icons.search_rounded),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  isDense: true,
                ),
              ),
            ),
            Expanded(
              child: Stack(
                children: [
                  if (_error != null)
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Text(
                          _error!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.red[400],
                            fontSize: 13,
                          ),
                        ),
                      ),
                    )
                  else if (_loadingRoot)
                    const Center(child: CircularProgressIndicator())
                  else if (visibleNodes.isEmpty)
                    Center(
                      child: Text(
                        _searchQuery.isEmpty ? 'No files' : 'No matching files',
                        style: TextStyle(color: Colors.grey[600]),
                      ),
                    )
                  else
                    ListView.builder(
                      padding: const EdgeInsets.fromLTRB(8, 2, 8, 20),
                      itemCount: visibleNodes.length,
                      itemBuilder: (context, index) {
                        final row = visibleNodes[index];
                        final node = row.node;
                        final isExpanded = _expandedPaths.contains(node.path);
                        final isLoadingDir = _loadingDirs.contains(node.path);
                        final selected = _selectedPath == node.path;
                        return _FileTreeRow(
                          node: node,
                          depth: row.depth,
                          isExpanded: isExpanded,
                          isSelected: selected,
                          isLoadingDir: isLoadingDir,
                          onTap: () => node.isDir
                              ? _toggleDirectory(node)
                              : _openFile(node),
                          onLongPress: () => _showItemActions(node),
                        );
                      },
                    ),
                  if (_readingFile)
                    const Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: Color(0x55000000),
                          child: Center(
                            child: CircularProgressIndicator(),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<_VisibleTreeNode> _flattenVisibleNodes(List<_RepoTreeNode> roots) {
    final rows = <_VisibleTreeNode>[];
    for (final node in roots) {
      _collectVisibleNode(rows, node, 0);
    }
    return rows;
  }

  void _collectVisibleNode(
    List<_VisibleTreeNode> rows,
    _RepoTreeNode node,
    int depth,
  ) {
    if (!_shouldIncludeNode(node)) return;

    rows.add(_VisibleTreeNode(node: node, depth: depth));
    if (!node.isDir) return;

    final forceExpand = _searchQuery.isNotEmpty;
    final expanded = forceExpand || _expandedPaths.contains(node.path);
    if (!expanded) return;

    for (final child in node.children) {
      _collectVisibleNode(rows, child, depth + 1);
    }
  }

  bool _shouldIncludeNode(_RepoTreeNode node) {
    if (_searchQuery.isEmpty) return true;
    if (node.name.toLowerCase().contains(_searchQuery) ||
        node.path.toLowerCase().contains(_searchQuery)) {
      return true;
    }
    for (final child in node.children) {
      if (_shouldIncludeNode(child)) return true;
    }
    return false;
  }
}

class _FileTreeRow extends StatelessWidget {
  const _FileTreeRow({
    required this.node,
    required this.depth,
    required this.isExpanded,
    required this.isSelected,
    required this.isLoadingDir,
    required this.onTap,
    required this.onLongPress,
  });

  final _RepoTreeNode node;
  final int depth;
  final bool isExpanded;
  final bool isSelected;
  final bool isLoadingDir;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final indent = 12.0 + depth * 16.0;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? (isDark ? Colors.white10 : const Color(0xFFEFF0F2))
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            padding: EdgeInsets.fromLTRB(indent, 8, 12, 8),
            child: Row(
              children: [
                if (node.isDir)
                  SizedBox(
                    width: 18,
                    child: isLoadingDir
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            isExpanded
                                ? Icons.expand_more_rounded
                                : Icons.chevron_right_rounded,
                            size: 18,
                            color: Colors.grey[500],
                          ),
                  )
                else
                  const SizedBox(width: 18),
                const SizedBox(width: 2),
                Icon(
                  node.isDir
                      ? Icons.folder_outlined
                      : Icons.insert_drive_file_outlined,
                  size: 20,
                  color:
                      node.isDir ? const Color(0xFF6B7280) : Colors.grey[700],
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    node.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FilePreviewSheet extends StatefulWidget {
  const _FilePreviewSheet({
    required this.result,
    required this.onSave,
    required this.onDelete,
  });

  final GitReadFileResult result;
  final Future<void> Function(String content) onSave;
  final Future<void> Function() onDelete;

  @override
  State<_FilePreviewSheet> createState() => _FilePreviewSheetState();
}

class _FilePreviewSheetState extends State<_FilePreviewSheet> {
  late final TextEditingController _controller;
  bool _editing = false;
  bool _saving = false;
  bool _deleting = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.result.content);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final language = _languageFromPath(widget.result.relativePath);
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(top: 10),
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.result.relativePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        Text(
                          _editing
                              ? 'Editing'
                              : (language == null ? 'Text preview' : language),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (widget.result.truncated)
                          Text(
                            'Truncated to ${widget.result.maxChars} chars',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(_editing
                        ? Icons.visibility_rounded
                        : Icons.edit_rounded),
                    tooltip: _editing ? 'Preview' : 'Edit',
                    onPressed: _saving || _deleting
                        ? null
                        : () => setState(() => _editing = !_editing),
                  ),
                  IconButton(
                    icon: _deleting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline_rounded),
                    tooltip: 'Remove file',
                    onPressed: _saving || _deleting
                        ? null
                        : () async {
                            setState(() => _deleting = true);
                            try {
                              await widget.onDelete();
                            } finally {
                              if (mounted) {
                                setState(() => _deleting = false);
                              }
                            }
                          },
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: Colors.grey[600]),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isDark
                      ? const Color(0xFF111111)
                      : const Color(0xFFF5F5F5),
                  border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: _editing
                    ? Padding(
                        padding: const EdgeInsets.all(10),
                        child: TextField(
                          controller: _controller,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          style: TextStyle(
                            fontSize: 12,
                            height: 1.45,
                            fontFamily: 'monospace',
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            isDense: true,
                          ),
                        ),
                      )
                    : _CodeView(
                        content: _controller.text,
                        language: language,
                        isDark: isDark,
                      ),
              ),
            ),
            if (_editing)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving
                        ? null
                        : () async {
                            setState(() => _saving = true);
                            try {
                              await widget.onSave(_controller.text);
                              if (!mounted) return;
                              setState(() => _editing = false);
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Save failed: $e')),
                              );
                            } finally {
                              if (mounted) {
                                setState(() => _saving = false);
                              }
                            }
                          },
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(_saving ? 'Saving...' : 'Save file'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CodeView extends StatelessWidget {
  const _CodeView({
    required this.content,
    required this.language,
    required this.isDark,
  });

  final String content;
  final String? language;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final lineCount = '\n'.allMatches(content).length + 1;
    final numbers =
        List<String>.generate(lineCount, (i) => '${i + 1}').join('\n');
    final textTheme = Theme.of(context).textTheme;

    return Scrollbar(
      child: SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
                decoration: BoxDecoration(
                  color: isDark
                      ? const Color(0xFF0E1620)
                      : const Color(0xFFF0F3F7),
                  borderRadius:
                      const BorderRadius.horizontal(left: Radius.circular(12)),
                ),
                child: SelectableText(
                  numbers,
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    fontFamily: 'monospace',
                    color: Colors.grey[600],
                  ),
                ),
              ),
              Container(
                width: 1,
                color: isDark ? Colors.white12 : Colors.black12,
              ),
              ConstrainedBox(
                constraints: BoxConstraints(
                  minWidth: MediaQuery.of(context).size.width - 70,
                ),
                child: HighlightView(
                  content,
                  language: language,
                  theme: isDark ? atomOneDarkTheme : githubTheme,
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  textStyle: textTheme.bodySmall?.copyWith(
                        fontSize: 12,
                        height: 1.45,
                        fontFamily: 'monospace',
                      ) ??
                      const TextStyle(
                        fontSize: 12,
                        height: 1.45,
                        fontFamily: 'monospace',
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String? _languageFromPath(String path) {
  final lower = path.toLowerCase();
  if (lower.endsWith('.py')) return 'python';
  if (lower.endsWith('.js') ||
      lower.endsWith('.mjs') ||
      lower.endsWith('.cjs')) {
    return 'javascript';
  }
  if (lower.endsWith('.tsx')) return 'tsx';
  if (lower.endsWith('.ts')) return 'typescript';
  if (lower.endsWith('.jsx')) return 'jsx';
  if (lower.endsWith('.json')) return 'json';
  if (lower.endsWith('.md') || lower.endsWith('.markdown')) return 'markdown';
  if (lower.endsWith('.html')) return 'xml';
  if (lower.endsWith('.css')) return 'css';
  if (lower.endsWith('.scss')) return 'scss';
  if (lower.endsWith('.yml') || lower.endsWith('.yaml')) return 'yaml';
  if (lower.endsWith('.sh')) return 'bash';
  if (lower.endsWith('.dart')) return 'dart';
  return null;
}

class _VisibleTreeNode {
  _VisibleTreeNode({
    required this.node,
    required this.depth,
  });

  final _RepoTreeNode node;
  final int depth;
}

class _RepoTreeNode {
  _RepoTreeNode({
    required this.name,
    required this.path,
    required this.type,
    required List<_RepoTreeNode> children,
    required this.didLoadChildrenAttempt,
  }) : children = List<_RepoTreeNode>.from(children);

  final String name;
  final String path;
  final String type;
  final List<_RepoTreeNode> children;
  bool didLoadChildrenAttempt;

  bool get isDir => type.toLowerCase() == 'dir';

  factory _RepoTreeNode.fromApi(GitRepoNode node) {
    final mappedChildren = node.children.map(_RepoTreeNode.fromApi).toList();
    return _RepoTreeNode(
      name: node.name,
      path: node.path,
      type: node.type,
      children: mappedChildren,
      didLoadChildrenAttempt: mappedChildren.isNotEmpty,
    );
  }

  void replaceChildren(List<_RepoTreeNode> next) {
    children
      ..clear()
      ..addAll(next);
    didLoadChildrenAttempt = true;
  }
}
