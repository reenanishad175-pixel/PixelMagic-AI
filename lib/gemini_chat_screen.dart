// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:convert';
import 'package:speech_to_text/speech_to_text.dart' as stt;

class GeminiChatScreen extends StatefulWidget {
  const GeminiChatScreen({super.key});
  @override
  State<GeminiChatScreen> createState() => _GeminiChatScreenState();
}

class _GeminiChatScreenState extends State<GeminiChatScreen> {
  final input = TextEditingController();
  final scroll = ScrollController();
  final List<Map<String, String>> messages = [];
  bool busy = false, loading = true, speechAvailable = false, listening = false;
  final stt.SpeechToText speech = stt.SpeechToText();
  String? error;
  String get storageKey => 'gemini_chat_${Supabase.instance.client.auth.currentUser?.id ?? 'guest'}';

  @override
  void initState() { super.initState(); _loadHistory(); _initSpeech(); }

  Future<void> _initSpeech() async {
    try {
      final available = await speech.initialize(
        onStatus: (status) { if (mounted) setState(() => listening = status == 'listening'); },
        onError: (e) { if (mounted) setState(() { listening = false; error = e.errorMsg; }); },
      );
      if (mounted) setState(() => speechAvailable = available);
    } catch (_) {
      if (mounted) setState(() => speechAvailable = false);
    }
  }

  Future<void> _toggleListening() async {
    if (busy) return;
    final localeId = Localizations.localeOf(context).languageCode == 'hi'
        ? 'hi_IN'
        : 'en_IN';
    if (speech.isListening) {
      await speech.stop();
      if (mounted) setState(() => listening = false);
      return;
    }
    if (!speechAvailable) {
      await _initSpeech();
    }
    if (!speechAvailable) {
      if (mounted) {
        setState(() => error = 'Voice input is unavailable. Please enable a speech recognition service or Google app microphone permission.');
      }
      return;
    }
    if (mounted) setState(() => error = null);
    await speech.listen(
      localeId: localeId,
      listenFor: const Duration(minutes: 1),
      pauseFor: const Duration(seconds: 4),
      onResult: (result) {
        if (mounted) setState(() {
          input.value = TextEditingValue(
            text: result.recognizedWords,
            selection: TextSelection.collapsed(offset: result.recognizedWords.length),
          );
        });
      },
    );
    if (mounted) setState(() => listening = speech.isListening);
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is List) { messages.addAll(decoded.whereType<Map>().map((m) => {
          'role': (m['role'] ?? 'user').toString(), 'text': (m['text'] ?? '').toString(),
        })); }
      }
    } catch (_) {}
    if (mounted) setState(() => loading = false);
    _scrollToBottom();
  }

  Future<void> _saveHistory() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(storageKey, jsonEncode(messages));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) { scroll.animateTo(scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250), curve: Curves.easeOut); }
    });
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (busy || text.isEmpty) return;
    final history = messages.map((m) => {'role': m['role'], 'text': m['text']}).toList();
    setState(() { busy = true; error = null; messages.add({'role': 'user', 'text': text}); });
    input.clear(); _scrollToBottom();
    try {
      final response = await Supabase.instance.client.functions.invoke('pixelmagic-ai',
        body: {'task': 'gemini_chat', 'prompt': text, 'history': history});
      if (response.status < 200 || response.status >= 300 || response.data is! Map) {
        final data = response.data;
        throw Exception(data is Map ? (data['error'] ?? 'Gemini request failed').toString() : 'Gemini request failed (${response.status})');
      }
      final answer = (response.data['text'] ?? '').toString().trim();
      if (answer.isEmpty) throw Exception('Gemini returned an empty answer.');
      if (mounted) setState(() => messages.add({'role': 'model', 'text': answer}));
      await _saveHistory();
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
      if (mounted) await _saveHistory();
    } finally {
      if (mounted) setState(() => busy = false);
      _scrollToBottom();
    }
  }

  Future<void> _newChat() async {
    if (busy) return;
    setState(() { messages.clear(); error = null; });
    await _saveHistory();
  }

  @override
  void dispose() { speech.stop(); input.dispose(); scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Gemini AI Chat'), actions: [
      IconButton(tooltip: 'New chat', onPressed: busy ? null : _newChat, icon: const Icon(Icons.add_comment_outlined)),
    ]),
    body: Column(children: [
      Expanded(child: loading ? const Center(child: CircularProgressIndicator()) :
        messages.isEmpty ? const Center(child: Padding(padding: EdgeInsets.all(28), child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.auto_awesome, size: 54, color: Color(0xFF55DCCB)),
            SizedBox(height: 14),
            Text('Ask Gemini anything', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 6),
            Text('Chat in Hindi or English. Your recent conversation is saved on this device.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60)),
          ],
        ))) : ListView.builder(controller: scroll, padding: const EdgeInsets.all(14),
          itemCount: messages.length + (busy ? 1 : 0),
          itemBuilder: (context, index) {
            if (index == messages.length) { return const Align(alignment: Alignment.centerLeft, child: Padding(
              padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))); }
            final item = messages[index];
            final user = item['role'] == 'user';
            return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft, child: Container(
              constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * .84),
              margin: const EdgeInsets.symmetric(vertical: 5), padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(color: user ? const Color(0xFF155B5A) : const Color(0xFF172334), borderRadius: BorderRadius.circular(16)),
              child: SelectableText(item['text'] ?? '', style: const TextStyle(height: 1.4))));
          })),
      if (error != null) Padding(padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
        child: Text(error!, style: const TextStyle(color: Colors.redAccent, fontSize: 12))),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(controller: input, minLines: 1, maxLines: 5, maxLength: 8000,
            decoration: const InputDecoration(hintText: 'Message Gemini…', counterText: '', contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
            onSubmitted: (_) => _send())),
          const SizedBox(width: 4),
          IconButton(
            tooltip: listening ? 'Stop voice input' : 'Speak to Gemini',
            onPressed: busy ? null : _toggleListening,
            icon: Icon(listening ? Icons.mic : Icons.mic_none_rounded,
              color: listening ? Colors.redAccent : (speechAvailable ? const Color(0xFF55DCCB) : null)),
          ),
          IconButton.filled(onPressed: busy ? null : _send, icon: const Icon(Icons.send_rounded)),
        ]))),
    ]),
  );
}
