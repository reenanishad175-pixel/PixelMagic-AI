// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'local_downloads.dart';

class PixelMagicAiStudio extends StatefulWidget {
  final String initialTask;
  const PixelMagicAiStudio({super.key, this.initialTask = 'image'});
  @override
  State<PixelMagicAiStudio> createState() => _PixelMagicAiStudioState();
}
class _PixelMagicAiStudioState extends State<PixelMagicAiStudio> {
  final prompt = TextEditingController();
  final ImagePicker picker = ImagePicker();
  XFile? sourcePhoto;
  late String task;
  bool busy = false;
  bool saving = false;
  String? error, imageUrl, stage, videoUrl;
  VideoPlayerController? video;
  String? apiStatus;

  @override
  void initState() {
    super.initState();
    task = widget.initialTask;
    checkApi();
  }

  Future<void> checkApi() async {
    try {
      final response = await Supabase.instance.client.functions.invoke('fal-key-check');
      final data = response.data;
      if (response.status == 200 && data is Map && data['configured'] == true) {
        if (mounted) setState(() => apiStatus = 'AI API connected — server key is available.');
      } else {
        final message = data is Map ? (data['message'] ?? data['error'] ?? 'API key is not configured.') : 'API key is not configured.';
        if (mounted) setState(() => apiStatus = message.toString());
      }
    } catch (e) {
      if (mounted) setState(() => apiStatus = 'API check failed: $e');
    }
  }

