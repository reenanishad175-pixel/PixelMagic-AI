// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:gal/gal.dart';

import 'local_downloads.dart';

const _studioAccent = Color(0xFF55DCCB);

class SocialExportPreset {
  final String name;
  final int width;
  final int height;
  const SocialExportPreset(this.name, this.width, this.height);
  String get label => '$width × $height';
}

const socialExportPresets = <SocialExportPreset>[
  SocialExportPreset('Instagram / Facebook Square Feed', 1080, 1080),
  SocialExportPreset('Instagram Portrait Feed', 1080, 1350),
  SocialExportPreset('Facebook Landscape Feed', 1200, 630),
  SocialExportPreset('Instagram Reel', 1080, 1920),
  SocialExportPreset('Instagram Story', 1080, 1920),
  SocialExportPreset('Facebook Story', 1080, 1920),
  SocialExportPreset('WhatsApp Status', 1080, 1920),
  SocialExportPreset('YouTube Thumbnail', 1280, 720),
  SocialExportPreset('YouTube Shorts', 1080, 1920),
  SocialExportPreset('YouTube Channel Banner', 2560, 1440),
  SocialExportPreset('YouTube Profile Image', 800, 800),
];

class SocialExportChoice {
  final int width;
  final int height;
  final bool fill;
  const SocialExportChoice(this.width, this.height, this.fill);
}

Future<SocialExportChoice?> showSocialExportDialog(BuildContext context) async {
  var selected = 0;
  var fill = true;
  final customWidth = TextEditingController(text: '1080');
  final customHeight = TextEditingController(text: '1080');
  var custom = false;
  final choice = await showDialog<SocialExportChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(builder: (context, setLocal) => AlertDialog(
      title: const Text('Download size'),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
        DropdownButtonFormField<int>(
          value: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Platform / format'),
          items: [
            for (var i = 0; i < socialExportPresets.length; i++)
              DropdownMenuItem(value: i, child: Text(socialExportPresets[i].name, maxLines: 2, overflow: TextOverflow.ellipsis)),
          ],
          onChanged: (v) => setLocal(() { selected = v ?? 0; custom = false; }),
        ),
        const SizedBox(height: 10),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          value: custom,
          onChanged: (v) => setLocal(() => custom = v ?? false),
          title: const Text('Custom size'),
          controlAffinity: ListTileControlAffinity.leading,
        ),
        if (custom) Row(children: [
          Expanded(child: TextField(controller: customWidth, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Width'))),
          const SizedBox(width: 10),
          Expanded(child: TextField(controller: customHeight, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height'))),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<bool>(
          segments: const [
            ButtonSegment(value: true, label: Text('Fill'), icon: Icon(Icons.crop)),
            ButtonSegment(value: false, label: Text('Fit'), icon: Icon(Icons.fit_screen)),
          ],
          selected: {fill},
          onSelectionChanged: (v) => setLocal(() => fill = v.first),
        ),
        const SizedBox(height: 5),
        const Text('Fill crops edges to use the full frame. Fit keeps the whole photo and adds background space.', style: TextStyle(color: Colors.white60, fontSize: 11)),
      ])),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final preset = socialExportPresets[selected];
          final w = custom ? int.tryParse(customWidth.text) : preset.width;
          final h = custom ? int.tryParse(customHeight.text) : preset.height;
          if (w == null || h == null || w < 64 || h < 64 || w > 4096 || h > 4096) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(const SnackBar(content: Text('Enter a width and height between 64 and 4096 pixels.')));
            return;
          }
          Navigator.pop(dialogContext, SocialExportChoice(w, h, fill));
        }, child: const Text('Download')),
      ],
    )),
  );
  customWidth.dispose();
  customHeight.dispose();
  return choice;
}

