// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:file_picker/file_picker.dart';
import 'local_video_engine.dart';
import 'local_downloads.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

const _accent = Color(0xFF55DCCB);
const _identity = <double>[1,0,0,0,0, 0,1,0,0,0, 0,0,1,0,0, 0,0,0,1,0];

class _PhotoFilter {
  final String name;
  final List<double> matrix;
  const _PhotoFilter(this.name, this.matrix);
}

const _filters = <_PhotoFilter>[
  _PhotoFilter('Original', _identity),
  _PhotoFilter('Vivid', [1.22,0,0,0,-12, 0,1.22,0,0,-12, 0,0,1.22,0,-12, 0,0,0,1,0]),
  _PhotoFilter('Warm', [1.08,0,0,0,8, 0,1.02,0,0,2, 0,0,0.88,0,-5, 0,0,0,1,0]),
  _PhotoFilter('Cool', [0.9,0,0,0,-3, 0,1.02,0,0,1, 0,0,1.12,0,8, 0,0,0,1,0]),
  _PhotoFilter('Vintage', [0.92,0.08,0,0,10, 0.04,0.88,0.04,0,6, 0,0.08,0.78,0,2, 0,0,0,1,0]),
  _PhotoFilter('Retro', [1.12,0.02,0,0,4, 0,0.92,0.02,0,0, 0,0.04,0.78,0,-4, 0,0,0,1,0]),
  _PhotoFilter('B&W', [0.213,0.715,0.072,0,0, 0.213,0.715,0.072,0,0, 0.213,0.715,0.072,0,0, 0,0,0,1,0]),
  _PhotoFilter('Noir', [1.35,0,0,0,-35, 0,1.35,0,0,-35, 0,0,1.35,0,-35, 0,0,0,1,0]),
  _PhotoFilter('Cinematic', [1.12,0,0,0,-8, 0,1.02,0,0,0, 0,0,0.86,0,8, 0,0,0,1,0]),
  _PhotoFilter('Fade', [0.88,0,0,0,22, 0,0.88,0,0,22, 0,0,0.88,0,22, 0,0,0,1,0]),
  _PhotoFilter('Matte', [0.9,0,0,0,18, 0,0.9,0,0,18, 0,0,0.9,0,18, 0,0,0,1,0]),
  _PhotoFilter('Golden', [1.12,0,0,0,12, 0,1.02,0,0,4, 0,0,0.72,0,-10, 0,0,0,1,0]),
  _PhotoFilter('Rose', [1.08,0,0,0,5, 0,0.9,0,0,0, 0,0,0.98,0,4, 0,0,0,1,0]),
  _PhotoFilter('Mint', [0.9,0,0,0,0, 0,1.12,0,0,8, 0,0,1.02,0,5, 0,0,0,1,0]),
  _PhotoFilter('Ocean', [0.82,0,0,0,-2, 0,1.02,0,0,2, 0,0,1.2,0,12, 0,0,0,1,0]),
  _PhotoFilter('Sunset', [1.18,0,0,0,10, 0,0.94,0,0,0, 0,0,0.78,0,-5, 0,0,0,1,0]),
  _PhotoFilter('Dream', [1.08,0.03,0,0,10, 0,1.02,0.03,0,8, 0.03,0,1.1,0,12, 0,0,0,1,0]),
  _PhotoFilter('Bright', [1.12,0,0,0,18, 0,1.12,0,0,18, 0,0,1.12,0,18, 0,0,0,1,0]),
  _PhotoFilter('Deep', [1.18,0,0,0,-12, 0,1.18,0,0,-12, 0,0,1.18,0,-12, 0,0,0,1,0]),
  _PhotoFilter('Pastel', [1.02,0.04,0,0,18, 0.04,1.02,0,0,18, 0,0.04,1.02,0,18, 0,0,0,1,0]),
  _PhotoFilter('Forest', [0.9,0,0,0,0, 0,1.08,0,0,5, 0,0,0.88,0,-2, 0,0,0,1,0]),
  _PhotoFilter('Lavender', [1.02,0,0.04,0,8, 0,0.94,0.04,0,2, 0.04,0,1.12,0,10, 0,0,0,1,0]),
  _PhotoFilter('Amber', [1.16,0.02,0,0,8, 0.02,1,0,0,2, 0,0,0.82,0,-6, 0,0,0,1,0]),
  _PhotoFilter('Chrome', [1.16,0,0,0,-8, 0,1.16,0,0,-8, 0,0,1.16,0,-8, 0,0,0,1,0]),
  _PhotoFilter('Soft', [0.96,0.02,0.02,0,8, 0.02,0.96,0.02,0,8, 0.02,0.02,0.96,0,8, 0,0,0,1,0]),
];

