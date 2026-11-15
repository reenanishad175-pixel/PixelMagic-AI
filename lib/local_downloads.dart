import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LocalDownload {
  final String path;
  final String name;
  final int savedAt;
  const LocalDownload({required this.path, required this.name, required this.savedAt});

  Map<String, dynamic> toJson() => {'path': path, 'name': name, 'savedAt': savedAt};
  factory LocalDownload.fromJson(Map<String, dynamic> json) => LocalDownload(
    path: json['path'] as String,
    name: json['name'] as String,
    savedAt: (json['savedAt'] as num).toInt(),
  );
}

class LocalDownloads {
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);
  static const _key = 'pixelmagic_local_downloads_v1';

  static Future<Directory> _folder() async {
    final root = await getApplicationDocumentsDirectory();
    final folder = Directory('${root.path}/PixelMagicDownloads');
    if (!await folder.exists()) await folder.create(recursive: true);
    return folder;
  }

  static Future<String> saveImageBytes(List<int> bytes) async {
    final folder = await _folder();
    final name = 'PixelMagic_${DateTime.now().millisecondsSinceEpoch}.png';
    final file = File('${folder.path}/$name');
    await file.writeAsBytes(bytes, flush: true);
    final prefs = await SharedPreferences.getInstance();
    final items = await list();
    final updated = [LocalDownload(path: file.path, name: name, savedAt: DateTime.now().millisecondsSinceEpoch), ...items];
    await prefs.setString(_key, jsonEncode(updated.map((e) => e.toJson()).toList()));
    changed.value++;
    return file.path;
  }

  static Future<List<LocalDownload>> list() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw) as List<dynamic>;
      final items = decoded.map((e) => LocalDownload.fromJson(Map<String, dynamic>.from(e as Map))).toList();
      final existing = items.where((e) => File(e.path).existsSync()).toList();
      if (existing.length != items.length) {
        await prefs.setString(_key, jsonEncode(existing.map((e) => e.toJson()).toList()));
      }
      return existing;
    } catch (_) {
      return [];
    }
  }

  static Future<void> delete(LocalDownload item) async {
    final file = File(item.path);
    if (await file.exists()) await file.delete();
    final prefs = await SharedPreferences.getInstance();
    final remaining = (await list()).where((e) => e.path != item.path).toList();
    await prefs.setString(_key, jsonEncode(remaining.map((e) => e.toJson()).toList()));
    changed.value++;
  }
}

class LocalDownloadsScreen extends StatefulWidget {
  const LocalDownloadsScreen({super.key});
  @override
  State<LocalDownloadsScreen> createState() => _LocalDownloadsScreenState();
}

class _LocalDownloadsScreenState extends State<LocalDownloadsScreen> {
  late Future<List<LocalDownload>> _items;

  @override
  void initState() {
    super.initState();
    _items = LocalDownloads.list();
    LocalDownloads.changed.addListener(_refresh);
  }

  @override
  void dispose() {
    LocalDownloads.changed.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() => setState(() => _items = LocalDownloads.list());

  @override
  Widget build(BuildContext context) => FutureBuilder<List<LocalDownload>>(
    future: _items,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Center(child: CircularProgressIndicator());
      }
      final items = snapshot.data ?? [];
      if (items.isEmpty) {
        return ListView(padding: const EdgeInsets.all(24), children: const [
          SizedBox(height: 28),
          Icon(Icons.download_for_offline_outlined, size: 64, color: Color(0xFF55DCCB)),
          SizedBox(height: 16),
          Center(child: Text('Your downloads', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
          SizedBox(height: 8),
          Center(child: Text('Edited photos saved from Photo Studio will appear here.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white60))),
          SizedBox(height: 18),
          Center(child: Text('No downloads yet', style: TextStyle(color: Colors.white38))),
        ]);
      }
      return ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Card(
            color: const Color(0xFF111F2B),
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.file(File(item.path), width: 54, height: 54, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => const Icon(Icons.image_not_supported)),
              ),
              title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(DateTime.fromMillisecondsSinceEpoch(item.savedAt).toLocal().toString().substring(0, 16)),
              trailing: IconButton(
                tooltip: 'Delete download',
                icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
                onPressed: () async {
                  await LocalDownloads.delete(item);
                  _refresh();
                },
              ),
            ),
          );
        },
      );
    },
  );
}
