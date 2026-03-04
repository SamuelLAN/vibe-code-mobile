import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_service.dart';

class ChatListDrawer extends StatelessWidget {
  const ChatListDrawer({super.key});

  Future<void> _showRenameDialog(
    BuildContext context,
    ChatService chatService, {
    required String chatId,
    required String currentTitle,
  }) async {
    final controller = TextEditingController(text: currentTitle);
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename chat'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Chat title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await chatService.updateChatTitle(chatId, controller.text);
              if (context.mounted) {
                Navigator.of(context).pop();
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _swipeActionBackground({
    required Alignment alignment,
    required Color color,
    required IconData icon,
    required String label,
  }) {
    return Container(
      color: color,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (alignment == Alignment.centerRight) ...[
            Text(label, style: const TextStyle(color: Colors.white)),
            const SizedBox(width: 8),
          ],
          Icon(icon, color: Colors.white),
          if (alignment == Alignment.centerLeft) ...[
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white)),
          ],
        ],
      ),
    );
  }

  String _displayTitle(String title) {
    final trimmed = title.trim();
    return trimmed.isEmpty ? 'New Chat' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final chatService = context.watch<ChatService>();

    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Chats', style: Theme.of(context).textTheme.titleLarge),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: chatService.isRefreshingChats
                            ? null
                            : () => chatService.refreshChatTitlesFromServer(),
                        icon: chatService.isRefreshingChats
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh),
                        tooltip: 'Refresh from server',
                      ),
                      TextButton.icon(
                        onPressed: () async {
                          await chatService.newChat();
                          Navigator.of(context).pop();
                        },
                        icon: const Icon(Icons.add),
                        label: const Text('New'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: chatService.chats.length,
                itemBuilder: (context, index) {
                  final chat = chatService.chats[index];
                  return Dismissible(
                    key: ValueKey('chat-${chat.id}'),
                    direction: DismissDirection.horizontal,
                    background: _swipeActionBackground(
                      alignment: Alignment.centerLeft,
                      color: Colors.blue,
                      icon: Icons.edit_outlined,
                      label: 'Edit',
                    ),
                    secondaryBackground: _swipeActionBackground(
                      alignment: Alignment.centerRight,
                      color: Colors.red,
                      icon: Icons.delete_outline,
                      label: 'Delete',
                    ),
                    confirmDismiss: (direction) async {
                      if (direction == DismissDirection.startToEnd) {
                        await _showRenameDialog(
                          context,
                          chatService,
                          chatId: chat.id,
                          currentTitle: _displayTitle(chat.title),
                        );
                        return false;
                      }
                      if (direction == DismissDirection.endToStart) {
                        await chatService.deleteChat(chat.id);
                        return false;
                      }
                      return false;
                    },
                    child: ListTile(
                      title: Text(
                        _displayTitle(chat.title),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      dense: true,
                      visualDensity: const VisualDensity(
                        vertical: -2,
                        horizontal: -1,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 2,
                      ),
                      minVerticalPadding: 0,
                      selected: chatService.activeChat?.id == chat.id,
                      onTap: () async {
                        await chatService.selectChat(chat.id);
                        if (context.mounted) {
                          Navigator.of(context).pop();
                        }
                      },
                    ),
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
