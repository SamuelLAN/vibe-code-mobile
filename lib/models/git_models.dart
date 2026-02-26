class GitCommit {
  GitCommit({
    required this.hash,
    required this.message,
    required this.date,
    this.author,
  });

  final String hash;
  final String message;
  final DateTime date;
  final String? author;

  String get shortHash => hash.length <= 7 ? hash : hash.substring(0, 7);
}

class GitOperationResult {
  GitOperationResult({
    required this.success,
    required this.message,
    this.details,
  });

  final bool success;
  final String message;
  final String? details;
}

class GitSummary {
  GitSummary({
    required this.branch,
    required this.aheadCount,
    required this.behindCount,
    required this.changedFileCount,
    required this.runningTaskCount,
  });

  final String branch;
  final int aheadCount;
  final int behindCount;
  final int changedFileCount;
  final int runningTaskCount;
}

class GitPushSummary {
  GitPushSummary({
    required this.branch,
    required this.aheadCount,
    this.remote = 'origin',
    this.remoteBranch,
  });

  final String branch;
  final int aheadCount;
  final String remote;
  final String? remoteBranch;
}

class GitRunTask {
  GitRunTask({
    required this.taskName,
    this.command,
    this.status,
    this.pid,
  });

  final String taskName;
  final String? command;
  final String? status;
  final int? pid;
}

class GitRunStatus {
  GitRunStatus({
    required this.runningTaskCount,
    required this.tasks,
  });

  final int runningTaskCount;
  final List<GitRunTask> tasks;
}

class GitWorktreeFile {
  GitWorktreeFile({
    required this.path,
    required this.statusCode,
  });

  final String path;
  final String statusCode;

  String get normalizedStatus {
    switch (statusCode.toUpperCase()) {
      case 'A':
        return 'added';
      case 'D':
        return 'deleted';
      case 'R':
        return 'renamed';
      case 'C':
        return 'copied';
      case 'U':
        return 'unmerged';
      case '?':
        return 'untracked';
      case 'M':
      default:
        return 'modified';
    }
  }
}

class GitWorktreeStatus {
  GitWorktreeStatus({
    required this.files,
    Map<String, int>? counts,
  }) : counts = counts ?? const {};

  final List<GitWorktreeFile> files;
  final Map<String, int> counts;
}