Future<String?> exportPreviewAtSocialSize({
  required BuildContext context,
  required GlobalKey previewKey,
}) async {
  final choice = await showSocialExportDialog(context);
  if (choice == null) return null;
  final boundary = previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
  if (boundary == null) throw Exception('Photo preview is not ready.');
  final rendered = await boundary.toImage(pixelRatio: 2.5);
  final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
  rendered.dispose();
  if (data == null) throw Exception('Could not render the edited photo.');
  final source = img.decodeImage(data.buffer.asUint8List());
  if (source == null) throw Exception('Could not process the edited photo.');
  final w = choice.width;
  final h = choice.height;
  final scale = choice.fill
      ? (w / source.width > h / source.height ? w / source.width : h / source.height)
      : (w / source.width < h / source.height ? w / source.width : h / source.height);
  final resized = img.copyResize(source,
      width: (source.width * scale).round().clamp(1, 8192).toInt(),
      height: (source.height * scale).round().clamp(1, 8192).toInt(),
      interpolation: img.Interpolation.average);
  img.Image output;
  if (choice.fill) {
    final x = ((resized.width - w) / 2).round().clamp(0, resized.width - w).toInt();
    final y = ((resized.height - h) / 2).round().clamp(0, resized.height - h).toInt();
    output = img.copyCrop(resized, x: x, y: y, width: w, height: h);
  } else {
    output = img.Image(width: w, height: h, numChannels: 4);
    img.fill(output, color: img.ColorRgba8(18, 24, 36, 255));
    img.compositeImage(output, resized,
      dstX: ((w - resized.width) / 2).round(),
      dstY: ((h - resized.height) / 2).round());
  }
  final path = await LocalDownloads.saveImageBytes(img.encodePng(output));
  await Gal.requestAccess();
  await Gal.putImage(path);
  return path;
}

class DesignTemplate {
  final String title;
  final String category;
  final IconData icon;
  final List<Color> colors;
  final String sample;
  const DesignTemplate(this.title, this.category, this.icon, this.colors, this.sample);
}

