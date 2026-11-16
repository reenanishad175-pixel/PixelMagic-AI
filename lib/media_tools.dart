// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'local_downloads.dart';
import 'local_video_engine.dart';

const _toolAccent = Color(0xFF55DCCB);

String _sizeLabel(int bytes) {
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class MediaCompressorScreen extends StatefulWidget {
  const MediaCompressorScreen({super.key});
  @override
  State<MediaCompressorScreen> createState() => _MediaCompressorScreenState();
}

class _MediaCompressorScreenState extends State<MediaCompressorScreen> {
  final picker = ImagePicker();
  File? source;
  String kind = 'photo';
  double quality = 65;
  bool busy = false;
  String? resultPath, error;

  Future<void> choose(String type) async {
    if (type == 'photo') {
      final file = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
      if (file != null && mounted) setState(() { source = File(file.path); kind = type; resultPath = null; error = null; });
    } else {
      final file = await picker.pickVideo(source: ImageSource.gallery);
      if (file != null && mounted) setState(() { source = File(file.path); kind = type; resultPath = null; error = null; });
    }
  }

  Future<void> compress() async {
    final input = source;
    if (input == null || busy) return;
    setState(() { busy = true; error = null; resultPath = null; });
    try {
      String output;
      if (kind == 'photo') {
        final decoded = img.decodeImage(await input.readAsBytes());
        if (decoded == null) throw Exception('This photo format could not be opened.');
        final dir = await getApplicationDocumentsDirectory();
        final folder = Directory('${dir.path}/PixelMagicDownloads');
        if (!await folder.exists()) await folder.create(recursive: true);
        output = '${folder.path}/PixelMagic_Compressed_${DateTime.now().millisecondsSinceEpoch}.jpg';
        await File(output).writeAsBytes(img.encodeJpg(decoded, quality: quality.round()), flush: true);
        await LocalDownloads.registerFile(output, mediaType: 'image');
      } else {
        final crf = (42 - (quality / 100 * 22)).round().clamp(20, 40);
        output = await LocalVideoEngine.compressVideo(input: input.path, crf: crf);
      }
      if (mounted) setState(() => resultPath = output);
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Photo & Video Compressor')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Reduce media size', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
      const Text('Compress photos and videos locally on your phone.', style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 18),
      SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'photo', label: Text('Photo'), icon: Icon(Icons.image)),
          ButtonSegment(value: 'video', label: Text('Video'), icon: Icon(Icons.video_file)),
        ],
        selected: {kind}, onSelectionChanged: busy ? null : (v) => choose(v.first),
      ),
      const SizedBox(height: 14),
      OutlinedButton.icon(onPressed: busy ? null : () => choose(kind),
        icon: Icon(kind == 'photo' ? Icons.add_photo_alternate : Icons.video_library),
        label: Text(source == null ? 'Choose ${kind == 'photo' ? 'photo' : 'video'}' : 'Choose another $kind')),
      if (source != null) ...[
        const SizedBox(height: 10),
        Text('Original size: ${_sizeLabel(source!.lengthSync())}', style: const TextStyle(color: _toolAccent)),
        if (kind == 'photo') ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.file(source!, height: 220, fit: BoxFit.contain)),
        const SizedBox(height: 14),
        Text('Compression quality: ${quality.round()}%'),
        Slider(value: quality, min: 20, max: 95, divisions: 15,
          onChanged: busy ? null : (v) => setState(() { quality = v; resultPath = null; })),
        const Text('Lower quality makes a smaller file. Video compression may take a few minutes.', style: TextStyle(color: Colors.white54, fontSize: 12)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: busy ? null : compress,
          icon: const Icon(Icons.compress), label: Text(busy ? 'Compressing…' : 'Compress and save')),
      ],
      if (busy) const Padding(padding: EdgeInsets.all(14), child: LinearProgressIndicator()),
      if (resultPath != null) ...[
        const SizedBox(height: 16),
        Card(color: const Color(0xFF111F2B), child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Compression complete', style: TextStyle(color: _toolAccent, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text('Before: ${_sizeLabel(source!.lengthSync())}'),
          Text('After: ${_sizeLabel(File(resultPath!).lengthSync())}'),
          Text('Saved: ${(100 - File(resultPath!).lengthSync() / source!.lengthSync() * 100).clamp(0, 100).toStringAsFixed(1)}%'),
          const SizedBox(height: 6), const Text('Saved in PixelMagic Downloads.', style: TextStyle(color: Colors.white60, fontSize: 12)),
        ]))),
      ],
      if (error != null) Padding(padding: const EdgeInsets.only(top: 14), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
    ]),
  );
}

