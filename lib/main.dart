import "dart:convert";
import "dart:io";

// import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:flutter/services.dart" show rootBundle;
import "package:flutter_chat_types/flutter_chat_types.dart" as types;
import "package:flutter_chat_ui/flutter_chat_ui.dart";
import "package:flutter_dotenv/flutter_dotenv.dart";
import "package:get_it/get_it.dart";
import "package:http/http.dart" as http;
// import "package:image_picker/image_picker.dart";
import "package:intl/date_symbol_data_local.dart";
// import "package:mime/mime.dart";
// import "package:open_filex/open_filex.dart";
// import "package:path_provider/path_provider.dart";
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

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Chat(
          messages: _messages,
          onAttachmentPressed: _handleAttachmentPressed,
          onMessageTap: _handleMessageTap,
          onPreviewDataFetched: _handlePreviewDataFetched,
          onSendPressed: _handleSendPressed,
          showUserAvatars: true,
          showUserNames: true,
          user: _user,
          typingIndicatorOptions: TypingIndicatorOptions(
              typingUsers: isWaitingForGPT ? [_gpt] : []),
        ),
      );

  void _addMessage(types.Message message) {
    setState(() {
      _messages.insert(0, message);
    });
  }

  void _handleAttachmentPressed() {
    showModalBottomSheet<void>(
      context: context,
      builder: (BuildContext context) => SafeArea(
        child: SizedBox(
          height: 144,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // _handleImageSelection();
                },
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text("Photo"),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  // _handleFileSelection();
                },
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text("File"),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text("Cancel"),
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

  void _handleSendPressed(types.PartialText message) async {
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
  }

  void _loadMessages() async {
    // final response = await rootBundle.loadString("assets/messages.json");
    // final messages = (jsonDecode(response) as List)
    //     .map((e) => types.Message.fromJson(e as Map<String, dynamic>))
    //     .toList();

    // setState(() {
    //   _messages = messages;
    // });
  }
}