final _templates = <DesignTemplate>[

  DesignTemplate('Diwali Glow', 'Festivals', Icons.light_mode, [Color(0xFF30104B), Color(0xFFF39B27)], 'शुभ दीपावली'),
  DesignTemplate('Holi Splash', 'Festivals', Icons.palette, [Color(0xFFEF476F), Color(0xFF118AB2)], 'होली की शुभकामनाएँ'),
  DesignTemplate('Eid Mubarak', 'Festivals', Icons.nightlight_round, [Color(0xFF063B3B), Color(0xFF16A085)], 'Eid Mubarak'),
  DesignTemplate('Christmas', 'Festivals', Icons.park, [Color(0xFF064E3B), Color(0xFFB91C1C)], 'Merry Christmas'),
  DesignTemplate('New Year', 'Occasions', Icons.celebration, [Color(0xFF141E30), Color(0xFF6D28D9)], 'Happy New Year'),
  DesignTemplate('Birthday', 'Occasions', Icons.cake, [Color(0xFF7C2D92), Color(0xFFEC4899)], 'Happy Birthday'),
  DesignTemplate('Wedding', 'Occasions', Icons.favorite, [Color(0xFF5B2333), Color(0xFFD4A373)], 'शुभ विवाह'),
  DesignTemplate('Mountain Escape', 'Scenery', Icons.landscape, [Color(0xFF164E63), Color(0xFF67B7A5)], 'Beautiful Moments'),
  DesignTemplate('Ocean View', 'Scenery', Icons.waves, [Color(0xFF075985), Color(0xFF38BDF8)], 'Stay Inspired'),
  DesignTemplate('Forest Calm', 'Scenery', Icons.forest, [Color(0xFF14532D), Color(0xFF84A98C)], 'Nature Calls'),
  DesignTemplate('Taj Heritage', 'Famous Places', Icons.account_balance, [Color(0xFF713F12), Color(0xFFE9C46A)], 'Explore India'),
  DesignTemplate('City Lights', 'Famous Places', Icons.location_city, [Color(0xFF172554), Color(0xFF7C3AED)], 'City Stories'),
  DesignTemplate('Park & Garden', 'Famous Places', Icons.park, [Color(0xFF166534), Color(0xFF86A873)], 'A Beautiful Place'),
  DesignTemplate('Election Campaign', 'Campaign', Icons.campaign, [Color(0xFF172554), Color(0xFFEA580C)], 'आपका समर्थन, हमारा संकल्प'),
  DesignTemplate('Public Meeting', 'Campaign', Icons.groups, [Color(0xFF7F1D1D), Color(0xFFF59E0B)], 'जनसभा में सादर आमंत्रण'),
  DesignTemplate('Business Banner', 'Banners', Icons.storefront, [Color(0xFF0F172A), Color(0xFF0F766E)], 'आपका स्वागत है'),
  DesignTemplate('YouTube Thumbnail', 'YouTube', Icons.ondemand_video, [Color(0xFF111827), Color(0xFFDC2626)], 'New Video'),
  DesignTemplate('Channel Profile Logo', 'YouTube', Icons.account_circle, [Color(0xFF172554), Color(0xFF0F766E)], 'Your Channel'),
  DesignTemplate('YouTube Channel Banner', 'YouTube', Icons.panorama, [Color(0xFF312E81), Color(0xFF0891B2)], 'Subscribe Now'),
  DesignTemplate('Minimal Logo', 'Logos', Icons.auto_awesome, [Color(0xFF0F172A), Color(0xFF334155)], 'BRAND NAME'),
  DesignTemplate('Creator Brand', 'Logos', Icons.stars, [Color(0xFF4C1D95), Color(0xFFBE185D)], 'CREATOR'),

  ...List<DesignTemplate>.generate(160, (index) {
    const categories = ['Festivals', 'Occasions', 'Scenery', 'Famous Places', 'Campaign', 'Banners', 'YouTube', 'Logos'];
    const styles = ['Royal', 'Modern', 'Minimal', 'Vibrant', 'Classic', 'Luxury', 'Nature', 'Neon', 'Elegant', 'Bold', 'Festive', 'Creative', 'Premium', 'Gradient', 'Studio', 'Heritage'];
    const palettes = [
      [Color(0xFF14213D), Color(0xFFFCA311)],
      [Color(0xFF3A0CA3), Color(0xFFF72585)],
      [Color(0xFF006D77), Color(0xFF83C5BE)],
      [Color(0xFF7F1D1D), Color(0xFFF59E0B)],
      [Color(0xFF1D3557), Color(0xFF457B9D)],
      [Color(0xFF14532D), Color(0xFF84CC16)],
      [Color(0xFF312E81), Color(0xFF22D3EE)],
      [Color(0xFF581C87), Color(0xFFF0ABFC)],
      [Color(0xFF111827), Color(0xFF64748B)],
      [Color(0xFF831843), Color(0xFFF9A8D4)],
    ];
    const icons = [Icons.auto_awesome, Icons.celebration, Icons.landscape, Icons.account_balance, Icons.campaign, Icons.storefront, Icons.ondemand_video, Icons.palette];
    const samples = ['शुभकामनाएँ', 'आपका खास दिन', 'Explore & Dream', 'Incredible India', 'आपका समर्थन, हमारा संकल्प', 'आपका ब्रांड', 'New Video', 'YOUR BRAND'];
    final categoryIndex = index % categories.length;
    final category = categories[categoryIndex];
    final title = '${styles[index % styles.length]} ${category == 'Famous Places' ? 'Travel' : category} ${(index + 1).toString().padLeft(3, '0')}';
    final palette = palettes[(index * 3 + index ~/ 7) % palettes.length];
    return DesignTemplate(title, category, icons[categoryIndex], palette, samples[categoryIndex]);
  }),
];

class LogoWallpaperStudio extends StatefulWidget {
  const LogoWallpaperStudio({super.key});
  @override
  State<LogoWallpaperStudio> createState() => _LogoWallpaperStudioState();
}

class _LogoWallpaperStudioState extends State<LogoWallpaperStudio> {
  final picker = ImagePicker();
  final previewKey = GlobalKey();
  final heading = TextEditingController(text: 'आपका नाम');
  final subheading = TextEditingController(text: 'आपका संदेश यहाँ');
  final candidate = TextEditingController(text: 'उम्मीदवार का नाम');
  final party = TextEditingController(text: 'पार्टी / संगठन');
  final symbol = TextEditingController(text: 'चुनाव चिह्न');
  String category = 'All';
  late DesignTemplate selected = _templates.first;
  File? backgroundPhoto;
  File? portraitPhoto;
  double textSize = 25;
  double textPosition = .68;
  Color textColor = Colors.white;
  bool campaignMode = false;
  int width = 1080, height = 1080;
  bool exporting = false;

