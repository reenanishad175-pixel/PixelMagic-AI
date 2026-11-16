// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfx/pdfx.dart' as pdfx;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:printing/printing.dart';

import 'local_downloads.dart';

class _PdfOverlay {
  final String? text;
  final Uint8List? imageBytes;
  final double x, y, width, height, fontSize;
  final Color color;
  final bool whiteout;
  final String font;
  const _PdfOverlay({
    this.text,
    this.imageBytes,
    this.x = .12,
    this.y = .12,
    this.width = .45,
    this.height = .16,
    this.fontSize = 18,
    this.color = Colors.black,
    this.whiteout = false,
    this.font = 'Helvetica',
  });
}

class _PdfPageData {
  final Uint8List bytes;
  final double width;
  final double height;
  final List<_PdfOverlay> overlays;
  _PdfPageData({required this.bytes, required this.width, required this.height, List<_PdfOverlay>? overlays})
      : overlays = overlays ?? [];
}

class ProPdfEditorScreen extends StatefulWidget {
  const ProPdfEditorScreen({super.key});
  @override
  State<ProPdfEditorScreen> createState() => _ProPdfEditorScreenState();
}

class _ProPdfEditorScreenState extends State<ProPdfEditorScreen> {
  final picker = ImagePicker();
  final pages = <_PdfPageData>[];
  int currentPage = 0;
  bool busy = false;
  String? sourceName;
  String? status;
  String? error;
  final List<TextLine> detectedLines = <TextLine>[];
  final TextRecognizer _textRecognizer = TextRecognizer(script: TextRecognitionScript.devanagiri);