  Future<Map<String, dynamic>> _call(Map<String, dynamic> body) async {
    final response = await Supabase.instance.client.functions.invoke('pixelmagic-ai', body: body);
    if (response.status < 200 || response.status >= 300) {
      final data = response.data;
      throw Exception(data is Map ? (data['error'] ?? 'AI request failed').toString() : 'AI request failed (${response.status})');
    }
    if (response.data is! Map) throw Exception('Unexpected AI service response.');
    return Map<String, dynamic>.from(response.data as Map);
  }
  Future<void> chooseSourcePhoto() async {
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 90);
    if (picked != null && mounted) setState(() => sourcePhoto = picked);
  }

  Future<void> generate() async {
    if (busy || prompt.text.trim().length < 3) return;
    if (task == 'image_to_video' && sourcePhoto == null) {
      setState(() => error = 'Choose a photo first, then describe how it should move.');
      return;
    }
    setState(() { busy = true; error = null; imageUrl = null; videoUrl = null; stage = 'Preparing secure AI request…'; });
    await video?.dispose(); video = null;
    String? inputObjectPath;
    try {
      final requestBody = <String, dynamic>{
        'task': task,
        'prompt': prompt.text.trim(),
        'action': 'submit',
      };
      if (task == 'image_to_video') {
        final user = Supabase.instance.client.auth.currentUser;
        if (user == null) throw Exception('Please sign in again before generating a video.');
        final extension = sourcePhoto!.path.toLowerCase().endsWith('.png') ? 'png'
            : sourcePhoto!.path.toLowerCase().endsWith('.webp') ? 'webp' : 'jpg';
        final contentType = extension == 'png' ? 'image/png'
            : extension == 'webp' ? 'image/webp' : 'image/jpeg';
        inputObjectPath = '${user.id}/photo_${DateTime.now().millisecondsSinceEpoch}.$extension';
        await Supabase.instance.client.storage
            .from('photo-to-video-inputs')
            .uploadBinary(
              inputObjectPath,
              await sourcePhoto!.readAsBytes(),
              fileOptions: FileOptions(contentType: contentType, upsert: false),
            );
        requestBody['image_url'] = await Supabase.instance.client.storage
            .from('photo-to-video-inputs')
            .createSignedUrl(inputObjectPath, 3600);
      }
      final submitted = await _call(requestBody);
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
      if (mounted) setState(() => stage = 'Loading generated result…');
      final result = await _call({'task': task, 'action': 'result', 'request_id': id});
      if (task == 'image') {
        final images = result['images'];
        final url = images is List && images.isNotEmpty ? images.first['url']?.toString() : null;
        if (url == null) throw Exception('Image URL was not returned.');
        if (mounted) setState(() => imageUrl = url);
      } else {
        final data = result['video'];
        final url = data is Map ? data['url']?.toString() : null;
        if (url == null) throw Exception('Video URL was not returned.');
        final player = VideoPlayerController.networkUrl(Uri.parse(url));
        await player.initialize();
        if (!mounted) { await player.dispose(); return; }
        setState(() { video = player; videoUrl = url; });
      }
      if (mounted) setState(() => stage = 'Generation complete');
    } catch (e) {
      final message = e.toString().replaceFirst('Exception: ', '');
      final lowerMessage = message.toLowerCase();
      final friendlyMessage = lowerMessage.contains('exhausted balance') ||
              lowerMessage.contains('user is locked')
          ? 'FAL AI balance is exhausted. Please top up your FAL account at fal.ai/dashboard/billing, then try again.'
          : message;
      if (mounted) setState(() => error = friendlyMessage);
    } finally {
      if (inputObjectPath != null) {
        try {
          await Supabase.instance.client.storage.from('photo-to-video-inputs').remove([inputObjectPath]);
        } catch (_) {}
      }
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveResult() async {
    if (saving) return;
    final url = imageUrl ?? videoUrl;
    if (url == null) return;
    setState(() => saving = true);
    try {
      final uri = Uri.parse(url);
      final request = await HttpClient().getUrl(uri);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('Could not download generated media.');
      }
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/PixelMagicDownloads');
      if (!await folder.exists()) await folder.create(recursive: true);
      final extension = imageUrl != null ? 'png' : 'mp4';
      final path = '${folder.path}/PixelMagic_AI_${DateTime.now().millisecondsSinceEpoch}.$extension';
      final file = File(path);
      await response.pipe(file.openWrite());
      await LocalDownloads.registerFile(path, mediaType: imageUrl != null ? 'image' : 'video');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('AI result saved to Downloads.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  void dispose() { prompt.dispose(); video?.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('AI Creative Studio')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Create with AI', style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold)),
      const SizedBox(height: 8),
      const Text('Describe your idea and let PixelMagic create it with AI.'),
      const SizedBox(height: 18),
      SegmentedButton<String>(segments: const [
        ButtonSegment(value: 'image', label: Text('AI Image'), icon: Icon(Icons.image)),
        ButtonSegment(value: 'video', label: Text('AI Reels'), icon: Icon(Icons.movie)),
        ButtonSegment(value: 'image_to_video', label: Text('Photo to Video'), icon: Icon(Icons.motion_photos_auto)),
      ], selected: {task}, onSelectionChanged: busy ? null : (v) => setState(() { task = v.first; imageUrl = null; videoUrl = null; video?.dispose(); video = null; })),
      if (task == 'image_to_video') ...[
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: busy ? null : chooseSourcePhoto,
          icon: const Icon(Icons.add_photo_alternate),
          label: Text(sourcePhoto == null ? 'Choose photo to animate' : 'Change source photo'),
        ),
        if (sourcePhoto != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(14),
            child: Image.file(File(sourcePhoto!.path), height: 220, fit: BoxFit.contain),
          ),
      ],
      const SizedBox(height: 14),
      TextField(
        controller: prompt,
        minLines: 3,
        maxLines: 6,
        maxLength: 2000,
        decoration: InputDecoration(
          labelText: task == 'image' ? 'Describe the image'
              : task == 'image_to_video' ? 'Describe how the photo should move'
              : 'Describe your reel',
        ),
      ),
      FilledButton.icon(
        onPressed: busy ? null : generate,
        icon: const Icon(Icons.auto_awesome),
        label: Text(busy ? 'Generating…'
            : task == 'image' ? 'Generate image'
            : task == 'image_to_video' ? 'Animate this photo'
            : 'Generate AI Reel'),
      ),
      if (busy) ...[const SizedBox(height: 16), const LinearProgressIndicator(), if (stage != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(stage!))],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
      if (imageUrl != null) ...[const SizedBox(height: 18), ClipRRect(borderRadius: BorderRadius.circular(14), child: Image.network(imageUrl!, errorBuilder: (_, __, ___) => const Text('Could not load generated image.'))), FilledButton.icon(onPressed: saving ? null : saveResult, icon: const Icon(Icons.download), label: Text(saving ? 'Saving…' : 'Save image to Downloads')), SelectableText(imageUrl!, style: const TextStyle(fontSize: 11))],
      if (video != null && video!.value.isInitialized) ...[const SizedBox(height: 18), AspectRatio(aspectRatio: video!.value.aspectRatio, child: VideoPlayer(video!)), FilledButton.tonalIcon(onPressed: () => setState(() => video!.value.isPlaying ? video!.pause() : video!.play()), icon: Icon(video!.value.isPlaying ? Icons.pause : Icons.play_arrow), label: const Text('Play / Pause')), FilledButton.icon(onPressed: saving ? null : saveResult, icon: const Icon(Icons.download), label: Text(saving ? 'Saving…' : 'Save video to Downloads'))],
      if (apiStatus != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(apiStatus!, style: TextStyle(fontSize: 12, color: apiStatus!.startsWith('AI API connected') ? Colors.greenAccent : Colors.orangeAccent))),
      const SizedBox(height: 14),
      const Text('AI generations may incur fal.ai usage charges.', style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]),
  );
}