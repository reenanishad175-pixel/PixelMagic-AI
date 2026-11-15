import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

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
      final file = File(Directory.systemTemp.path + '/pixelmagic_' + DateTime.now().millisecondsSinceEpoch.toString() + '.png');
      await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
      await Gal.requestAccess();
      await Gal.putImage(file.path);
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
  String? _error;

  Future<void> _chooseVideo() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;
    setState(() { _loading = true; _error = null; });
    await _controller?.dispose();
    final controller = VideoPlayerController.file(File(file.path));
    try {
      await controller.initialize();
      if (!mounted) { await controller.dispose(); return; }
      setState(() { _controller = controller; _loading = false; });
    } catch (_) {
      await controller.dispose();
      if (mounted) setState(() { _loading = false; _error = 'This video could not be opened on this device.'; });
    }
  }

  @override
  void dispose() { _controller?.dispose(); super.dispose(); }

  String _time(Duration d) => d.inMinutes.remainder(60).toString().padLeft(2, '0') + ':' + d.inSeconds.remainder(60).toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final c = _controller;
    return Scaffold(
      appBar: AppBar(title: const Text('Video Studio')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (c == null)
          InkWell(onTap: _loading ? null : _chooseVideo, borderRadius: BorderRadius.circular(18),
            child: Container(height: 230, decoration: BoxDecoration(color: const Color(0xFF111F2B), borderRadius: BorderRadius.circular(18), border: Border.all(color: _accent)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                const Icon(Icons.video_library_outlined, size: 58, color: _accent),
                const SizedBox(height: 12), Text(_loading ? 'Loading video…' : 'Choose a video'),
                const SizedBox(height: 5), const Text('Preview and playback on your phone', style: TextStyle(color: Colors.white54, fontSize: 12)),
              ])))
        else ...[
          ClipRRect(borderRadius: BorderRadius.circular(16),
            child: AspectRatio(aspectRatio: c.value.aspectRatio, child: VideoPlayer(c))),
          const SizedBox(height: 12),
          Row(children: [
            IconButton.filled(onPressed: () => setState(() => c.value.isPlaying ? c.pause() : c.play()),
              icon: Icon(c.value.isPlaying ? Icons.pause : Icons.play_arrow)),
            Expanded(child: VideoProgressIndicator(c, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12))),
            Text(_time(c.value.position) + ' / ' + _time(c.value.duration), style: const TextStyle(fontSize: 11)),
          ]),
          OutlinedButton.icon(onPressed: _chooseVideo, icon: const Icon(Icons.video_file), label: const Text('Choose another video')),
          const SizedBox(height: 10),
          const Text('Offline editing tools', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const _ComingSoonTile(icon: Icons.content_cut, title: 'Trim / Cut', detail: 'Clip selection and export need a local video-rendering engine.'),
          const _ComingSoonTile(icon: Icons.music_note, title: 'Add music', detail: 'Audio mixing and export need a local video-rendering engine.'),
          const _ComingSoonTile(icon: Icons.text_fields, title: 'Text overlay', detail: 'Text overlay export needs the same local rendering engine.'),
          const _ComingSoonTile(icon: Icons.call_merge, title: 'Merge videos', detail: 'Joining clips needs local video-rendering support.'),
        ],
        if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        if (c == null) const Padding(padding: EdgeInsets.only(top: 14), child: Text('Video preview is offline. Editing and export tools will be added after a compatible free on-device rendering engine is included.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12))),
      ]),
      floatingActionButton: c == null ? FloatingActionButton.extended(onPressed: _chooseVideo, icon: const Icon(Icons.video_library), label: const Text('Choose video')) : null,
    );
  }
}

class _ComingSoonTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String detail;
  const _ComingSoonTile({required this.icon, required this.title, required this.detail});
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFF111F2B),
    child: ListTile(leading: Icon(icon, color: _accent), title: Text(title),
      subtitle: Text(detail, style: const TextStyle(color: Colors.white54, fontSize: 11))),
  );
}