List<double> _mixMatrix(List<double> effect, double amount) =>
    List<double>.generate(20, (i) => _identity[i] + (effect[i] - _identity[i]) * amount);

class LocalPhotoEditorScreen extends StatefulWidget {
  const LocalPhotoEditorScreen({super.key});
  @override
  State<LocalPhotoEditorScreen> createState() => _LocalPhotoEditorScreenState();
}

class _LocalPhotoEditorScreenState extends State<LocalPhotoEditorScreen> {
  final _picker = ImagePicker();
  final _previewKey = GlobalKey();
  XFile? _photo;
  int _selected = 0;
  double _intensity = 1;
  bool _showOriginal = false;
  bool _saving = false;
  bool _transforming = false;

  Future<void> _applyPhotoTransform(String operation) async {
    if (_photo == null || _transforming) return;
    setState(() => _transforming = true);
    try {
      final bytes = await File(_photo!.path).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) throw Exception('This photo format could not be edited.');
      img.Image changed;
      if (operation == 'rotate') {
        changed = img.copyRotate(decoded, angle: 90);
      } else if (operation == 'flip') {
        changed = img.copyFlip(decoded, direction: img.FlipDirection.horizontal);
      } else {
        final crop = await showDialog<Rect>(
          context: context,
          builder: (context) => const _PhotoCropDialog(),
        );
        if (crop == null) return;
        final width = (decoded.width * crop.width).round().clamp(1, decoded.width);
        final height = (decoded.height * crop.height).round().clamp(1, decoded.height);
        final x = (decoded.width * crop.left).round().clamp(0, decoded.width - width);
        final y = (decoded.height * crop.top).round().clamp(0, decoded.height - height);
        changed = img.copyCrop(decoded, x: x, y: y, width: width, height: height);
      }
      final dir = await getTemporaryDirectory();
      final output = File('${dir.path}/pixelmagic_edit_${DateTime.now().millisecondsSinceEpoch}.jpg');
      await output.writeAsBytes(img.encodeJpg(changed, quality: 95), flush: true);
      if (mounted) setState(() { _photo = XFile(output.path); _selected = 0; _intensity = 1; _showOriginal = false; });
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Edit failed: $e')));
    } finally {
      if (mounted) setState(() => _transforming = false);
    }
  }

  Future<void> _choosePhoto() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked != null && mounted) setState(() { _photo = picked; _selected = 0; });
  }

  Future<void> _savePhoto() async {
    if (_photo == null || _saving) return;
    setState(() => _saving = true);
    try {
      final boundary = _previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Preview not ready');
      final ui.Image image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw Exception('Could not render image');
      final savedPath = await LocalDownloads.saveImageBytes(data.buffer.asUint8List());
      await Gal.requestAccess();
      await Gal.putImage(savedPath);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Edited photo saved to your gallery.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save photo: ' + e.toString())));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filters[_selected];
    final matrix = _mixMatrix(filter.matrix, _intensity);
    return Scaffold(
      appBar: AppBar(title: const Text('Photo Studio'), actions: [
        IconButton(onPressed: _photo == null ? null : () => setState(() => _showOriginal = !_showOriginal),
          tooltip: 'Before / after', icon: const Icon(Icons.compare)),
      ]),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
        if (_photo == null)
          InkWell(onTap: _choosePhoto, borderRadius: BorderRadius.circular(18),
            child: Container(height: 270, decoration: BoxDecoration(color: const Color(0xFF111F2B), borderRadius: BorderRadius.circular(18), border: Border.all(color: _accent)),
              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.add_photo_alternate_outlined, size: 54, color: _accent),
                SizedBox(height: 10), Text('Choose a photo to start'),
                SizedBox(height: 4), Text('All filters run locally on your phone', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ])))
        else ...[
          RepaintBoundary(key: _previewKey, child: AspectRatio(aspectRatio: 4 / 5,
            child: ClipRRect(borderRadius: BorderRadius.circular(18),
              child: ColoredBox(color: const Color(0xFF111F2B),
                child: _showOriginal ? Image.file(File(_photo!.path), fit: BoxFit.contain)
                  : ColorFiltered(colorFilter: ColorFilter.matrix(matrix), child: Image.file(File(_photo!.path), fit: BoxFit.contain)))))),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text(_showOriginal ? 'Original preview' : filter.name + ' · ' + (_intensity * 100).round().toString() + '%', style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton.icon(onPressed: () => setState(() => _showOriginal = !_showOriginal),
              icon: const Icon(Icons.compare), label: Text(_showOriginal ? 'Show edit' : 'Before')),
          ]),
          const Text('Crop & Transform', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: _transforming ? null : () => _applyPhotoTransform('crop'), icon: const Icon(Icons.crop), label: const Text('Crop')),
            OutlinedButton.icon(onPressed: _transforming ? null : () => _applyPhotoTransform('rotate'), icon: const Icon(Icons.rotate_right), label: const Text('Rotate 90°')),
            OutlinedButton.icon(onPressed: _transforming ? null : () => _applyPhotoTransform('flip'), icon: const Icon(Icons.flip), label: const Text('Flip')),
          ]),
          if (_transforming) const Padding(padding: EdgeInsets.all(8), child: LinearProgressIndicator()),
          const SizedBox(height: 12),
          Row(children: [
            const Text('Intensity', style: TextStyle(color: Colors.white70)),
            Expanded(child: Slider(value: _intensity, min: 0, max: 1, onChanged: _showOriginal ? null : (v) => setState(() => _intensity = v))),
          ]),
          SizedBox(height: 102, child: ListView.separated(scrollDirection: Axis.horizontal,
            itemCount: _filters.length, separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final f = _filters[index];
              final selected = index == _selected;
              return InkWell(onTap: () => setState(() { _selected = index; _showOriginal = false; }),
                borderRadius: BorderRadius.circular(12),
                child: Container(width: 88, padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: selected ? const Color(0xFF153E43) : const Color(0xFF111F2B),
                    borderRadius: BorderRadius.circular(12), border: Border.all(color: selected ? _accent : Colors.white12)),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(index == 0 ? Icons.image : Icons.filter_vintage, color: selected ? _accent : Colors.white60),
                    const SizedBox(height: 5), Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
                  ])));
            })),
          const SizedBox(height: 14),
          FilledButton.icon(onPressed: _saving ? null : _savePhoto,
            icon: const Icon(Icons.save_alt), label: Text(_saving ? 'Saving…' : 'Save to gallery')),
          OutlinedButton.icon(onPressed: _choosePhoto, icon: const Icon(Icons.photo_library_outlined), label: const Text('Change photo')),
        ],
        if (_photo == null) const SizedBox(height: 14),
      ]),
      floatingActionButton: _photo == null ? FloatingActionButton.extended(onPressed: _choosePhoto, icon: const Icon(Icons.photo_library), label: const Text('Choose photo')) : null,
    );
  }
}

