import '../models/chat.dart';
import '../models/message.dart';

class ChatRepository {
  // 硬编码示例数据
  final List<Chat> _chats = [
    Chat(
      id: '1',
      title: '欢迎对话',
      createdAt: DateTime.now().subtract(const Duration(days: 1)),
      updatedAt: DateTime.now(),
      lastMessagePreview: '你好！欢迎使用这个聊天应用',
    ),
    Chat(
      id: '2',
      title: 'Flutter 开发',
      createdAt: DateTime.now().subtract(const Duration(days: 3)),
      updatedAt: DateTime.now().subtract(const Duration(hours: 2)),
      lastMessagePreview: 'Flutter 是一个很棒的框架',
    ),
  ];

  final Map<String, List<Message>> _messages = {
    '1': [
      Message(
        id: 'm1',
        chatId: '1',
        role: MessageRole.assistant,
        content: '你好！欢迎使用这个聊天应用 👋\n\n我可以帮你：\n- 回答问题\n- 编写代码\n- 分析项目\n\n有什么我可以帮你的吗？',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
        attachments: [],
      ),
    ],
    '2': [
      Message(
        id: 'm2',
        chatId: '2',
        role: MessageRole.user,
        content: '什么是 Flutter？',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        attachments: [],
      ),
      Message(
        id: 'm3',
        chatId: '2',
        role: MessageRole.assistant,
        content: 'Flutter 是一个由 Google 开发的开源 UI 软件开发工具包。\n\n主要特点：\n- **跨平台**：一套代码同时支持 iOS、Android、Web、桌面\n- **高性能**：使用 Skia 渲染引擎\n- **热重载**：开发时实时预览修改\n- **丰富的组件**：Material Design 和 Cupertino 组件库',
        createdAt: DateTime.now().subtract(const Duration(days: 3)),
        attachments: [],
      ),
      Message(
        id: 'm4',
        chatId: '2',
        role: MessageRole.user,
        content: 'Flutter 和 React Native 哪个好？',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        attachments: [],
      ),
      Message(
        id: 'm5',
        chatId: '2',
        role: MessageRole.assistant,
        content: '两者各有优势：\n\n| 特性 | Flutter | React Native |\n|------|---------|--------------|\n| 渲染方式 | Skia 自绘 | 原生组件 |\n| 性能 | 更优 | 较好 |\n| 生态 | 增长中 | 更成熟 |\n| 学习曲线 | Dart | JavaScript |\n\n**选择建议**：\n- 如果追求极致性能，选 Flutter\n- 如果团队熟悉 JS，选 React Native',
        createdAt: DateTime.now().subtract(const Duration(hours: 2)),
        attachments: [],
      ),
    ],
  };

  Future<void> init() async {
    // 模拟异步初始化
    await Future.delayed(const Duration(milliseconds: 100));
  }

  Future<List<Chat>> getChats() async {
    return List.from(_chats)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<Chat> createChat(Chat chat) async {
    _chats.add(chat);
    _messages[chat.id] = [];
    return chat;
  }

  Future<void> updateChat(Chat chat) async {
    final index = _chats.indexWhere((c) => c.id == chat.id);
    if (index != -1) {
      _chats[index] = chat;
    }
  }

  Future<void> deleteChat(String chatId) async {
    _chats.removeWhere((c) => c.id == chatId);
    _messages.remove(chatId);
  }

  Future<List<Message>> getMessages(String chatId) async {
    return List.from(_messages[chatId] ?? []);
  }

  Future<void> addMessage(Message message) async {
    _messages.putIfAbsent(message.chatId, () => []);
    _messages[message.chatId]!.add(message);
  }

  Future<void> updateMessage(Message message) async {
    final messages = _messages[message.chatId];
    if (messages == null) return;
    
    final index = messages.indexWhere((m) => m.id == message.id);
    if (index != -1) {
      messages[index] = message;
    }
  }
}
