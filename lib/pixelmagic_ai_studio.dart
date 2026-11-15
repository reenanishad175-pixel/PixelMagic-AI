// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

class PixelMagicAiStudio extends StatefulWidget {
  const PixelMagicAiStudio({super.key});
  @override
  State<PixelMagicAiStudio> createState() => _PixelMagicAiStudioState();
}
class _PixelMagicAiStudioState extends State<PixelMagicAiStudio> {
  final prompt = TextEditingController();
  String task = 'image';
  bool busy = false;
  String? error, imageUrl, stage;
  VideoPlayerController? video;

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke('pixelmagic-ai', body: body);
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      throw Exception(data is Map ? (data['error'] ?? 'AI request failed').toString() : 'AI request failed (${response.status})');
    }
    if (response.data is! Map) throw Exception('Unexpected AI service response.');
    return Map<String, dynamic>.from(response.data as Map);
  }
  Future<void> generate() async {
    if (busy || prompt.text.trim().length < 3) return;
    setState(() { busy = true; error = null; imageUrl = null; stage = 'Submitting secure AI request…'; });
    await video?.dispose(); video = null;
    try {
      final submitted = await _call({'task': task, 'prompt': prompt.text.trim(), 'action': 'submit'});
      final id = submitted['request_id']?.toString();
      if (id == null || id.isEmpty) throw Exception('AI provider did not return a request ID.');
      Map<String, dynamic>? status;
      for (var i = 0; i < 90; i++) {
        await Future.delayed(const Duration(seconds: 4));
        status = await _call({'task': task, 'action': 'status', 'request_id': id});
        final state = (status['status'] ?? '').toString().toUpperCase();
        if (state == 'COMPLETED') break;
        if (state == 'FAILED' || state == 'CANCELLED') throw Exception(status['error']?.toString() ?? 'AI generation failed.');
        if (mounted) setState(() => stage = 'Generating with AI… (${i + 1}/90)');
      }
      if ((status?['status'] ?? '').toString().toUpperCase() != 'COMPLETED') throw Exception('Generation timed out. Try again.');
      setState(() => stage = 'Loading generated result…');
      final result = await _call({'task': task, 'action': 'result', 'request_id': id});
      if (task == 'image') {
        final images = result['images'];
        final url = images is List && images.isNotEmpty ? images.first['url']?.toString() : null;
        if (url == null) throw Exception('Image URL was not returned.');
        setState(() => imageUrl = url);
      } else {
        final data = result['video'];
        final url = data is Map ? data['url']?.toString() : null;
        if (url == null) throw Exception('Video URL was not returned.');
        final player = VideoPlayerController.networkUrl(Uri.parse(url));
        await player.initialize();
        if (!mounted) { await player.dispose(); return; }
        setState(() => video = player);
      }
      if (mounted) setState(() => stage = 'Generation complete');
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally { if (mounted) setState(() => busy = false); }
  }
  @override
  void dispose() { prompt.dispose(); video?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PixelMagic AI Studio')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Create with AI', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('AI image and video generation using the secured fal.ai service.'),
      const SizedBox(height: 18),
      SegmentedButton<String>(segments: const [
        ButtonSegment(value: 'image', label: Text('AI Image'), icon: Icon(Icons.image)),
        ButtonSegment(value: 'video', label: Text('AI Video'), icon: Icon(Icons.movie)),
      ], selected: {task}, onSelectionChanged: busy ? null : (v) => setState(() { task = v.first; imageUrl = null; video?.dispose(); video = null; })),
      const SizedBox(height: 14),
      TextField(controller: prompt, minLines: 3, maxLines: 6, maxLength: 2000, decoration: InputDecoration(labelText: task == 'image' ? 'Describe the image' : 'Describe the video')),
      FilledButton.icon(onPressed: busy ? null : generate, icon: const Icon(Icons.auto_awesome), label: Text(busy ? 'Generating…' : task == 'image' ? 'Generate image' : 'Generate video')),
      if (busy) ...[const SizedBox(height: 16), const LinearProgressIndicator(), if (stage != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(stage!))],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
      if (imageUrl != null) ...[const SizedBox(height: 18), ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(imageUrl!, errorBuilder: (_, __, ___) => const Text('Could not load generated image.'))), SelectableText(imageUrl!, style: const TextStyle(fontSize: 11))],
      if (video != null && video!.value.isInitialized) ...[const SizedBox(height: 18), AspectRatio(aspectRatio: video!.value.aspectRatio, child: VideoPlayer(video!)), FilledButton.tonalIcon(onPressed: () => setState(() => video!.value.isPlaying ? video!.pause() : video!.play()), icon: Icon(video!.value.isPlaying ? Icons.pause : Icons.play_arrow), label: const Text('Play / Pause'))],
      const SizedBox(height: 14),
      const Text('AI generations may incur fal.ai usage charges.', style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]),
  );
}