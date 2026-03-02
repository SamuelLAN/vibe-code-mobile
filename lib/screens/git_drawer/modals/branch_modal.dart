import 'package:flutter/material.dart';

import '../../../models/git_models.dart';

class BranchModal extends StatefulWidget {
  const BranchModal({
    super.key,
    required this.branches,
    required this.currentBranch,
    required this.onCheckout,
    required this.onCreateLocalBranch,
  });

  final List<GitBranchRef> branches;
  final String currentBranch;
  final Future<void> Function(GitBranchRef branch) onCheckout;
  final Future<void> Function(String newBranchName, GitBranchRef fromBranch)
      onCreateLocalBranch;

  @override
  State<BranchModal> createState() => _BranchModalState();
}

class _BranchModalState extends State<BranchModal> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _newBranchController = TextEditingController();

  String _search = '';
  GitBranchRef? _sourceBranch;

  @override
  void initState() {
    super.initState();
    _sourceBranch = _pickInitialSource(widget.branches, widget.currentBranch);
    _searchController.addListener(() {
      setState(() => _search = _searchController.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _newBranchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final filtered = _filteredBranches(widget.branches, _search);
    final locals = filtered
        .where((item) => item.type == GitBranchType.local)
        .toList(growable: false);
    final remotes = filtered
        .where((item) => item.type == GitBranchType.remote)
        .toList(growable: false);

    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _DragHandle(),
              _ModalHeader(title: 'Checkout Branch'),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: _BranchCreateCard(
                  controller: _newBranchController,
                  sourceBranch: _sourceBranch,
                  sourceCandidates: widget.branches,
                  onSourceChanged: (value) =>
                      setState(() => _sourceBranch = value),
                  onCreate: () async {
                    final source = _sourceBranch;
                    final name = _newBranchController.text.trim();
                    if (source == null || name.isEmpty) return;
                    await widget.onCreateLocalBranch(name, source);
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search branches',
                    prefixIcon: const Icon(Icons.search),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView(
                  children: [
                    _BranchSection(
                      title: 'Local branches',
                      emptyLabel: 'No local branches',
                      branches: locals,
                      currentBranch: widget.currentBranch,
                      onCheckout: widget.onCheckout,
                    ),
                    _BranchSection(
                      title: 'Remote branches',
                      emptyLabel: 'No remote branches',
                      branches: remotes,
                      currentBranch: widget.currentBranch,
                      onCheckout: widget.onCheckout,
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  GitBranchRef? _pickInitialSource(
      List<GitBranchRef> branches, String current) {
    for (final item in branches) {
      if (item.type == GitBranchType.local && item.name == current) return item;
    }
    for (final item in branches) {
      if (item.type == GitBranchType.local) return item;
    }
    if (branches.isEmpty) return null;
    return branches.first;
  }

  List<GitBranchRef> _filteredBranches(List<GitBranchRef> branches, String q) {
    if (q.isEmpty) return branches;
    return branches.where((item) {
      return item.name.toLowerCase().contains(q) ||
          item.fullName.toLowerCase().contains(q) ||
          (item.remoteName ?? '').toLowerCase().contains(q);
    }).toList(growable: false);
  }
}

class _BranchCreateCard extends StatelessWidget {
  const _BranchCreateCard({
    required this.controller,
    required this.sourceBranch,
    required this.sourceCandidates,
    required this.onSourceChanged,
    required this.onCreate,
  });

  final TextEditingController controller;
  final GitBranchRef? sourceBranch;
  final List<GitBranchRef> sourceCandidates;
  final ValueChanged<GitBranchRef?> onSourceChanged;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final branchOptions = sourceCandidates
        .where((item) => item.type == GitBranchType.local || item.isRemote)
        .toList(growable: false);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Create local branch',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<GitBranchRef>(
            initialValue:
                sourceBranch != null && branchOptions.contains(sourceBranch)
                    ? sourceBranch
                    : null,
            isExpanded: true,
            items: branchOptions
                .map((item) => DropdownMenuItem<GitBranchRef>(
                      value: item,
                      child: Text(
                        item.isRemote ? item.fullName : item.name,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ))
                .toList(growable: false),
            onChanged: onSourceChanged,
            decoration: const InputDecoration(
              labelText: 'From',
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            decoration: const InputDecoration(
              labelText: 'New branch name',
              hintText: 'feature/xxx',
              isDense: true,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add),
              label: const Text('Create and checkout'),
            ),
          ),
        ],
      ),
    );
  }
}

class _BranchSection extends StatelessWidget {
  const _BranchSection({
    required this.title,
    required this.emptyLabel,
    required this.branches,
    required this.currentBranch,
    required this.onCheckout,
  });

  final String title;
  final String emptyLabel;
  final List<GitBranchRef> branches;
  final String currentBranch;
  final Future<void> Function(GitBranchRef branch) onCheckout;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          if (branches.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Text(
                emptyLabel,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
          ...branches.map((branch) {
            final isCurrent = branch.type == GitBranchType.local &&
                branch.name == currentBranch;
            return InkWell(
              onTap: isCurrent ? null : () => onCheckout(branch),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isDark ? Colors.white12 : Colors.black12,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      branch.type == GitBranchType.remote
                          ? Icons.cloud_queue_rounded
                          : Icons.account_tree_rounded,
                      size: 18,
                      color: isCurrent
                          ? Theme.of(context).colorScheme.primary
                          : Colors.grey[500],
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        branch.type == GitBranchType.remote
                            ? branch.fullName
                            : branch.name,
                        style: TextStyle(
                          color: isCurrent
                              ? Theme.of(context).colorScheme.primary
                              : (isDark ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                    if (isCurrent)
                      _Pill(
                        label: 'Current',
                        color: Theme.of(context).colorScheme.primary,
                      )
                    else
                      const Icon(Icons.chevron_right_rounded),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}

class _DragHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 4,
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: Colors.grey[400],
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _ModalHeader extends StatelessWidget {
  const _ModalHeader({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 12, 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
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
    );
  }
}
