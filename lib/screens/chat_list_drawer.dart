import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chat_service.dart';

class ChatListDrawer extends StatelessWidget {
  const ChatListDrawer({super.key});

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
                            : () => chatService.refreshChatsFromServer(),
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
              child: ListView.separated(
                itemCount: chatService.chats.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final chat = chatService.chats[index];
                  return ListTile(
                    title: Text(chat.title),
                    subtitle:
                        Text(chat.lastMessagePreview ?? 'No messages yet'),
                    selected: chatService.activeChat?.id == chat.id,
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.edit),
                          onPressed: () async {
                            final controller =
                                TextEditingController(text: chat.title);
                            await showDialog<void>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('Rename chat'),
                                content: TextField(
                                  controller: controller,
                                  decoration: const InputDecoration(
                                      labelText: 'Chat title'),
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    child: const Text('Cancel'),
                                  ),
                                  ElevatedButton(
                                    onPressed: () async {
                                      await chatService.updateChatTitle(
                                          chat.id, controller.text);
                                      if (context.mounted) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                                    child: const Text('Save'),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () async {
                            await chatService.deleteChat(chat.id);
                          },
                        ),
                      ],
                    ),
                    onTap: () async {
                      await chatService.selectChat(chat.id);
                      Navigator.of(context).pop();
                    },
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
