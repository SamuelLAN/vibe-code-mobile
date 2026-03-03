import 'package:flutter/material.dart';

import '../../../../models/git_models.dart';

class RepoFilesModal extends StatefulWidget {
  const RepoFilesModal({
    super.key,
    required this.onListDir,
    required this.onReadFile,
  });

  final Future<List<GitRepoNode>> Function(String relativePath, int depth)
      onListDir;
  final Future<GitReadFileResult> Function(String relativePath) onReadFile;

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
    } catch (_) {
      // Keep current node state; row remains expandable with existing children.
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
          heightFactor: 0.9,
          child: _FilePreviewSheet(result: result),
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
  });

  final _RepoTreeNode node;
  final int depth;
  final bool isExpanded;
  final bool isSelected;
  final bool isLoadingDir;
  final VoidCallback onTap;

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

class _FilePreviewSheet extends StatelessWidget {
  const _FilePreviewSheet({required this.result});

  final GitReadFileResult result;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
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
                          result.relativePath,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        if (result.truncated)
                          Text(
                            'Truncated to ${result.maxChars} chars',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange[700],
                            ),
                          ),
                      ],
                    ),
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
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isDark
                      ? const Color(0xFF111111)
                      : const Color(0xFFF5F5F5),
                  border: Border.all(
                      color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    result.content,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      fontFamily: 'monospace',
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
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
