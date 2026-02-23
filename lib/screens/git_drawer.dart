import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/git_models.dart';
import '../services/git_service.dart';
import '../services/settings_service.dart';

class GitDrawer extends StatefulWidget {
  const GitDrawer({super.key});

  @override
  State<GitDrawer> createState() => _GitDrawerState();
}

class _GitDrawerState extends State<GitDrawer> {
  List<String> _branches = [];
  String _currentBranch = 'main';
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadBranches();
  }

  Future<void> _loadBranches() async {
    final git = context.read<GitService>();
    setState(() => _isLoading = true);
    try {
      final branches = await git.getBranches();
      final currentBranch = await git.getCurrentBranch();
      if (mounted) {
        setState(() {
          _branches = branches;
          _currentBranch = currentBranch;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load branches: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _showResult(GitOperationResult result) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message + (result.details == null ? '' : ' ${result.details}')),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
    if (result.success) {
      await _loadBranches();
    }
  }

  Future<void> _createBranch() async {
    final git = context.read<GitService>();
    final controller = TextEditingController();

    if (!mounted) return;
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建分支'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '分支名称',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(controller.text.trim()),
            child: const Text('创建'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      final opResult = await git.createBranch(name: result);
      await _showResult(opResult);
    }
  }

  Future<void> _deleteBranch(String branchName) async {
    final git = context.read<GitService>();

    if (!mounted) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除分支'),
        content: Text('确定要删除分支 "$branchName" 吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final opResult = await git.deleteBranch(name: branchName);
      await _showResult(opResult);
    }
  }

  Future<void> _switchBranch(String branchName) async {
    final git = context.read<GitService>();
    final opResult = await git.checkout(branch: branchName);
    await _showResult(opResult);
  }

  void _showBranchOptions(String branchName) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('切换分支'),
              onTap: () {
                Navigator.of(context).pop();
                _switchBranch(branchName);
              },
            ),
            if (branchName != _currentBranch)
              ListTile(
                leading: const Icon(Icons.merge_type),
                title: const Text('合并到当前分支'),
                onTap: () {
                  Navigator.of(context).pop();
                  _mergeBranch(branchName);
                },
              ),
            if (branchName != 'main' && branchName != _currentBranch)
              ListTile(
                leading: const Icon(Icons.delete_outline, color: Colors.red),
                title: const Text('删除分支', style: TextStyle(color: Colors.red)),
                onTap: () {
                  Navigator.of(context).pop();
                  _deleteBranch(branchName);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _mergeBranch(String sourceBranch) async {
    final git = context.read<GitService>();
    final opResult = await git.mergeBranch(source: sourceBranch, target: _currentBranch);
    await _showResult(opResult);
  }

  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.grey.withOpacity(0.2))),
              ),
              child: Row(
                children: [
                  const Text(
                    '分支',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: _isLoading ? null : _loadBranches,
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: _createBranch,
                  ),
                ],
              ),
            ),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey.withOpacity(0.1),
              child: Row(
                children: [
                  const Text(
                    '当前分支: ',
                    style: TextStyle(color: Colors.grey),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2196F3).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      _currentBranch,
                      style: const TextStyle(
                        color: Color(0xFF2196F3),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: _branches.length,
                      itemBuilder: (context, index) {
                        final branch = _branches[index];
                        final isCurrent = branch == _currentBranch;
                        return ListTile(
                          leading: Icon(
                            Icons.account_tree,
                            color: isCurrent ? const Color(0xFF2196F3) : Colors.grey,
                          ),
                          title: Text(
                            branch,
                            style: TextStyle(
                              color: isCurrent ? const Color(0xFF2196F3) : Colors.black87,
                              fontWeight: isCurrent ? FontWeight.w500 : FontWeight.normal,
                            ),
                          ),
                          trailing: isCurrent
                              ? const Icon(Icons.check, color: Color(0xFF2196F3), size: 20)
                              : IconButton(
                                  icon: const Icon(Icons.more_vert, size: 20),
                                  onPressed: () => _showBranchOptions(branch),
                                ),
                          onTap: isCurrent ? null : () => _switchBranch(branch),
                          onLongPress: () => _showBranchOptions(branch),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
