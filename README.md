# Vibe Coding Mobile (Flutter)

Cross-platform iOS + Android client for secure login, AI-powered chat, and Git operations.

## Setup

```bash
flutter pub get
flutter run
```

## Demo Login

The app ships with a demo login for local validation:
- Username: `vibe`
- Password: `coding123`

Replace this in `lib/services/auth_service.dart` when wiring your real auth API.

## Configuration

### Git Service
The Git drawer uses a backend service (or mock mode) to execute Git operations.
- Open the Git drawer → Configure Git
- Provide:
  - Git backend base URL (example: `http://10.0.2.2:8000` for Android emulator)
  - Repository path (server-side repo path)
  - Optional access token
- Toggle `Use mock git responses` to simulate Git without a backend

Expected Git endpoints (JSON POST):
- `/git/pull`
- `/git/push`
- `/git/commit`
- `/git/reset`
- `/git/status`
- `/git/log`
- `/git/stash`
- `/git/stash-pop`
- `/git/checkout`

Each request includes `{ repoPath: "..." }` plus operation-specific payloads.

### Speech + Attachments
- Ensure microphone permission is granted for voice input.
- Camera and photo library permissions are required for image attachments.

## Folder Structure

```
lib/
  main.dart
  models/
  screens/
  services/
  widgets/
```

## Testing

```bash
flutter test
```

## Notes
- Chat history is stored locally in SQLite.
- Sensitive values (tokens, Git credentials) are stored with `flutter_secure_storage`.
- Replace mock assistant responses in `lib/services/chat_service.dart` with your AI backend call.
