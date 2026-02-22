class GitCommit {
  GitCommit({
    required this.hash,
    required this.message,
    required this.date,
  });

  final String hash;
  final String message;
  final DateTime date;
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

class GitPushSummary {
  GitPushSummary({required this.branch, required this.aheadCount});

  final String branch;
  final int aheadCount;
}
