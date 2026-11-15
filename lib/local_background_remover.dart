// ignore_for_file: deprecated_member_use

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:google_mlkit_selfie_segmentation/google_mlkit_selfie_segmentation.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';

import 'local_downloads.dart';

const _removeAccent = Color(0xFF55DCCB);

Uint8List _applyPersonMask(Map<String, dynamic> data) {
  final source = img.decodeImage(data['bytes'] as Uint8List);
  if (source == null) throw Exception('Could not read the selected photo.');
  final mask = data['mask'] as List<double>;
  final maskWidth = data['maskWidth'] as int;
  final maskHeight = data['maskHeight'] as int;
  final output = img.Image(width: source.width, height: source.height, numChannels: 4);
  for (var y = 0; y < source.height; y++) {
    final my = (y * maskHeight / source.height).floor().clamp(0, maskHeight - 1);
    for (var x = 0; x < source.width; x++) {
      final mx = (x * maskWidth / source.width).floor().clamp(0, maskWidth - 1);
      final confidence = mask[my * maskWidth + mx].clamp(0.0, 1.0);
      // A soft alpha transition preserves smoother hair and clothing edges.
      final alpha = (((confidence - 0.22) / 0.58).clamp(0.0, 1.0) * 255).round();
      final pixel = source.getPixel(x, y);
      output.setPixel(x, y, img.ColorRgba8(pixel.r.toInt(), pixel.g.toInt(), pixel.b.toInt(), alpha));
    }
  }
  return Uint8List.fromList(img.encodePng(output));
}

class BackgroundRemoverScreen extends StatefulWidget {
  const BackgroundRemoverScreen({super.key});
  @override
  State<BackgroundRemoverScreen> createState() => _BackgroundRemoverScreenState();
}

class _BackgroundRemoverScreenState extends State<BackgroundRemoverScreen> {
  final _picker = ImagePicker();
  final _segmenter = SelfieSegmenter(mode: SegmenterMode.single, enableRawSizeMask: true);
  XFile? _source;
  Uint8List? _result;
  bool _working = false;
  bool _showOriginal = false;
  bool _saving = false;
  String? _error;

  Future<void> _choose() async {
    final picked = await _picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (picked == null || !mounted) return;
    setState(() { _source = picked; _result = null; _error = null; _showOriginal = false; });
    await _remove();
  }

  Future<void> _remove() async {
    final file = _source;
    if (file == null || _working) return;
    setState(() { _working = true; _error = null; });
    try {
      final input = InputImage.fromFile(File(file.path));
      final mask = await _segmenter.processImage(input);
      if (mask == null) throw Exception('Person was not detected clearly. Try a photo with one person and good lighting.');
      final bytes = await File(file.path).readAsBytes();
      final result = await compute(_applyPersonMask, {
        'bytes': bytes,
        'mask': mask.confidences,
        'maskWidth': mask.width,
        'maskHeight': mask.height,
      });
      if (mounted) setState(() => _result = result);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _save() async {
    final result = _result;
    if (result == null || _saving) return;
    setState(() => _saving = true);
    try {
      final path = await LocalDownloads.saveImageBytes(result);
      await Gal.requestAccess();
      await Gal.putImage(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Transparent PNG saved to gallery and Downloads.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save image: $e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _segmenter.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Background Remover')),
    body: ListView(padding: const EdgeInsets.all(16), children: [
      if (_source == null)
        InkWell(
          onTap: _working ? null : _choose,
          borderRadius: BorderRadius.circular(18),
          child: Container(height: 250, decoration: BoxDecoration(color: const Color(0xFF111F2B), borderRadius: BorderRadius.circular(18), border: Border.all(color: _removeAccent)),
            child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.layers_clear, size: 56, color: _removeAccent),
              SizedBox(height: 12),
              Text('Choose a photo'),
              SizedBox(height: 6),
              Text('Person background removal runs on your phone', style: TextStyle(color: Colors.white54, fontSize: 12)),
            ])),
        )
      else ...[
        Container(
          decoration: BoxDecoration(color: const Color(0xFF26333D), borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: AspectRatio(aspectRatio: 4 / 5, child: _result == null
            ? Image.file(File(_source!.path), fit: BoxFit.contain)
            : Image.memory(_showOriginal ? File(_source!.path).readAsBytesSync() : _result!, fit: BoxFit.contain)),
        ),
        const SizedBox(height: 10),
        if (_result != null)
          Row(children: [
            Expanded(child: Text(_showOriginal ? 'Original photo' : 'Transparent background preview', style: const TextStyle(fontWeight: FontWeight.w600))),
            TextButton.icon(onPressed: () => setState(() => _showOriginal = !_showOriginal), icon: const Icon(Icons.compare), label: Text(_showOriginal ? 'Show result' : 'Before')),
          ]),
        if (_working) const Padding(padding: EdgeInsets.symmetric(vertical: 20), child: Column(children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Finding person and removing background…')])),
        if (_error != null) Padding(padding: const EdgeInsets.symmetric(vertical: 12), child: Text(_error!, style: const TextStyle(color: Colors.redAccent))),
        if (_result != null) FilledButton.icon(onPressed: _saving ? null : _save, icon: const Icon(Icons.save_alt), label: Text(_saving ? 'Saving…' : 'Save transparent PNG')),
        OutlinedButton.icon(onPressed: _working ? null : _choose, icon: const Icon(Icons.photo_library_outlined), label: const Text('Choose another photo')),
      ],
      const SizedBox(height: 10),
      const Text('Best results: one clearly visible person, good lighting, and a simple background. The result is saved as a transparent PNG.', style: TextStyle(color: Colors.white54, fontSize: 12)),
    ]),
    floatingActionButton: _source == null ? FloatingActionButton.extended(onPressed: _choose, icon: const Icon(Icons.photo_library), label: const Text('Choose photo')) : null,
  );
}
