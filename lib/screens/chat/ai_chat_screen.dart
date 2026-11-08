import 'package:flutter/material.dart';

import '../../services/ai_chat_service.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final _messages = <Map<String, String>>[];
  final _service = const AiChatService();
  bool _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    _controller.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _sending = true;
    });
    _scrollToBottom();
    try {
      final reply = await _service.send(_messages.takeLast(12).toList());
      if (!mounted) return;
      setState(() => _messages.add({'role': 'assistant', 'content': reply}));
    } on AiChatException catch (error) {
      if (!mounted) return;
      setState(
        () => _messages.add({'role': 'assistant', 'content': error.message}),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToBottom();
      }
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF3F8FD),
    appBar: AppBar(
      backgroundColor: const Color(0xFFF3F8FD),
      title: const Row(
        children: [
          CircleAvatar(
            backgroundColor: Color(0xFF326D98),
            child: Icon(Icons.auto_awesome, color: Colors.white, size: 20),
          ),
          SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Assistant StudentHub',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
              ),
              Text(
                'En ligne · Pose ta question',
                style: TextStyle(fontSize: 11, color: Colors.blueGrey),
              ),
            ],
          ),
        ],
      ),
    ),
    body: Column(
      children: [
        Expanded(
          child: _messages.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.forum_outlined,
                          size: 54,
                          color: Color(0xFF326D98),
                        ),
                        SizedBox(height: 14),
                        Text(
                          'Bonjour ! Comment puis-je t’aider ?',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF102A43),
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Demande-moi de l’aide sur les annonces, les événements, ton logement ou les réclamations.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Color(0xFF52677B)),
                        ),
                      ],
                    ),
                  ),
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16),
                  itemCount: _messages.length + (_sending ? 1 : 0),
                  itemBuilder: (context, index) {
                    if (index == _messages.length) {
                      return const _ChatBubble(
                        text: 'Je réfléchis…',
                        fromUser: false,
                      );
                    }
                    final message = _messages[index];
                    return _ChatBubble(
                      text: message['content']!,
                      fromUser: message['role'] == 'user',
                    );
                  },
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    decoration: InputDecoration(
                      hintText: 'Écrire un message…',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 13,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(26),
                        borderSide: const BorderSide(color: Color(0xFFD7E3EF)),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  onPressed: _sending ? null : _send,
                  icon: const Icon(Icons.arrow_upward),
                  style: IconButton.styleFrom(
                    backgroundColor: const Color(0xFF326D98),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.text, required this.fromUser});
  final String text;
  final bool fromUser;

  @override
  Widget build(BuildContext context) => Align(
    alignment: fromUser ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * .82,
      ),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      decoration: BoxDecoration(
        color: fromUser ? const Color(0xFF326D98) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: fromUser ? null : Border.all(color: const Color(0xFFD7E3EF)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: fromUser ? Colors.white : const Color(0xFF102A43),
          height: 1.35,
        ),
      ),
    ),
  );
}

extension _TakeLast<T> on Iterable<T> {
  Iterable<T> takeLast(int count) => skip(length > count ? length - count : 0);
}