class LocalVideoEditorScreen extends StatefulWidget {
  const LocalVideoEditorScreen({super.key});
  @override
  State<LocalVideoEditorScreen> createState() => _LocalVideoEditorScreenState();
}

class _LocalVideoEditorScreenState extends State<LocalVideoEditorScreen> {
  final _picker = ImagePicker();
  VideoPlayerController? _controller;
  bool _loading = false;
  bool _editing = false;
  String? _error;
  String? _status;
  double _trimStart = 0;
  double _trimEnd = 0;
  String _filter = 'Original';
  String? _backgroundPath;

  Future<void> _chooseBackground() async {
    final picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['jpg', 'jpeg', 'png', 'mp4', 'mov', 'm4v'],
    );
    final path = picked?.files.single.path;
    if (path != null && mounted) setState(() => _backgroundPath = path);
  }

  Future<void> _applyChromaKey() async {
    if (_backgroundPath == null) {
      await _chooseBackground();
      if (_backgroundPath == null) return;
    }
    await _perform(
      (input) => LocalVideoEngine.chromaKeyBackground(input: input, background: _backgroundPath!),
      'Green-screen background replaced and video saved. Use a solid green-screen source.',
    );
  }

  Future<void> _chooseVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    await _loadVideo(file.path);
  }

  Future<void> _loadVideo(String path) async {
    setState(() { _loading = true; _error = null; _status = null; });
    await _controller?.dispose();
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      setState(() {
        _controller = controller;
        _trimStart = 0;
        _trimEnd = controller.value.duration.inMilliseconds / 1000;
        _loading = false;
      });
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() { _loading = false; _error = 'This video could not be opened on this device.'; });
    }
  }

  Future<void> _perform(Future<String> Function(String input) action, String success) async {
    final c = _controller;
    if (c == null || _editing) return;
    setState(() { _editing = true; _error = null; _status = 'Processing video on this device…'; });
    try {
      await c.pause();
      final output = await action(c.dataSource);
      await _loadVideo(output);
      if (mounted) setState(() => _status = success);
      try {
        await Gal.requestAccess();
        await Gal.putVideo(output);
      } catch (_) {
        // The file is already saved inside Downloads even if gallery permission is denied.
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _editing = false);
    }
  }

  Future<void> _trim() async {
    final c = _controller;
    if (c == null) return;
    await _perform((path) => LocalVideoEngine.trim(
      input: path,
      start: Duration(milliseconds: (_trimStart * 1000).round()),
      end: Duration(milliseconds: (_trimEnd * 1000).round()),
    ), 'Trimmed video saved to Downloads.');
  }

  Future<void> _addMusic() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio);
    final path = picked?.files.single.path;
    if (path == null) return;
    await _perform((input) => LocalVideoEngine.addMusic(input: input, audio: path), 'Music added and video saved.');
  }

  Future<void> _addText() async {
    final textController = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add video text'),
        content: TextField(controller: textController, autofocus: true, maxLength: 80, decoration: const InputDecoration(hintText: 'Type your caption')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, textController.text.trim()), child: const Text('Apply')),
        ],
      ),
    );
    textController.dispose();
    if (value == null || value.isEmpty) return;
    final seconds = _controller?.value.duration.inMilliseconds.toDouble() ?? 0;
    await _perform((input) => LocalVideoEngine.addText(input: input, text: value, seconds: seconds / 1000), 'Text overlay added and video saved.');
  }

  Future<void> _merge() async {
    final second = await _picker.pickVideo(source: ImageSource.gallery);
    if (second == null || _controller == null) return;
    await _perform((first) => LocalVideoEngine.merge(first: first, second: second.path), 'Videos merged and saved.');
  }

  Future<void> _applyVideoFilter(String name) async {
    if (name == 'Original') return;
    setState(() => _filter = name);
    await _perform((input) => LocalVideoEngine.applyFilter(input: input, filter: name), '$name filter applied and saved.');
    if (_error != null && mounted) setState(() => _filter = 'Original');
  }

  @override
  void dispose() { _controller?.dispose(); super.dispose(); }

  String _time(Duration d) => d.inMinutes.remainder(60).toString().padLeft(2, '0') + ':' + d.inSeconds.remainder(60).toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    final duration = c?.value.duration ?? Duration.zero;
    final maxSeconds = duration.inMilliseconds / 1000;
    final canTrim = c != null && maxSeconds > 1 && _trimEnd > _trimStart;
    return Scaffold(
      appBar: AppBar(title: const Text('Video Studio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (c == null)
          InkWell(onTap: _loading ? null : _chooseVideo, borderRadius: BorderRadius.circular(18),
            child: Container(height: 230, decoration: BoxDecoration(color: const Color(0xFF111F2B), borderRadius: BorderRadius.circular(18), border: Border.all(color: _accent)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.video_library_outlined, size: 58, color: _accent),
                const SizedBox(height: 12), Text(_loading ? 'Loading video…' : 'Choose a video'),
                const SizedBox(height: 5), const Text('Offline video editing and export', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ])))
        else ...[
          ClipRRect(borderRadius: BorderRadius.circular(16),
            child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
          const SizedBox(height: 12),
          Row(children: [
            IconButton.filled(onPressed: _editing ? null : () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow)),
            Expanded(child: VideoProgressIndicator(c, allowScrubbing: !_editing, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12))),
            Text(_time(c.value.position) + ' / ' + _time(duration), style: const TextStyle(fontSize: 11)),
          ]),
          OutlinedButton.icon(onPressed: _editing ? null : _chooseVideo, icon: const Icon(Icons.video_file), label: const Text('Choose another video')),
          const SizedBox(height: 12),
          const Text('Trim / Cut', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          Text('Select the part to keep · ${_time(Duration(milliseconds: (_trimStart * 1000).round()))} – ${_time(Duration(milliseconds: (_trimEnd * 1000).round()))}', style: const TextStyle(color: Colors.white60, fontSize: 12)),
          if (maxSeconds > 1) RangeSlider(
            min: 0, max: maxSeconds,
            values: RangeValues(_trimStart.clamp(0, maxSeconds), _trimEnd.clamp(0, maxSeconds)),
            onChanged: _editing ? null : (v) => setState(() { _trimStart = v.start; _trimEnd = v.end; }),
          ),
          FilledButton.icon(onPressed: _editing || !canTrim ? null : _trim, icon: const Icon(Icons.content_cut), label: const Text('Trim and export')),
          const SizedBox(height: 14),
          const Text('Video filters', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: ['Original','Cinematic','Vintage','Retro','B&W','HDR','Vivid','Warm','Cool','Portrait','Film','Moody','Slow Motion'].map((name) =>
            ChoiceChip(label: Text(name), selected: _filter == name, onSelected: _editing ? null : (_) => _applyVideoFilter(name))).toList()),
          const SizedBox(height: 14),
          const Text('More editing tools', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          FilledButton.tonalIcon(onPressed: _editing ? null : _addMusic, icon: const Icon(Icons.music_note), label: const Text('Add music from phone')),
          FilledButton.tonalIcon(onPressed: _editing ? null : _addText, icon: const Icon(Icons.text_fields), label: const Text('Add text overlay')),
          FilledButton.tonalIcon(onPressed: _editing ? null : _merge, icon: const Icon(Icons.call_merge), label: const Text('Merge with another video')),
          const SizedBox(height: 14),
          const Text('Motion & Animation', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: _editing ? null : () => _perform(
                (input) => LocalVideoEngine.fade(
                  input: input,
                  durationSeconds: duration.inMilliseconds / 1000,
                ),
                'Fade-in and fade-out animation applied and saved.',
              ),
              icon: const Icon(Icons.animation), label: const Text('Fade animation'),
            ),
            FilledButton.tonalIcon(
              onPressed: _editing ? null : () => _perform(
                (input) => LocalVideoEngine.reverse(input: input),
                'Reverse motion applied and saved.',
              ),
              icon: const Icon(Icons.replay), label: const Text('Reverse motion'),
            ),
            FilledButton.tonalIcon(
              onPressed: _editing ? null : () => _perform(
                (input) => LocalVideoEngine.applyFilter(input: input, filter: 'Slow Motion'),
                'Slow-motion effect applied and saved.',
              ),
              icon: const Icon(Icons.slow_motion_video), label: const Text('Slow motion'),
            ),
          ]),
          const SizedBox(height: 14),
          const Text('Green Screen · Chroma Key', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
          const Text('Remove a solid green screen and place your own photo or video behind the subject.', style: TextStyle(color: Colors.white60, fontSize: 12)),
          OutlinedButton.icon(
            onPressed: _editing ? null : _chooseBackground,
            icon: const Icon(Icons.wallpaper),
            label: Text(_backgroundPath == null ? 'Choose replacement background' : 'Change replacement background'),
          ),
          FilledButton.tonalIcon(
            onPressed: _editing || _backgroundPath == null ? null : _applyChromaKey,
            icon: const Icon(Icons.layers),
            label: const Text('Replace green background'),
          ),
        ],
        if (_editing) const Padding(padding: EdgeInsets.symmetric(vertical: 14), child: Center(child: CircularProgressIndicator())),
        if (_status != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_status!, style: const TextStyle(color: _accent))),
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
      ]),
      floatingActionButton: c == null ? FloatingActionButton.extended(onPressed: _chooseVideo, icon: const Icon(Icons.video_library), label: const Text('Choose video')) : null,
    );
  }
}


