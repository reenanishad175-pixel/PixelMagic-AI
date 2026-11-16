import 'package:flutter/material.dart';

class VideoExportSettings {
  final int width;
  final int height;
  final String label;
  final String fitMode;
  const VideoExportSettings({
    required this.width,
    required this.height,
    required this.label,
    required this.fitMode,
  });
}

Future<VideoExportSettings?> showVideoExportSettingsDialog(BuildContext context) {
  return showDialog<VideoExportSettings>(
    context: context,
    builder: (context) => const _VideoExportSettingsDialog(),
  );
}

class _VideoExportSettingsDialog extends StatefulWidget {
  const _VideoExportSettingsDialog();

  @override
  State<_VideoExportSettingsDialog> createState() => _VideoExportSettingsDialogState();
}

class _VideoExportSettingsDialogState extends State<_VideoExportSettingsDialog> {
  static const presets = <String, List<int>>{
    'Reels / Shorts / Story (9:16)': [1080, 1920],
    'Facebook / Instagram Feed Square (1:1)': [1080, 1080],
    'Instagram Feed Portrait (4:5)': [1080, 1350],
    'YouTube / Landscape (16:9)': [1920, 1080],
    'WhatsApp Status (9:16)': [1080, 1920],
    'Facebook Story (9:16)': [1080, 1920],
    'HD Landscape (16:9)': [1280, 720],
    'Custom size': [1080, 1920],
  };

  String selected = 'Reels / Shorts / Story (9:16)';
  String fitMode = 'fill';
  late final TextEditingController widthController;
  late final TextEditingController heightController;

  @override
  void initState() {
    super.initState();
    widthController = TextEditingController(text: '1080');
    heightController = TextEditingController(text: '1920');
  }

  @override
  void dispose() {
    widthController.dispose();
    heightController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = presets[selected]!;
    final custom = selected == 'Custom size';
    return AlertDialog(
      title: const Text('Export video size'),
      content: SingleChildScrollView(child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Choose where you want to post your edited video.'),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            value: selected,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Platform / aspect ratio'),
            items: presets.keys.map((name) => DropdownMenuItem(
              value: name,
              child: Text(name, overflow: TextOverflow.ellipsis),
            )).toList(),
            onChanged: (value) => setState(() {
              selected = value ?? selected;
              final chosen = presets[selected]!;
              widthController.text = chosen[0].toString();
              heightController.text = chosen[1].toString();
            }),
          ),
          if (custom) ...[
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: widthController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Width (px)'))),
              const SizedBox(width: 10),
              Expanded(child: TextField(controller: heightController, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Height (px)'))),
            ]),
          ],
          const SizedBox(height: 12),
          const Text('How should the video fit?'),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'fill',
            groupValue: fitMode,
            onChanged: (v) => setState(() => fitMode = v!),
            title: const Text('Fill frame'),
            subtitle: const Text('Fills the selected size; may crop edges.'),
          ),
          RadioListTile<String>(
            contentPadding: EdgeInsets.zero,
            value: 'fit',
            groupValue: fitMode,
            onChanged: (v) => setState(() => fitMode = v!),
            title: const Text('Fit entire video'),
            subtitle: const Text('Keeps the whole video; may add side/top bars.'),
          ),
          if (!custom) Text('Output: ${size[0]} × ${size[1]} px', style: const TextStyle(color: Colors.white60, fontSize: 12)),
        ],
      )),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: () {
          final width = int.tryParse(widthController.text);
          final height = int.tryParse(heightController.text);
          if (width == null || height == null || width < 144 || height < 144 || width > 4096 || height > 4096) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter a custom width and height between 144 and 4096 pixels.')));
            return;
          }
          Navigator.pop(context, VideoExportSettings(
            width: width,
            height: height,
            label: selected,
            fitMode: fitMode,
          ));
        }, child: const Text('Export video')),
      ],
    );
  }
}