class PdfToolsScreen extends StatefulWidget {
  const PdfToolsScreen({super.key});
  @override
  State<PdfToolsScreen> createState() => _PdfToolsScreenState();
}

class _PdfToolsScreenState extends State<PdfToolsScreen> {
  final picker = ImagePicker();
  File? selectedPdf;
  bool busy = false;
  String? status, error;

  Future<void> createPdf() async {
    final images = await picker.pickMultiImage(imageQuality: 95);
    if (images.isEmpty) return;
    setState(() { busy = true; error = null; status = null; });
    try {
      final doc = pw.Document();
      var pageCount = 0;
      for (final image in images) {
        final bytes = await File(image.path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        final jpg = img.encodeJpg(decoded, quality: 92);
        final memory = pw.MemoryImage(jpg);
        doc.addPage(pw.Page(pageFormat: PdfPageFormat.a4, margin: const pw.EdgeInsets.all(20),
          build: (_) => pw.Center(child: pw.Image(memory, fit: pw.BoxFit.contain))));
        pageCount++;
      }
      if (pageCount == 0) throw Exception('No usable photos were selected.');
      final bytes = await doc.save();
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/PixelMagicDownloads');
      if (!await folder.exists()) await folder.create(recursive: true);
      final file = File('${folder.path}/PixelMagic_PhotoPDF_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await LocalDownloads.registerFile(file.path, mediaType: 'pdf');
      if (mounted) setState(() => status = 'PDF created: ${file.path.split(Platform.pathSeparator).last}');
      await Printing.sharePdf(bytes: bytes, filename: 'PixelMagic_Photos.pdf');
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> choosePdf() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked?.files.single.path;
    if (path != null && mounted) setState(() { selectedPdf = File(path); error = null; status = null; });
  }

  Future<void> sharePdf() async {
    final file = selectedPdf;
    if (file == null) return;
    try {
      await Printing.sharePdf(bytes: await file.readAsBytes(), filename: file.path.split(Platform.pathSeparator).last);
    } catch (e) {
      if (mounted) setState(() => error = 'Could not open this PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('PDF Editor & Photo to PDF')),
    body: ListView(padding: const EdgeInsets.all(18), children: [
      const Text('Photo to PDF', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const Text('Select multiple photos to create a multi-page A4 PDF.', style: TextStyle(color: Colors.white60)),
      const SizedBox(height: 12),
      FilledButton.icon(onPressed: busy ? null : createPdf, icon: const Icon(Icons.picture_as_pdf), label: Text(busy ? 'Creating PDF…' : 'Create PDF from photos')),
      const Divider(height: 30),
      const Text('PDF tools', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
      const Text('Choose an existing PDF to preview through the system PDF share/print viewer or send it to another app.', style: TextStyle(color: Colors.white60, fontSize: 12)),
      const SizedBox(height: 12),
      OutlinedButton.icon(onPressed: busy ? null : choosePdf, icon: const Icon(Icons.folder_open), label: const Text('Choose existing PDF')),
      if (selectedPdf != null) ...[
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.picture_as_pdf, color: _toolAccent),
          title: Text(selectedPdf!.path.split(Platform.pathSeparator).last, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(_sizeLabel(selectedPdf!.lengthSync()))),
        FilledButton.tonalIcon(onPressed: sharePdf, icon: const Icon(Icons.open_in_new), label: const Text('Open / Share / Print PDF')),
      ],
      if (busy) const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
      if (status != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(status!, style: const TextStyle(color: _toolAccent))),
      if (error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
    ]),
  );
}
