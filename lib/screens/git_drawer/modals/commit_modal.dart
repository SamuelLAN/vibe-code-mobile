import 'package:flutter/material.dart';

import '../../../../constants/colors.dart';
import '../../../../models/git_models.dart';
import '../widgets/widgets.dart';

class CommitModal extends StatefulWidget {
  const CommitModal({
    super.key,
    required this.files,
    required this.onConfirm,
    required this.onGenerateMessage,
  });

  final List<GitWorktreeFile> files;
  final void Function(String message, List<String> filePaths, bool addAll)
      onConfirm;
  final Future<String> Function(List<String> filePaths) onGenerateMessage;

  @override
  State<CommitModal> createState() => _CommitModalState();
}

class _CommitModalState extends State<CommitModal> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late List<_CommitSelectionFile> _files;
  bool _generatingMessage = false;

  @override
  void initState() {
    super.initState();
    _files = widget.files
        .map(
          (f) => _CommitSelectionFile(
            path: f.path,
            status: f.normalizedStatus,
            staged: true,
          ),
        )
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleStage(String path) {
    setState(() {
      _files = _files
          .map((f) => f.path == path ? f.copyWith(staged: !f.staged) : f)
          .toList();
    });
  }

  void _stageAll() {
    setState(() {
      _files = _files.map((f) => f.copyWith(staged: true)).toList();
    });
  }

  void _unstageAll() {
    setState(() {
      _files = _files.map((f) => f.copyWith(staged: false)).toList();
    });
  }

  Future<void> _generateMessage() async {
    if (_generatingMessage) return;
    setState(() => _generatingMessage = true);
    try {
      final selectedPaths =
          _files.where((f) => f.staged).map((f) => f.path).toList();
      final selectedAll =
          selectedPaths.length == _files.length && _files.isNotEmpty;
      final generated = await widget
          .onGenerateMessage(selectedAll ? const <String>[] : selectedPaths);
      if (!mounted) return;
      final trimmed = generated.trim();
      if (trimmed.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未生成有效的提交信息')),
        );
        return;
      }
      _controller.text = trimmed;
      _controller.selection = TextSelection.fromPosition(
        TextPosition(offset: _controller.text.length),
      );
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('生成提交信息失败: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _generatingMessage = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedCount = _files.where((f) => f.staged).length;
    final canSubmit = _controller.text.trim().isNotEmpty &&
        (selectedCount > 0 || _files.isNotEmpty);

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Git Commit',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : Colors.black87,
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, color: Colors.grey[600]),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        maxLength: 72,
                        maxLines: 3,
                        onChanged: (_) => setState(() {}),
                        style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87),
                        decoration: InputDecoration(
                          hintText: '提交信息...',
                          hintStyle: TextStyle(color: Colors.grey[500]),
                          filled: true,
                          fillColor: isDark ? Colors.white10 : Colors.grey[100],
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                          counterText: '',
                          suffixIcon: IconButton(
                            tooltip: '生成 Commit Message',
                            onPressed:
                                _generatingMessage ? null : _generateMessage,
                            icon: _generatingMessage
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : const Icon(Icons.auto_awesome_rounded),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_files.isNotEmpty)
                        Row(
                          children: [
                            Expanded(
                                child: ActionButton(
                                    label: '全部暂存', onTap: _stageAll)),
                            const SizedBox(width: 8),
                            Expanded(
                                child: ActionButton(
                                    label: '取消暂存', onTap: _unstageAll)),
                          ],
                        ),
                      if (_files.isNotEmpty) const SizedBox(height: 12),
                      if (_files.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Text('当前没有可提交的变更文件',
                              style: TextStyle(color: Colors.grey[600])),
                        ),
                      ..._files.map((f) => _buildFileRow(context, f, isDark)),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor:
                              Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                        onPressed: canSubmit
                            ? () => widget.onConfirm(
                                  _controller.text.trim(),
                                  _files
                                      .where((f) => f.staged)
                                      .map((f) => f.path)
                                      .toList(),
                                  selectedCount == _files.length &&
                                      _files.isNotEmpty,
                                )
                            : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.commit_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text(_files.isEmpty
                                ? '提交'
                                : '提交 $selectedCount 个文件'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFileRow(
      BuildContext context, _CommitSelectionFile f, bool isDark) {
    return InkWell(
      onTap: () => _toggleStage(f.path),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: f.staged
                    ? Theme.of(context).colorScheme.primary
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: f.staged
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400]!,
                  width: 1.5,
                ),
              ),
              child: f.staged
                  ? const Icon(Icons.check, size: 12, color: Colors.white)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                f.path,
                style: TextStyle(
                  fontSize: 13,
                  fontFamily: 'monospace',
                  color: isDark ? Colors.white : Colors.black87,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              f.status,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: switch (f.status) {
                  'deleted' => GitColors.deleted,
                  'added' => GitColors.added,
                  _ => GitColors.modified,
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CommitSelectionFile {
  const _CommitSelectionFile({
    required this.path,
    required this.status,
    required this.staged,
  });

  final String path;
  final String status;
  final bool staged;

  _CommitSelectionFile copyWith({bool? staged}) {
    return _CommitSelectionFile(
      path: path,
      status: status,
      staged: staged ?? this.staged,
    );
  }
}