  Future<void> openPdf() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['pdf']);
    final path = picked?.files.single.path;
    if (path == null) return;
    setState(() { busy = true; error = null; status = 'Opening PDF pages…'; });
    final loaded = <_PdfPageData>[];
    pdfx.PdfDocument? document;
    try {
      document = await pdfx.PdfDocument.openFile(path);
      for (var number = 1; number <= document.pagesCount; number++) {
        final page = await document.getPage(number);
        try {
          final scale = (1800 / page.width).clamp(1.0, 2.0);
          final raster = await page.render(
            width: page.width * scale,
            height: page.height * scale,
            format: pdfx.PdfPageImageFormat.png,
          );
          if (raster == null) throw Exception('Could not render page $number.');
          loaded.add(_PdfPageData(bytes: raster.bytes, width: page.width, height: page.height));
        } finally {
          await page.close();
        }
        if (mounted) setState(() => status = 'Rendering page $number of ${document!.pagesCount}…');
      }
      if (loaded.isEmpty) throw Exception('This PDF has no readable pages.');
      if (!mounted) return;
      setState(() {
        pages..clear()..addAll(loaded);
        currentPage = 0;
        sourceName = path.split(Platform.pathSeparator).last;
        status = 'Loaded ${loaded.length} pages. Add overlays, reorder or remove pages.';
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString().replaceFirst('Exception: ', ''));
    } finally {
      await document?.close();
      if (mounted) setState(() => busy = false);
    }
  }


  Future<void> scanCurrentPageWithOcr() async {
    if (pages.isEmpty || busy) return;
    setState(() { busy = true; error = null; status = 'Recognizing text on this page…'; detectedLines.clear(); });
    try {
      final temp = await getTemporaryDirectory();
      final file = File('${temp.path}/pixelmagic_ocr_${DateTime.now().microsecondsSinceEpoch}.png');
      await file.writeAsBytes(pages[currentPage].bytes, flush: true);
      final result = await _textRecognizer.processImage(InputImage.fromFilePath(file.path));
      if (!mounted) return;
      setState(() {
        detectedLines.addAll(result.blocks.expand((block) => block.lines));
        status = 'OCR found ${detectedLines.length} text line(s). Tap a line to edit it.';
      });
      await file.delete();
    } catch (e) {
      if (mounted) setState(() => error = 'On-device OCR failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addRecognizedLine(TextLine line) async {
    if (pages.isEmpty) return;
    final controller = TextEditingController(text: line.text);
    final decoded = img.decodeImage(pages[currentPage].bytes);
    if (decoded == null) { controller.dispose(); return; }
    final box = line.boundingBox;
    final x = (box.left / decoded.width).clamp(0.0, 0.95).toDouble();
    final y = (box.top / decoded.height).clamp(0.0, 0.95).toDouble();
    final w = (box.width / decoded.width).clamp(0.05, 1.0 - x).toDouble();
    final h = (box.height / decoded.height).clamp(0.025, 1.0 - y).toDouble();
    final replacement = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit recognized text'),
        content: TextField(controller: controller, maxLines: 4, autofocus: true),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, controller.text.trim()), child: const Text('Use text')),
        ],
      ),
    );
    controller.dispose();
    if (replacement == null || replacement.isEmpty || !mounted) return;
    setState(() {
      pages[currentPage].overlays.add(_PdfOverlay(
        text: replacement, x: x, y: y, width: w, height: h,
        fontSize: (box.height * pages[currentPage].width / decoded.width * .78).clamp(7, 42).toDouble(),
        whiteout: true,
      ));
      status = 'Editable replacement layer added. Check alignment before exporting.';
    });
  }

  Future<void> addPhotoPages() async {
    final selected = await picker.pickMultiImage(imageQuality: 95);
    if (selected.isEmpty) return;
    setState(() { busy = true; error = null; });
    try {
      for (final photo in selected) {
        final bytes = await File(photo.path).readAsBytes();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        final normalized = img.encodePng(decoded);
        pages.add(_PdfPageData(
          bytes: Uint8List.fromList(normalized),
          width: 595,
          height: 842,
        ));
      }
      if (mounted) {
        setState(() {
          if (pages.isNotEmpty) currentPage = pages.length - 1;
          status = 'Added ${selected.length} photo page(s).';
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = 'Could not add photos: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> addText() async {
    if (pages.isEmpty) return;
    final textController = TextEditingController();
    final sizeController = TextEditingController(text: '18');
    final xController = TextEditingController(text: '12');
    final yController = TextEditingController(text: '12');
    var color = Colors.black;
    var whiteout = false;
    var font = 'Helvetica';
    final result = await showDialog<_PdfOverlay>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Add / replace PDF text'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: textController, maxLines: 3, decoration: const InputDecoration(labelText: 'Text to add or replacement text')),
          TextField(controller: sizeController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Font size (points)')),
          DropdownButtonFormField<String>(value: font, decoration: const InputDecoration(labelText: 'Font'), items: const [
            DropdownMenuItem(value: 'Helvetica', child: Text('Helvetica')),
            DropdownMenuItem(value: 'Times', child: Text('Times New Roman style')),
            DropdownMenuItem(value: 'Courier', child: Text('Courier')),
          ], onChanged: (v) => setLocal(() => font = v ?? 'Helvetica')),
          Row(children: [
            const Text('Text color'),
            const SizedBox(width: 10),
            for (final c in [Colors.black, Colors.blue, Colors.red, Colors.green, Colors.white])
              IconButton(onPressed: () => setLocal(() => color = c), icon: Icon(Icons.circle, color: c, size: 22)),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: whiteout,
            onChanged: (v) => setLocal(() => whiteout = v),
            title: const Text('Cover old text behind this text'),
            subtitle: const Text('Use this to visually replace or remove text in the selected area.'),
          ),
          TextField(controller: xController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Left position (%)')),
          TextField(controller: yController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Top position (%)')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final size = double.tryParse(sizeController.text) ?? 18;
            final x = (double.tryParse(xController.text) ?? 12).clamp(0, 90) / 100;
            final y = (double.tryParse(yController.text) ?? 12).clamp(0, 95) / 100;
            if (textController.text.trim().isEmpty) return;
            Navigator.pop(ctx, _PdfOverlay(
              text: textController.text.trim(), x: x, y: y, fontSize: size.clamp(6, 96),
              color: color, whiteout: whiteout, font: font,
            ));
          }, child: const Text('Add text')),
        ],
      )),
    );
    textController.dispose(); sizeController.dispose(); xController.dispose(); yController.dispose();
    if (result != null && mounted) {
      setState(() {
        pages[currentPage].overlays.add(result);
        status = 'Text layer added to page ${currentPage + 1}.';
      });
    }
  }

  Future<void> editLayer(int index) async {
    if (pages.isEmpty || index < 0 || index >= pages[currentPage].overlays.length) return;
    final original = pages[currentPage].overlays[index];
    final textController = TextEditingController(text: original.text ?? '');
    final xController = TextEditingController(text: (original.x * 100).round().toString());
    final yController = TextEditingController(text: (original.y * 100).round().toString());
    final widthController = TextEditingController(text: (original.width * 100).round().toString());
    final heightController = TextEditingController(text: (original.height * 100).round().toString());
    final sizeController = TextEditingController(text: original.fontSize.round().toString());
    var color = original.color;
    var whiteout = original.whiteout;
    var font = original.font;
    final edited = await showDialog<_PdfOverlay>(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setLocal) => AlertDialog(
        title: const Text('Edit text / image layer'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (original.text != null)
            TextField(controller: textController, maxLines: 3, decoration: const InputDecoration(labelText: 'Edit layer text')),
          Row(children: [
            Expanded(child: TextField(controller: xController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Left %'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: yController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Top %'))),
          ]),
          Row(children: [
            Expanded(child: TextField(controller: widthController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Width %'))),
            const SizedBox(width: 8),
            Expanded(child: TextField(controller: heightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height %'))),
          ]),
          if (original.text != null) ...[
            TextField(controller: sizeController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Font size')),
            DropdownButtonFormField<String>(value: font, decoration: const InputDecoration(labelText: 'Font'), items: const [
              DropdownMenuItem(value: 'Helvetica', child: Text('Helvetica')),
              DropdownMenuItem(value: 'Times', child: Text('Times')),
              DropdownMenuItem(value: 'Courier', child: Text('Courier')),
            ], onChanged: (v) => setLocal(() => font = v ?? 'Helvetica')),
            Wrap(spacing: 4, children: [
              for (final item in [Colors.black, Colors.blue, Colors.red, Colors.green, Colors.white, Colors.yellow])
                IconButton(onPressed: () => setLocal(() => color = item), icon: Icon(Icons.circle, color: item, size: 21)),
            ]),
            SwitchListTile(contentPadding: EdgeInsets.zero, value: whiteout, onChanged: (v) => setLocal(() => whiteout = v), title: const Text('Cover text underneath')),
          ],
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            final x = ((double.tryParse(xController.text) ?? 12).clamp(0, 95)) / 100;
            final y = ((double.tryParse(yController.text) ?? 12).clamp(0, 95)) / 100;
            final w = ((double.tryParse(widthController.text) ?? 45).clamp(5, 100)) / 100;
            final h = ((double.tryParse(heightController.text) ?? 16).clamp(3, 100)) / 100;
            final value = original.text == null ? null : textController.text.trim();
            if (original.text != null && (value == null || value.isEmpty)) return;
            Navigator.pop(ctx, _PdfOverlay(
              text: value, imageBytes: original.imageBytes, x: x, y: y, width: w, height: h,
              fontSize: (double.tryParse(sizeController.text) ?? 18).clamp(6, 96),
              color: color, whiteout: whiteout, font: font,
            ));
          }, child: const Text('Save layer')),
        ],
      )),
    );
    textController.dispose(); xController.dispose(); yController.dispose();
    widthController.dispose(); heightController.dispose(); sizeController.dispose();
    if (edited != null && mounted) {
      setState(() {
        pages[currentPage].overlays[index] = edited;
        status = 'Layer updated.';
      });
    }
  }

  Future<void> addImage() async {
    if (pages.isEmpty) return;
    final picked = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (picked == null) return;
    final bytes = await File(picked.path).readAsBytes();
    if (!mounted) return;
    setState(() {
      pages[currentPage].overlays.add(_PdfOverlay(
        imageBytes: bytes, x: .12, y: .12, width: .35, height: .25,
      ));
      status = 'Image / logo added to page ${currentPage + 1}.';
    });
  }

  void movePage(int direction) {
    final target = currentPage + direction;
    if (target < 0 || target >= pages.length) return;
    setState(() {
      final item = pages.removeAt(currentPage);
      pages.insert(target, item);
      currentPage = target;
      status = 'Page order updated.';
    });
  }

  void deletePage() {
    if (pages.isEmpty) return;
    setState(() {
      pages.removeAt(currentPage);
      currentPage = currentPage.clamp(0, pages.length - 1);
      status = pages.isEmpty ? 'All pages removed.' : 'Page deleted.';
    });
  }

  Future<void> exportPdf({bool share = false}) async {
    if (pages.isEmpty || busy) return;
    setState(() { busy = true; error = null; status = 'Building edited PDF…'; });
    try {
      final document = pw.Document();
      for (final page in pages) {
        final base = pw.MemoryImage(page.bytes);
        final layers = <pw.Widget>[
          pw.Positioned.fill(child: pw.Image(base, fit: pw.BoxFit.fill)),
        ];
        for (final overlay in page.overlays) {
          if (overlay.imageBytes != null) {
            layers.add(pw.Positioned(
              left: overlay.x * page.width,
              top: overlay.y * page.height,
              child: pw.SizedBox(
                width: overlay.width * page.width,
                height: overlay.height * page.height,
                child: pw.Image(pw.MemoryImage(overlay.imageBytes!), fit: pw.BoxFit.contain),
              ),
            ));
          } else if (overlay.text != null) {
            if (overlay.whiteout) {
              layers.add(pw.Positioned(
                left: overlay.x * page.width,
                top: overlay.y * page.height,
                child: pw.SizedBox(
                  width: overlay.width * page.width,
                  height: overlay.height * page.height,
                  child: pw.Container(color: PdfColors.white),
                ),
              ));
            }
            final font = overlay.font == 'Times' ? pw.Font.times()
                : overlay.font == 'Courier' ? pw.Font.courier() : pw.Font.helvetica();
            layers.add(pw.Positioned(
              left: overlay.x * page.width,
              top: overlay.y * page.height,
              child: pw.SizedBox(
                width: page.width * overlay.width,
                child: pw.Text(
                overlay.text!,
                style: pw.TextStyle(font: font, fontSize: overlay.fontSize, color: PdfColor(
                  overlay.color.red / 255, overlay.color.green / 255, overlay.color.blue / 255,
                )),
                ),
              ),
            ));
          }
        }
        document.addPage(pw.Page(
          pageFormat: PdfPageFormat(page.width, page.height),
          margin: pw.EdgeInsets.zero,
          build: (_) => pw.Stack(children: layers),
        ));
      }
      final bytes = await document.save();
      final dir = await getApplicationDocumentsDirectory();
      final folder = Directory('${dir.path}/PixelMagicDownloads');
      if (!await folder.exists()) await folder.create(recursive: true);
      final file = File('${folder.path}/PixelMagic_Edited_${DateTime.now().millisecondsSinceEpoch}.pdf');
      await file.writeAsBytes(bytes, flush: true);
      await LocalDownloads.registerFile(file.path, mediaType: 'pdf');
      if (share) {
        await Printing.sharePdf(bytes: bytes, filename: file.uri.pathSegments.last);
      }
      if (mounted) setState(() => status = 'PDF saved: ${file.uri.pathSegments.last}');
    } catch (e) {
      if (mounted) setState(() => error = 'PDF export failed: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    _textRecognizer.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final page = pages.isEmpty ? null : pages[currentPage];
    return Scaffold(
      appBar: AppBar(title: const Text('PRO PDF Editor')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Edit PDF pages', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold)),
        const Text('Import a PDF, add or cover text, add logos/photos, add photo pages, reorder or delete pages, then export.', style: TextStyle(color: Colors.white60, fontSize: 12)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(onPressed: busy ? null : openPdf, icon: const Icon(Icons.folder_open), label: const Text('Open PDF')),
          OutlinedButton.icon(onPressed: busy ? null : addPhotoPages, icon: const Icon(Icons.add_photo_alternate), label: const Text('Add photo pages')),
        ]),
        if (sourceName != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(sourceName!, style: const TextStyle(color: Colors.white54))),
        if (pages.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Page ${currentPage + 1} of ${pages.length}', style: const TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 52, child: ListView(scrollDirection: Axis.horizontal, children: [
            for (var i = 0; i < pages.length; i++)
              Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(label: Text('Page ${i + 1}'), selected: currentPage == i, onSelected: (_) => setState(() => currentPage = i))),
          ])),
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: AspectRatio(
              aspectRatio: page!.width / page.height,
              child: LayoutBuilder(builder: (context, constraints) => Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(page.bytes, fit: BoxFit.fill),
                  for (final overlay in page.overlays)
                    if (overlay.imageBytes != null)
                      Positioned(
                        left: overlay.x * constraints.maxWidth,
                        top: overlay.y * constraints.maxHeight,
                        width: overlay.width * constraints.maxWidth,
                        height: overlay.height * constraints.maxHeight,
                        child: Image.memory(overlay.imageBytes!, fit: BoxFit.contain),
                      )
                    else if (overlay.text != null)
                      Positioned(
                        left: overlay.x * constraints.maxWidth,
                        top: overlay.y * constraints.maxHeight,
                        child: Container(
                          width: overlay.width * constraints.maxWidth,
                          height: overlay.height * constraints.maxHeight,
                          color: overlay.whiteout ? Colors.white : Colors.transparent,
                          padding: overlay.whiteout ? const EdgeInsets.all(4) : EdgeInsets.zero,
                          child: Text(
                            overlay.text!,
                            style: TextStyle(fontSize: (overlay.fontSize * .65).clamp(8, 28), color: overlay.color, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                ],
              )),
            ),
          ),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            OutlinedButton.icon(onPressed: addText, icon: const Icon(Icons.text_fields), label: const Text('Add / replace text')),
            OutlinedButton.icon(onPressed: addImage, icon: const Icon(Icons.image), label: const Text('Add image / logo')),
          OutlinedButton.icon(onPressed: busy ? null : scanCurrentPageWithOcr, icon: const Icon(Icons.document_scanner), label: const Text('Scan text (OCR')),
            OutlinedButton.icon(onPressed: () => movePage(-1), icon: const Icon(Icons.arrow_upward), label: const Text('Move page up')),
            OutlinedButton.icon(onPressed: () => movePage(1), icon: const Icon(Icons.arrow_downward), label: const Text('Move page down')),
            OutlinedButton.icon(onPressed: deletePage, icon: const Icon(Icons.delete_outline), label: const Text('Delete page')),
          ]),
          if (detectedLines.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('OCR text found · tap to edit and cover the original', style: TextStyle(fontWeight: FontWeight.bold)),
            for (final line in detectedLines)
              ListTile(dense: true, leading: const Icon(Icons.text_snippet_outlined), title: Text(line.text, maxLines: 2, overflow: TextOverflow.ellipsis), subtitle: Text('Detected at ${line.boundingBox.left.round()}, ${line.boundingBox.top.round()}'), onTap: () => addRecognizedLine(line)),
          ],
          if (page.overlays.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text('Layers on this page', style: TextStyle(fontWeight: FontWeight.bold)),
            const Text('Tap a layer to edit its text, position, size, font or color.', style: TextStyle(color: Colors.white54, fontSize: 11)),
            for (var i = 0; i < page.overlays.length; i++)
              ListTile(
                dense: true,
                title: Text(page.overlays[i].text ?? 'Image / logo layer'),
                subtitle: Text('Position ${(page.overlays[i].x * 100).round()}%, ${(page.overlays[i].y * 100).round()}% · ${(page.overlays[i].width * 100).round()} × ${(page.overlays[i].height * 100).round()}%'),
                onTap: () => editLayer(i),
                trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                  IconButton(tooltip: 'Edit layer', icon: const Icon(Icons.edit), onPressed: () => editLayer(i)),
                  IconButton(tooltip: 'Delete layer', icon: const Icon(Icons.delete_outline), onPressed: () => setState(() => page.overlays.removeAt(i))),
                ]),
              ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(onPressed: busy ? null : () => exportPdf(), icon: const Icon(Icons.save), label: const Text('Save edited PDF')),
          OutlinedButton.icon(onPressed: busy ? null : () => exportPdf(share: true), icon: const Icon(Icons.share), label: const Text('Save & share / print')),
        ],
        if (busy) const Padding(padding: EdgeInsets.all(14), child: LinearProgressIndicator()),
        if (status != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(status!, style: const TextStyle(color: Color(0xFF55DCCB)))),
        if (error != null) Padding(padding: const EdgeInsets.only(top: 10), child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
        const SizedBox(height: 12),
        const Text('Note: on-device OCR detects text lines and lets you create replacement layers. The source page remains a raster image; review alignment carefully. Hindi OCR and PDF font rendering must be tested on sample documents. Cloud OCR fallback is not configured yet.', style: TextStyle(color: Colors.white54, fontSize: 11)),
      ]),
      floatingActionButton: pages.isEmpty ? FloatingActionButton.extended(onPressed: busy ? null : openPdf, icon: const Icon(Icons.picture_as_pdf), label: const Text('Open PDF')) : null,
    );
  }
}