class _PhotoCropDialog extends StatefulWidget {
  const _PhotoCropDialog();
  @override
  State<_PhotoCropDialog> createState() => _PhotoCropDialogState();
}

class _PhotoCropDialogState extends State<_PhotoCropDialog> {
  double width = 0.85, height = 0.85, left = 0.075, top = 0.075;
  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('Crop photo'),
    content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
      Text('Width · ${(width * 100).round()}%'),
      Slider(value: width, min: 0.25, max: 1, divisions: 15, onChanged: (v) => setState(() { width = v; left = left.clamp(0, 1 - width).toDouble(); })),
      Text('Height · ${(height * 100).round()}%'),
      Slider(value: height, min: 0.25, max: 1, divisions: 15, onChanged: (v) => setState(() { height = v; top = top.clamp(0, 1 - height).toDouble(); })),
      Text('Move crop left / right · ${(left * 100).round()}%'),
      Slider(value: left.clamp(0, 1 - width).toDouble(), min: 0, max: 1 - width, onChanged: (v) => setState(() => left = v)),
      Text('Move crop up / down · ${(top * 100).round()}%'),
      Slider(value: top.clamp(0, 1 - height).toDouble(), min: 0, max: 1 - height, onChanged: (v) => setState(() => top = v)),
    ])),
    actions: [
      TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, Rect.fromLTWH(left, top, width, height)), child: const Text('Apply crop')),
    ],
  );
}
