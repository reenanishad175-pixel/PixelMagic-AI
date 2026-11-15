import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_video/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_video/return_code.dart';
import 'package:path_provider/path_provider.dart';

import 'local_downloads.dart';

class LocalVideoEngine {
  static String _quote(String value) => '"${value.replaceAll('\\', '\\\\').replaceAll('"', '\\"')}"';

  static Future<String> _outputPath(String label) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/PixelMagicDownloads');
    if (!await folder.exists()) await folder.create(recursive: true);
    return '${folder.path}/${label}_${DateTime.now().millisecondsSinceEpoch}.mp4';
  }

  static Future<String> _run(String command, String output, String label) async {
    final session = await FFmpegKit.execute(command);
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code) || !await File(output).exists()) {
      final logs = await session.getOutput();
      throw Exception('$label failed. ${(logs ?? '').split('\n').reversed.take(5).toList().reversed.join(' ')}');
    }
    await LocalDownloads.registerFile(output, mediaType: 'video');
    return output;
  }

  static Future<String> trim({
    required String input,
    required Duration start,
    required Duration end,
  }) async {
    if (end <= start) throw ArgumentError('End time must be after start time.');
    final output = await _outputPath('PixelMagic_Trim');
    final seconds = (end - start).inMilliseconds / 1000;
    final command = '-y -ss ${start.inMilliseconds / 1000} -i ${_quote(input)} -t $seconds -c:v mpeg4 -q:v 3 -c:a aac -b:a 128k -movflags +faststart ${_quote(output)}';
    return _run(command, output, 'Video trim');
  }

  static Future<String> addMusic({
    required String input,
    required String audio,
    double volume = 0.8,
  }) async {
    final output = await _outputPath('PixelMagic_Music');
    final command = '-y -i ${_quote(input)} -stream_loop -1 -i ${_quote(audio)} -map 0:v:0 -map 1:a:0 -c:v copy -af "volume=$volume" -c:a aac -b:a 192k -shortest -movflags +faststart ${_quote(output)}';
    return _run(command, output, 'Add music');
  }

  static Future<String> addText({
    required String input,
    required String text,
    required double seconds,
  }) async {
    final output = await _outputPath('PixelMagic_Text');
    final temp = await getTemporaryDirectory();
    final textFile = File('${temp.path}/pixelmagic_overlay_${DateTime.now().millisecondsSinceEpoch}.txt');
    await textFile.writeAsString(text.replaceAll(':', '\\:').replaceAll("'", "\\'"), flush: true);
    final filter = "drawtext=fontfile=/system/fonts/Roboto-Regular.ttf:textfile='${textFile.path}':fontcolor=white:fontsize=36:borderw=3:bordercolor=black:x=(w-text_w)/2:y=h*0.82:enable='between(t,0,$seconds)'";
    try {
      return await _run('-y -i ${_quote(input)} -vf "$filter" -c:v mpeg4 -q:v 3 -c:a aac -b:a 128k -movflags +faststart ${_quote(output)}', output, 'Text overlay');
    } finally {
      if (await textFile.exists()) await textFile.delete();
    }
  }

  static Future<String> applyFilter({
    required String input,
    required String filter,
  }) async {
    final output = await _outputPath('PixelMagic_Filter');
    final presets = <String, String>{
      'Cinematic': 'eq=contrast=1.16:saturation=0.82:brightness=-0.02,colorbalance=rs=0.04:bs=-0.04',
      'Vintage': 'curves=vintage,eq=saturation=0.72:contrast=0.92',
      'Retro': 'colorbalance=rs=0.08:gs=0.02:bs=-0.08,eq=contrast=1.08:saturation=0.9',
      'B&W': 'hue=s=0,eq=contrast=1.12',
      'HDR': 'eq=contrast=1.25:saturation=1.18:gamma=0.95',
      'Vivid': 'eq=saturation=1.45:contrast=1.08',
      'Warm': 'colorbalance=rs=0.12:gs=0.03:bs=-0.12',
      'Cool': 'colorbalance=rs=-0.1:gs=0.02:bs=0.12',
      'Film': 'eq=contrast=1.12:saturation=0.75:gamma=1.05,noise=alls=3:allf=t',
      'Moody': 'eq=brightness=-0.06:contrast=1.22:saturation=0.78',
    };
    final videoFilter = presets[filter];
    if (videoFilter == null) throw ArgumentError('Unknown filter.');
    return _run('-y -i ${_quote(input)} -vf "$videoFilter" -c:v mpeg4 -q:v 3 -c:a aac -b:a 128k -movflags +faststart ${_quote(output)}', output, 'Video filter');
  }

  static Future<String> merge({
    required String first,
    required String second,
  }) async {
    final output = await _outputPath('PixelMagic_Merged');
    final temp = await getTemporaryDirectory();
    final list = File('${temp.path}/pixelmagic_concat_${DateTime.now().millisecondsSinceEpoch}.txt');
    String listPath(String path) => path.replaceAll("'", "'\\''");
    await list.writeAsString("file '${listPath(first)}'\nfile '${listPath(second)}'\n", flush: true);
    try {
      return await _run('-y -f concat -safe 0 -i ${_quote(list.path)} -c:v mpeg4 -q:v 3 -c:a aac -b:a 128k -movflags +faststart ${_quote(output)}', output, 'Merge videos');
    } finally {
      if (await list.exists()) await list.delete();
    }
  }
}
