// ignore_for_file: prefer_interpolation_to_compose_strings

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
    if (filter == 'Slow Motion') {
      return _run('-y -i ${_quote(input)} -vf "setpts=1.5*PTS" -af "atempo=0.6666667" -c:v mpeg4 -q:v 3 -c:a aac -b:a 128k -movflags +faststart ${_quote(output)}', output, 'Slow motion');
    }
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
      'Portrait': 'eq=brightness=0.02:contrast=1.04:saturation=1.06,unsharp=3:3:0.35',
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
  static Future<String> setSpeed({
    required String input,
    required double speed,
  }) async {
    if (speed < 0.5 || speed > 2.0) {
      throw ArgumentError('Speed must be between 0.5x and 2.0x.');
    }
    final output = await _outputPath('PixelMagic_Speed');
    final videoPts = (1 / speed).toStringAsFixed(5);
    final audioTempo = speed.toStringAsFixed(5);
    final command = '-y -i ' + _quote(input) +
        ' -vf "setpts=' + videoPts + '*PTS" -af "atempo=' + audioTempo +
        '" -c:v mpeg4 -q:v 3 -c:a aac -b:a 160k -movflags +faststart ' +
        _quote(output);
    return _run(command, output, 'Video speed');
  }

  static Future<String> setVolume({
    required String input,
    required double volume,
  }) async {
    if (volume < 0 || volume > 2.0) {
      throw ArgumentError('Volume must be between 0 and 2.');
    }
    final output = await _outputPath('PixelMagic_Volume');
    final command = '-y -i ' + _quote(input) + ' -af "volume=' +
        volume.toStringAsFixed(3) +
        '" -c:v copy -c:a aac -b:a 160k -movflags +faststart ' +
        _quote(output);
    return _run(command, output, 'Video volume');
  }


  static Future<String> reverse({
    required String input,
  }) async {
    final output = await _outputPath('PixelMagic_Reverse');
    final command = '-y -i ' + _quote(input) +
        ' -vf "reverse" -af "areverse" -c:v mpeg4 -q:v 3 -c:a aac -b:a 160k -movflags +faststart ' +
        _quote(output);
    return _run(command, output, 'Reverse video');
  }

  static Future<String> fade({
    required String input,
    double seconds = 1.0,
  }) async {
    if (seconds <= 0 || seconds > 5) throw ArgumentError('Fade duration must be 0-5 seconds.');
    final output = await _outputPath('PixelMagic_Fade');
    final command = '-y -i ' + _quote(input) +
        ' -vf "fade=t=in:st=0:d=$seconds,fade=t=out:st=99999:d=$seconds" ' +
        '-c:v mpeg4 -q:v 3 -c:a aac -b:a 160k -movflags +faststart ' + _quote(output);
    return _run(command, output, 'Video fade');
  }

  static Future<String> chromaKeyBackground({
    required String input,
    required String background,
  }) async {
    final output = await _outputPath('PixelMagic_GreenScreen');
    final command = '-y -i ' + _quote(input) + ' -stream_loop -1 -i ' + _quote(background) +
        ' -filter_complex "[1:v]scale=iw:ih[bg];[0:v]chromakey=0x00FF00:0.18:0.08[fg];[bg][fg]overlay=shortest=1[v]" ' +
        '-map "[v]" -map "0:a?" -c:v mpeg4 -q:v 3 -c:a aac -b:a 160k -shortest -movflags +faststart ' +
        _quote(output);
    return _run(command, output, 'Green screen replacement');
  }

}