  @override
  void dispose() {
    heading.dispose(); subheading.dispose(); candidate.dispose(); party.dispose(); symbol.dispose();
    super.dispose();
  }

  Future<void> chooseBackground() async {
    final p = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (p != null && mounted) setState(() => backgroundPhoto = File(p.path));
  }

  Future<void> choosePortrait() async {
    final p = await picker.pickImage(source: ImageSource.gallery, imageQuality: 95);
    if (p != null && mounted) setState(() => portraitPhoto = File(p.path));
  }

  Future<void> export() async {
    if (exporting) return;
    setState(() => exporting = true);
    try {
      final boundary = previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Design preview is not ready.');
      final pixelRatio = width / 360;
      final image = await boundary.toImage(pixelRatio: pixelRatio);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw Exception('Could not export the design.');
      final decoded = img.decodeImage(data.buffer.asUint8List());
      if (decoded == null) throw Exception('Could not process the design.');
      final resized = img.copyResize(decoded, width: width, height: height, interpolation: img.Interpolation.average);
      final path = await LocalDownloads.saveImageBytes(img.encodePng(resized));
      await Gal.requestAccess();
      await Gal.putImage(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Design saved to Gallery: $width×$height')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categories = ['All', 'Festivals', 'Occasions', 'Scenery', 'Famous Places', 'Campaign', 'Banners', 'YouTube', 'Logos'];
    final visible = _templates.where((t) => category == 'All' || t.category == category).toList();
    final ratio = width / height;
    return Scaffold(
      appBar: AppBar(title: const Text('Wallpaper & Banner Design Studio  •  PRO')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Text('Choose a ready-made design · ${_templates.length} templates', style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        SizedBox(height: 42, child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final c in categories) Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(label: Text(c), selected: category == c, onSelected: (_) => setState(() => category = c))),
        ])),
        SizedBox(height: 104, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: visible.length, separatorBuilder: (_, __) => const SizedBox(width: 9), itemBuilder: (_, i) {
          final t = visible[i];
          return InkWell(onTap: () => setState(() {
              selected = t;
              campaignMode = t.category == 'Campaign';
              heading.text = t.sample;
              if (t.title == 'YouTube Thumbnail') { width = 1280; height = 720; }
              else if (t.title == 'Channel Profile Logo' || t.title == 'Minimal Logo' || t.title == 'Creator Brand') { width = 800; height = 800; }
              else if (t.title == 'YouTube Channel Banner') { width = 2560; height = 1440; }
              else { width = 1080; height = 1080; }
            }),
            child: Container(width: 122, padding: const EdgeInsets.all(10), decoration: BoxDecoration(
              gradient: LinearGradient(colors: t.colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(13), border: Border.all(color: selected == t ? _studioAccent : Colors.white24, width: selected == t ? 2 : 1)),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(t.icon, size: 25), const SizedBox(height: 5), Text(t.title, textAlign: TextAlign.center, maxLines: 2, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
              ]),
            ),
          );
        })),
        const SizedBox(height: 12),
        Row(children: [
          const Expanded(child: Text('Live design preview', style: TextStyle(fontWeight: FontWeight.bold))),
          DropdownButton<int>(value: width, items: const [1080, 1280, 1920, 2560, 800].map((v) => DropdownMenuItem(value: v, child: Text('$v px wide'))).toList(), onChanged: (v) => setState(() {
            width = v ?? 1080;
            if (width == 1280) {
              height = 720;
            } else if (width == 2560) {
              height = 1440;
            } else if (width == 800) {
              height = 800;
            } else if (width == 1920) {
              height = 1080;
            } else {
              height = 1080;
            }
          })),
        ]),
        Center(
          child: RepaintBoundary(
            key: previewKey,
            child: SizedBox(
              width: 360,
              child: AspectRatio(
                aspectRatio: ratio,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (backgroundPhoto != null)
                        Image.file(backgroundPhoto!, fit: BoxFit.cover)
                      else
                        DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: selected.colors,
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      if (backgroundPhoto == null)
                        Positioned(
                          right: -25,
                          top: -20,
                          child: Icon(selected.icon, size: 180, color: Colors.white.withOpacity(.12)),
                        ),
                      if (portraitPhoto != null)
                        Positioned(
                          left: 12,
                          top: 12,
                          bottom: 12,
                          width: 104,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: Image.file(portraitPhoto!, fit: BoxFit.cover),
                          ),
                        ),
                      Positioned(
                        left: 16,
                        right: 16,
                        top: 12,
                        child: Text(
                          selected.title.toUpperCase(),
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w900, color: Colors.white70),
                        ),
                      ),
                      Align(
                        alignment: Alignment(0, (textPosition * 1.6) - 1),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                campaignMode ? candidate.text : heading.text,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: textColor, fontSize: textSize, fontWeight: FontWeight.w900, shadows: const [Shadow(color: Colors.black87, blurRadius: 8)]),
                              ),
                              const SizedBox(height: 7),
                              Text(
                                campaignMode ? party.text : subheading.text,
                                textAlign: TextAlign.center,
                                style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w600, shadows: const [Shadow(color: Colors.black87, blurRadius: 7)]),
                              ),
                              if (campaignMode)
                                Text(symbol.text, style: TextStyle(color: textColor, fontWeight: FontWeight.bold, fontSize: 13)),
                            ],
                          ),
                        ),
                      ),
                      if (campaignMode)
                        const Positioned(
                          bottom: 12,
                          left: 12,
                          right: 12,
                          child: Text('जनता की आवाज़ • विकास का संकल्प', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Edit your design', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        TextField(controller: heading, decoration: const InputDecoration(labelText: 'Main name / heading'), onChanged: (_) => setState(() {})),
        TextField(controller: subheading, decoration: const InputDecoration(labelText: 'Message / tagline'), onChanged: (_) => setState(() {})),
        if (campaignMode) ...[
          TextField(controller: candidate, decoration: const InputDecoration(labelText: 'Candidate name'), onChanged: (_) => setState(() {})),
          TextField(controller: party, decoration: const InputDecoration(labelText: 'Party / organization'), onChanged: (_) => setState(() {})),
          TextField(controller: symbol, decoration: const InputDecoration(labelText: 'Election symbol / mark'), onChanged: (_) => setState(() {})),
        ],
        Row(children: [
          Expanded(child: OutlinedButton.icon(onPressed: chooseBackground, icon: const Icon(Icons.wallpaper), label: const Text('Upload custom background from gallery'))),
          const SizedBox(width: 8),
          Expanded(child: OutlinedButton.icon(onPressed: choosePortrait, icon: const Icon(Icons.person), label: const Text('Add portrait / logo'))),
        ]),
        Row(children: [
          const Text('Text size'), Expanded(child: Slider(value: textSize, min: 14, max: 42, onChanged: (v) => setState(() => textSize = v))),
        ]),
        Row(children: [
          const Text('Text position'), Expanded(child: Slider(value: textPosition, min: .2, max: 1, onChanged: (v) => setState(() => textPosition = v))),
        ]),
        Wrap(spacing: 8, children: [
          for (final c in [Colors.white, Colors.black, Colors.yellow, Colors.red, Colors.cyan, Colors.orange])
            InkWell(onTap: () => setState(() => textColor = c), child: CircleAvatar(radius: 14, backgroundColor: c, child: textColor == c ? const Icon(Icons.check, size: 16, color: Colors.black) : null)),
        ]),
        DropdownButton<int>(value: height, isExpanded: true, items: const [720, 800, 1080, 1350, 1440, 1920].map((v) => DropdownMenuItem(value: v, child: Text('Height: $v px'))).toList(), onChanged: (v) => setState(() => height = v ?? 1080)),
        FilledButton.icon(onPressed: exporting ? null : export, icon: const Icon(Icons.download), label: Text(exporting ? 'Exporting…' : 'Export PNG to Gallery')),
      ]),
    );
  }
}

