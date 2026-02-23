import 'package:flutter/material.dart';

import '../../../../constants/colors.dart';
import '../../../../mocks/git_data.dart';
import '../widgets/widgets.dart';

class CommitModal extends StatefulWidget {
  final Function(String message, List<GitFileChange> files) onConfirm;

  const CommitModal({super.key, required this.onConfirm});

  @override
  State<CommitModal> createState() => _CommitModalState();
}

class _CommitModalState extends State<CommitModal> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  late List<GitFileChange> _files;

  @override
  void initState() {
    super.initState();
    _files = mockFileChanges
        .map((f) => GitFileChange(path: f.path, status: f.status, staged: f.staged))
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
      _files = _files.map((f) {
        if (f.path == path) {
          return GitFileChange(path: f.path, status: f.status, staged: !f.staged);
        }
        return f;
      }).toList();
    });
  }

  void _stageAll() {
    setState(() {
      _files = _files
          .map((f) => GitFileChange(path: f.path, status: f.status, staged: true))
          .toList();
    });
  }

  void _unstageAll() {
    setState(() {
      _files = _files
          .map((f) => GitFileChange(path: f.path, status: f.status, staged: false))
          .toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
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
                        style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: ActionButton(label: '全部暂存', onTap: _stageAll),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ActionButton(label: '取消暂存', onTap: _unstageAll),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      ..._files.map((f) => InkWell(
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
                                      color: f.status == 'deleted'
                                          ? GitColors.deleted
                                          : f.status == 'added'
                                              ? GitColors.added
                                              : GitColors.modified,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.primary,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        onPressed: _controller.text.trim().isNotEmpty
                            ? () => widget.onConfirm(
                                _controller.text.trim(), _files.where((f) => f.staged).toList())
                            : null,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.commit_rounded, size: 18),
                            const SizedBox(width: 8),
                            Text('提交 ${_files.where((f) => f.staged).length} 个文件'),
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
}
