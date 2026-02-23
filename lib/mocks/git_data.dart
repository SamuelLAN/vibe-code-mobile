class GitFileChange {
  GitFileChange({
    required this.path,
    required this.status,
    this.staged = false,
  });

  final String path;
  final String status; // 'added', 'modified', 'deleted'
  final bool staged;
}

class GitCommit {
  GitCommit({
    required this.hash,
    required this.shortHash,
    required this.message,
    required this.author,
    required this.date,
  });

  final String hash;
  final String shortHash;
  final String message;
  final String author;
  final String date;
}

const String currentBranch = 'main';
const int commitsAhead = 3;

final List<GitFileChange> mockFileChanges = [
  GitFileChange(path: 'lib/screens/chat_screen.dart', status: 'modified', staged: true),
  GitFileChange(path: 'lib/widgets/input_bar.dart', status: 'modified', staged: false),
  GitFileChange(path: 'lib/models/message.dart', status: 'added', staged: true),
  GitFileChange(path: 'assets/logo.png', status: 'deleted', staged: false),
];

final List<GitCommit> mockCommits = [
  GitCommit(
    hash: 'a1b2c3d4e5f6g7h8i9j0',
    shortHash: 'a1b2c3d',
    message: 'Add chat history persistence',
    author: 'Dev',
    date: '2 hours ago',
  ),
  GitCommit(
    hash: 'b2c3d4e5f6g7h8i9j0k1',
    shortHash: 'b2c3d4e',
    message: 'Implement voice input mode',
    author: 'Dev',
    date: '5 hours ago',
  ),
  GitCommit(
    hash: 'c3d4e5f6g7h8i9j0k1l2',
    shortHash: 'c3d4e5f',
    message: 'Add attachment support',
    author: 'Dev',
    date: '1 day ago',
  ),
  GitCommit(
    hash: 'd4e5f6g7h8i9j0k1l2m3',
    shortHash: 'd4e5f6g',
    message: 'Initial commit',
    author: 'Dev',
    date: '2 days ago',
  ),
];

final List<String> mockBranches = [
  'main',
  'develop',
  'feature/voice-input',
  'bugfix/chat-scroll',
];
