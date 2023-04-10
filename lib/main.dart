import "dart:convert";
import 'package:path/path.dart';
import "dart:io";
import 'package:sembast/sembast.dart';
import 'package:sembast/sembast_io.dart';

// import "package:file_picker/file_picker.dart";
import "package:flag/flag.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:flutter_chat_types/flutter_chat_types.dart" as types;
import "package:flutter_chat_ui/flutter_chat_ui.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:get_it/get_it.dart";
import "package:http/http.dart" as http;
import "package:intl/date_symbol_data_local.dart";
import "package:path_provider/path_provider.dart";
import "package:uuid/uuid.dart";

Future main() async {
  await dotenv.load(fileName: ".env", mergeWith: Platform.environment);
  initializeDateFormatting().then((_) => runApp(const MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => const MaterialApp(
        home: ChatPage(),
        debugShowCheckedModeBanner: false,
      );
}

class ChatPage extends StatefulWidget {
  const ChatPage({super.key});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final List<types.Message> _messages = [];
  bool isWaitingForGPT = false;
  final _user = const types.User(id: "user");
  final _gpt = const types.User(
      id: "gpt",
      firstName: 'GPT',
      imageUrl:
          "https://upload.wikimedia.org/wikipedia/commons/thumb/0/04/ChatGPT_logo.svg/2048px-ChatGPT_logo.svg.png");

  Future<String> askGPT(String msg) async {
    final url = Uri.parse("https://api.openai.com/v1/completions");
    var header = {
      "Authorization": "Bearer ${dotenv.env["API_TOKEN"]!}",
      "Content-Type": "application/json",
    };

    var body = jsonEncode({
      "model": "text-davinci-003",
      "prompt": msg,
      "temperature": 0,
      "max_tokens": 500
    });

    try {
      final response = await http.post(url, headers: header, body: body);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        data["choices"][0]["text"] =
            data["choices"][0]["text"].toString().trim();
        return data["choices"][0]["text"];
      } else {
        return "Oops, Something Wrong!";
      }
    } catch (e) {
      return "Oops, $e";
    }
  }

  @override
  void initState() {
    super.initState();
    _loadMessages();
  }

  ChatTheme theme = const DarkChatTheme();
  bool isVn = false;
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          backgroundColor: theme.inputBackgroundColor,
          leading: IconButton(
            icon: Icon(Icons.delete_forever_rounded,
                color: theme.errorColor, size: 40),
            onPressed: _clearMessages,
          ),
          actions: [
            GestureDetector(
                onTap: () {
                  setState(() {
                    isVn = !isVn;
                  });
                  // chatController.addChat();
                },
                child: Flag.fromString(
                  isVn ? 'vn' : 'us',
                  width: 50,
                )),
            const SizedBox(width: 16),
          ],
          centerTitle: true,
          titleSpacing: 0,
        ),
        body: Chat(
          messages: _messages,
          // onAttachmentPressed: _handleAttachmentPressed,
          inputOptions: InputOptions(
              sendButtonVisibilityMode: SendButtonVisibilityMode.always),
          theme: theme,
          onMessageTap: _handleMessageTap,
          onPreviewDataFetched: _handlePreviewDataFetched,
          onSendPressed: _handleSendPressed,
          showUserAvatars: true,
          showUserNames: true,
          user: _user,
          l10n: isVn ? const ChatL10nVi() : const ChatL10nEn(),
          typingIndicatorOptions: TypingIndicatorOptions(
              typingUsers: isWaitingForGPT ? [_gpt] : []),
        ),
      );

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  void _addMessageReversed(types.Message message) {
    setState(() {
      _messages.insert(_messages.length, message);
    });
  }

  void _handleMessageTap(BuildContext _, types.Message message) async {
    if (message is types.FileMessage) {
      var localPath = message.uri;

      if (message.uri.startsWith("http")) {
        try {
          final index =
              _messages.indexWhere((element) => element.id == message.id);
          final updatedMessage =
              (_messages[index] as types.FileMessage).copyWith(
            isLoading: true,
          );

          setState(() {
            _messages[index] = updatedMessage;
          });

          final client = http.Client();
          final request = await client.get(Uri.parse(message.uri));
          final bytes = request.bodyBytes;
          // final documentsDir = (await getApplicationDocumentsDirectory()).path;
          // localPath = "$documentsDir/${message.name}";

          if (!File(localPath).existsSync()) {
            final file = File(localPath);
            await file.writeAsBytes(bytes);
          }
        } finally {
          final index =
              _messages.indexWhere((element) => element.id == message.id);
          final updatedMessage =
              (_messages[index] as types.FileMessage).copyWith(
            isLoading: null,
          );

          setState(() {
            _messages[index] = updatedMessage;
          });
        }
      }

      // await OpenFilex.open(localPath);
    }
  }

  void _handlePreviewDataFetched(
    types.TextMessage message,
    types.PreviewData previewData,
  ) {
    final index = _messages.indexWhere((element) => element.id == message.id);
    final updatedMessage = (_messages[index] as types.TextMessage).copyWith(
      previewData: previewData,
    );

    setState(() {
      _messages[index] = updatedMessage;
    });
  }

  _handleSendPressed(types.PartialText message) async {
    final textMessage = types.TextMessage(
      author: _user,
      createdAt: DateTime.now().millisecondsSinceEpoch,
      id: const Uuid().v4(),
      text: message.text,
    );
    _addMessage(textMessage);

    setState(() {
      isWaitingForGPT = true;
    });

    final answer = await askGPT(message.text);
    final answerMessage = types.TextMessage(
      id: const Uuid().v4(),
      author: _gpt,
      text: answer,
      createdAt: DateTime.now().millisecondsSinceEpoch,
    );

    setState(() {
      isWaitingForGPT = false;
    });

    _addMessage(answerMessage);
    _saveMessages();
  }

  void _saveMessages() async {
    var dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    var dbPath = join(dir.path, 'chat.db');
    var db = await databaseFactoryIo.openDatabase(dbPath);
    var store = StoreRef.main();
    String jsonString = jsonEncode(_messages);
    await store.record('chat').put(db, jsonString);
    await db.close();
  }

  void _loadMessages() async {
    var dir = await getApplicationDocumentsDirectory();
    await dir.create(recursive: true);
    var dbPath = join(dir.path, 'chat.db');
    var db = await databaseFactoryIo.openDatabase(dbPath);
    var store = StoreRef.main();
    var chat = await store.record('chat').get(db);
    var messages = jsonDecode(chat as String);
    for (var msg in messages) {
      _addMessageReversed(types.TextMessage.fromJson(msg));
    }
    await db.close();
  }

  void _clearMessages() {
    setState(() {
      _messages.removeWhere((element) => true);
    });

    _saveMessages();
  }
}
