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
  bool _advancedOpen = false;

  Future<void> _showResult(GitOperationResult result) async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.message + (result.details == null ? '' : ' ${result.details}')),
        backgroundColor: result.success ? Colors.green : Colors.red,
      ),
    );
  }

  Future<void> _openCommitDialog(GitService git) async {
    final files = await git.status();
    final controller = TextEditingController();
    final selected = <String>{...files};

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Commit changes'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller,
                  decoration: const InputDecoration(labelText: 'Commit message'),
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text('Changed files', style: Theme.of(context).textTheme.labelLarge),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: files
                        .map(
                          (file) => CheckboxListTile(
                            value: selected.contains(file),
                            title: Text(file),
                            onChanged: (value) {
                              if (value == true) {
                                selected.add(file);
                              } else {
                                selected.remove(file);
                              }
                              setLocal(() {});
                            },
                          ),
                        )
                        .toList(),
                  ),
                ),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        selected
                          ..clear()
                          ..addAll(files);
                        setLocal(() {});
                      },
                      child: const Text('Stage All'),
                    ),
                    TextButton(
                      onPressed: () {
                        selected.clear();
                        setLocal(() {});
                      },
                      child: const Text('Unstage All'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(context).pop();
                final result = await git.commit(
                  message: controller.text.trim(),
                  files: selected.toList(),
                );
                await _showResult(result);
              },
              child: const Text('Commit'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openResetDialog(GitService git) async {
    final commits = await git.log();
    GitCommit? selected = commits.first;
    String mode = 'mixed';

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Reset to commit'),
          content: SizedBox(
            width: 320,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: commits.length,
                    itemBuilder: (context, index) {
                      final commit = commits[index];
                      return RadioListTile<GitCommit>(
                        value: commit,
                        groupValue: selected,
                        title: Text('${commit.hash} • ${commit.message}'),
                        subtitle: Text(commit.date.toLocal().toString()),
                        onChanged: (value) {
                          selected = value;
                          setLocal(() {});
                        },
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                DropdownButtonFormField<String>(
                  value: mode,
                  items: const [
                    DropdownMenuItem(value: 'soft', child: Text('Soft reset')),
                    DropdownMenuItem(value: 'mixed', child: Text('Mixed reset')),
                    DropdownMenuItem(value: 'hard', child: Text('Hard reset')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      mode = value;
                      setLocal(() {});
                    }
                  },
                  decoration: const InputDecoration(labelText: 'Reset mode'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                if (mode == 'hard') {
                  final confirm = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Confirm hard reset'),
                      content: const Text('Hard reset will discard local changes.'),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                        ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Reset')),
                      ],
                    ),
                  );
                  if (confirm != true) return;
                }
                Navigator.of(context).pop();
                final result = await git.reset(hash: selected!.hash, mode: mode);
                await _showResult(result);
              },
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openConfigureDialog(SettingsService settings) async {
    final baseUrlController = TextEditingController(text: await settings.getGitBaseUrl() ?? '');
    final repoController = TextEditingController(text: await settings.getGitRepoPath() ?? '');
    final tokenController = TextEditingController(text: await settings.getGitToken() ?? '');
    bool mockMode = await settings.getGitMockMode();

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: const Text('Git configuration'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: baseUrlController,
                decoration: const InputDecoration(labelText: 'Git backend base URL'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: repoController,
                decoration: const InputDecoration(labelText: 'Repository path'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: tokenController,
                decoration: const InputDecoration(labelText: 'Access token (optional)'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: mockMode,
                onChanged: (value) => setLocal(() => mockMode = value),
                title: const Text('Use mock git responses'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async {
                await settings.setGitBaseUrl(baseUrlController.text);
                await settings.setGitRepoPath(repoController.text);
                await settings.setGitToken(tokenController.text);
                await settings.setGitMockMode(mockMode);
                if (mounted) Navigator.of(context).pop();
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final git = context.watch<GitService>();
    final settings = context.read<SettingsService>();

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text('Git Operations', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text('Pull'),
              onTap: git.isBusy
                  ? null
                  : () async {
                      final result = await git.pull();
                      await _showResult(result);
                    },
            ),
            ListTile(
              leading: const Icon(Icons.update),
              title: const Text('Reset'),
              onTap: git.isBusy ? null : () async => _openResetDialog(git),
            ),
            ListTile(
              leading: const Icon(Icons.check_circle_outline),
              title: const Text('Commit'),
              onTap: git.isBusy ? null : () async => _openCommitDialog(git),
            ),
            ListTile(
              leading: const Icon(Icons.upload),
              title: const Text('Push'),
              onTap: git.isBusy
                  ? null
                  : () async {
                      final summary = await git.getPushSummary();
                      if (!mounted) return;
                      final confirm = await showDialog<bool>(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: const Text('Confirm push'),
                          content: Text(
                            'Push ${summary.aheadCount} commit(s) to ${summary.branch}?',
                          ),
                          actions: [
                            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
                            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Push')),
                          ],
                        ),
                      );
                      if (confirm != true) return;
                      final result = await git.push();
                      await _showResult(result);
                    },
            ),
            const Divider(height: 24),
            ListTile(
              leading: Icon(_advancedOpen ? Icons.expand_less : Icons.expand_more),
              title: const Text('Advanced'),
              onTap: () => setState(() => _advancedOpen = !_advancedOpen),
            ),
            if (_advancedOpen) ...[
              ListTile(
                leading: const Icon(Icons.playlist_add),
                title: const Text('Status'),
                onTap: () async {
                  final files = await git.status();
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Working tree status'),
                      content: SizedBox(
                        width: 320,
                        child: ListView(
                          shrinkWrap: true,
                          children: files.map((file) => Text(file)).toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('Log'),
                onTap: () async {
                  final commits = await git.log();
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Recent commits'),
                      content: SizedBox(
                        width: 320,
                        child: ListView(
                          shrinkWrap: true,
                          children: commits
                              .map(
                                (commit) => ListTile(
                                  title: Text(commit.message),
                                  subtitle: Text('${commit.hash} • ${commit.date.toLocal()}'),
                                ),
                              )
                              .toList(),
                        ),
                      ),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.archive_outlined),
                title: const Text('Stash'),
                onTap: () async {
                  final result = await git.stash();
                  await _showResult(result);
                },
              ),
              ListTile(
                leading: const Icon(Icons.unarchive_outlined),
                title: const Text('Stash Pop'),
                onTap: () async {
                  final result = await git.stashPop();
                  await _showResult(result);
                },
              ),
              ListTile(
                leading: const Icon(Icons.call_split),
                title: const Text('Checkout branch'),
                onTap: () async {
                  final controller = TextEditingController();
                  if (!mounted) return;
                  await showDialog<void>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text('Checkout branch'),
                      content: TextField(
                        controller: controller,
                        decoration: const InputDecoration(labelText: 'Branch name'),
                      ),
                      actions: [
                        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.of(context).pop();
                            final result = await git.checkout(branch: controller.text.trim());
                            await _showResult(result);
                          },
                          child: const Text('Checkout'),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ],
            const Divider(height: 24),
            ListTile(
              leading: const Icon(Icons.settings),
              title: const Text('Configure Git'),
              onTap: () => _openConfigureDialog(settings),
            ),
          ],
        ),
      ),
    );
  }
}
