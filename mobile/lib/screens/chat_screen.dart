import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../config.dart';
import '../models/models.dart';
import '../services/api.dart';
import '../utils/format.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});
  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messages = <ChatMessage>[];
  final _input = TextEditingController();
  final _scroll = ScrollController();
  bool _loading = true;
  bool _sending = false;

  static const _suggestions = [
    'Sidee buu ahaa iibka toddobaadkan?',
    'Alaabtee ayaa dhammaanaysa?',
    'Yaa deyn igu leh?',
    'Faa\'iidadayda bishan waa imisa?',
    'Ii qor fariin WhatsApp oo xayeysiis ah',
    'Sidee u kordhin karaa iibkayga?',
  ];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final l = await Api.instance.get('/api/ai/history');
      _messages
        ..clear()
        ..addAll((l as List).map((e) => ChatMessage.fromJson(e)));
    } catch (_) {
      // taariikhda la'aanteed sii wad
    }
    if (mounted) setState(() => _loading = false);
    _toBottom();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.animateTo(_scroll.position.maxScrollExtent, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
    });
  }

  Future<void> _send([String? preset]) async {
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty || _sending) return;
    _input.clear();
    setState(() {
      _messages.add(ChatMessage(role: 'user', content: text));
      _sending = true;
    });
    _toBottom();
    try {
      final res = await Api.instance.post('/api/ai/chat', {'message': text}, const Duration(seconds: 90));
      final actions = (res['actions'] as List?) ?? [];
      setState(() => _messages.add(ChatMessage(role: 'assistant', content: res['reply'] ?? '')));
      if (actions.isNotEmpty && mounted) showOk(context, 'Kaaliye wuxuu cusboonaysiiyay xogtaada ✓');
    } catch (e) {
      setState(() => _messages.add(ChatMessage(role: 'assistant', content: e is ApiException ? e.message : '$e', isError: true)));
    } finally {
      if (mounted) setState(() => _sending = false);
      _toBottom();
    }
  }

  Future<void> _clear() async {
    if (!await confirm(context, 'Tirtir wada-hadalka?', 'Dhammaan fariimaha waa la tirtiri doonaa.')) return;
    try {
      await Api.instance.delete('/api/ai/history');
      setState(_messages.clear);
    } catch (e) {
      if (mounted) showError(context, e);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Row(children: [Icon(Icons.auto_awesome), SizedBox(width: 8), Text('Kaaliye AI')]),
        actions: [if (_messages.isNotEmpty) IconButton(onPressed: _clear, icon: const Icon(Icons.delete_sweep_outlined), tooltip: 'Tirtir')],
      ),
      body: Column(children: [
        if (AppConfig.useMock)
          Container(
            width: double.infinity,
            color: cs.tertiaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Demo mode: jawaabuhu waa tusaale ku salaysan xogtaada. AI-ga dhabta ah waxaa lagu xiri doonaa qaybta backend-ka.',
              style: TextStyle(color: cs.onTertiaryContainer, fontSize: 12),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _messages.isEmpty
                  ? _welcome(context)
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.all(12),
                      itemCount: _messages.length + (_sending ? 1 : 0),
                      itemBuilder: (c, i) {
                        if (i == _messages.length) return const _Typing();
                        return _Bubble(message: _messages[i]);
                      },
                    ),
        ),
        Material(
          color: cs.surfaceContainer,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _input,
                    minLines: 1,
                    maxLines: 5,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(hintText: 'Wax i weydii...', isDense: true),
                    onSubmitted: (_) => _send(),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton.filled(
                  onPressed: _sending ? null : () => _send(),
                  icon: const Icon(Icons.send),
                ),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _welcome(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(padding: const EdgeInsets.all(24), children: [
      const SizedBox(height: 24),
      Icon(Icons.auto_awesome, size: 48, color: cs.primary),
      const SizedBox(height: 12),
      Text('Salaan! Waxaan ahay Kaaliyahaaga ganacsiga.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.titleMedium),
      const SizedBox(height: 6),
      Text('Wax iga weydii iibkaaga, stock-ga, macaamiisha, ama ii sheeg inaan kharash diiwaangeliyo.',
          textAlign: TextAlign.center, style: TextStyle(color: cs.onSurfaceVariant)),
      const SizedBox(height: 24),
      Wrap(
        spacing: 8,
        runSpacing: 8,
        alignment: WrapAlignment.center,
        children: _suggestions.map((s) => ActionChip(label: Text(s), onPressed: () => _send(s))).toList(),
      ),
    ]);
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  const _Bubble({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final user = message.isUser;
    final bg = message.isError ? cs.errorContainer : (user ? cs.primary : cs.surfaceContainerHigh);
    final fg = message.isError ? cs.onErrorContainer : (user ? cs.onPrimary : cs.onSurface);
    return Align(
      alignment: user ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: () {
          Clipboard.setData(ClipboardData(text: message.content));
          showOk(context, 'Waa la koobiyeeyay');
        },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.82),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(user ? 18 : 4),
              bottomRight: Radius.circular(user ? 4 : 18),
            ),
          ),
          child: _RichText(text: message.content, color: fg),
        ),
      ),
    );
  }
}

/// Markdown fudud: **bold** iyo liisas "- " — package la'aan.
class _RichText extends StatelessWidget {
  final String text;
  final Color color;
  const _RichText({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    final base = TextStyle(color: color, height: 1.35, fontSize: 15);
    final lines = text.split('\n');
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          for (var i = 0; i < lines.length; i++) ...[
            ..._parseLine(lines[i].replaceFirstMapped(RegExp(r'^\s*[-*]\s+'), (_) => '•  ').replaceFirst(RegExp(r'^#{1,6}\s+'), '')),
            if (i < lines.length - 1) const TextSpan(text: '\n'),
          ],
        ],
      ),
    );
  }

  List<TextSpan> _parseLine(String line) {
    final spans = <TextSpan>[];
    final re = RegExp(r'\*\*(.+?)\*\*');
    var last = 0;
    for (final m in re.allMatches(line)) {
      if (m.start > last) spans.add(TextSpan(text: line.substring(last, m.start)));
      spans.add(TextSpan(text: m.group(1), style: const TextStyle(fontWeight: FontWeight.w700)));
      last = m.end;
    }
    if (last < line.length) spans.add(TextSpan(text: line.substring(last)));
    return spans;
  }
}

class _Typing extends StatelessWidget {
  const _Typing();
  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: Theme.of(context).colorScheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(18)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            SizedBox(width: 10),
            Text('Kaaliye wuu fekerayaa...'),
          ]),
        ),
      );
}
