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
    if (!await File(first).exists() || !await File(second).exists()) {
      throw Exception('One of the selected videos is no longer available. Please select both videos again.');
    }
    const normalize = 'scale=1280:720:force_original_aspect_ratio=decrease,'
        'pad=1280:720:(ow-iw)/2:(oh-ih)/2,fps=30,setsar=1,format=yuv420p,setpts=PTS-STARTPTS';
    final outputWithAudio = await _outputPath('PixelMagic_Merged');
    final audioFilter = '[0:a:0]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo,asetpts=PTS-STARTPTS[a0];'
        '[1:a:0]aresample=44100,aformat=sample_fmts=fltp:channel_layouts=stereo,asetpts=PTS-STARTPTS[a1];';
    final filterWithAudio = '[0:v:0]$normalize[v0];[1:v:0]$normalize[v1];'
        '$audioFilter;[v0][a0][v1][a1]concat=n=2:v=1:a=1[outv][outa]';
    final commandWithAudio = '-y -i ${_quote(first)} -i ${_quote(second)} '
        '-filter_complex "$filterWithAudio" -map "[outv]" -map "[outa]" '
        '-c:v mpeg4 -q:v 3 -c:a aac -b:a 128k -ar 44100 -ac 2 -movflags +faststart '
        '${_quote(outputWithAudio)}';
    try {
      return await _run(commandWithAudio, outputWithAudio, 'Merge videos');
    } catch (_) {
      // Some phone clips have no audio stream. Retry with a video-only
      // concat so different camera formats still merge instead of crashing.
      final partial = File(outputWithAudio);
      if (await partial.exists()) await partial.delete();
      final output = await _outputPath('PixelMagic_Merged');
      final videoFilter = '[0:v:0]$normalize[v0];[1:v:0]$normalize[v1];'
          '[v0][v1]concat=n=2:v=1:a=0[outv]';
      final command = '-y -i ${_quote(first)} -i ${_quote(second)} '
          '-filter_complex "$videoFilter" -map "[outv]" -an '
          '-c:v mpeg4 -q:v 3 -movflags +faststart ${_quote(output)}';
      return _run(command, output, 'Merge videos');
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
    required double durationSeconds,
    double seconds = 1.0,
  }) async {
    if (seconds <= 0 || seconds > 5) throw ArgumentError('Fade duration must be 0-5 seconds.');
    final output = await _outputPath('PixelMagic_Fade');
    final command = '-y -i ' + _quote(input) +
        ' -vf "fade=t=in:st=0:d=$seconds,fade=t=out:st=${(durationSeconds-seconds).clamp(0, durationSeconds)}:d=$seconds" ' +
        '-c:v mpeg4 -q:v 3 -c:a aac -b:a 160k -movflags +faststart ' + _quote(output);
    return _run(command, output, 'Video fade');
  }

  static Future<String> chromaKeyBackground({
    required String input,
    required String background,
  }) async {
    final output = await _outputPath('PixelMagic_GreenScreen');
    final command = '-y -i ' + _quote(input) + ' -stream_loop -1 -i ' + _quote(background) +
        ' -filter_complex "[1:v]scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720[bg];[0:v]scale=1280:720:force_original_aspect_ratio=decrease,pad=1280:720:(ow-iw)/2:(oh-ih)/2,chromakey=0x00FF00:0.18:0.08[fg];[bg][fg]overlay=shortest=1[v]" ' +
        '-map "[v]" -map "0:a?" -c:v mpeg4 -q:v 3 -c:a aac -b:a 160k -shortest -movflags +faststart ' +
        _quote(output);
    return _run(command, output, 'Green screen replacement');
  }


  static Future<String> adjustColor({
    required String input,
    required double brightness,
    required double contrast,
    required double saturation,
  }) async {
    final output = await _outputPath('PixelMagic_ColorGrade');
    final filter = 'eq=brightness=${brightness.toStringAsFixed(3)}:contrast=${contrast.toStringAsFixed(3)}:saturation=${saturation.toStringAsFixed(3)}';
    return _run('-y -i ' + _quote(input) + ' -vf "' + filter +
        '" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' + _quote(output), output, 'Color grading');
  }

  static Future<String> crop({
    required String input,
    double fraction = 0.85,
  }) async {
    if (fraction < 0.5 || fraction > 1) throw ArgumentError('Crop size out of range.');
    final output = await _outputPath('PixelMagic_Crop');
    final f = fraction.toStringAsFixed(3);
    return _run('-y -i ' + _quote(input) + ' -vf "crop=iw*' + f + ':ih*' + f +
        ':(iw-ow)/2:(ih-oh)/2" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' +
        _quote(output), output, 'Video crop');
  }


  static Future<String> compressVideo({
    required String input,
    int crf = 30,
  }) async {
    if (crf < 20 || crf > 40) throw ArgumentError('Compression quality out of range.');
    final output = await _outputPath('PixelMagic_Compressed');
    final quantizer = ((crf - 20) * 0.9 + 2).round().clamp(2, 20);
    final command = '-y -i ' + _quote(input) +
      ' -c:v mpeg4 -q:v $quantizer -c:a aac -b:a 96k -movflags +faststart ' + _quote(output);
    return _run(command, output, 'Video compression');
  }

  static Future<String> exportResolution({
    required String input,
    required int height,
  }) async {
    if (![720, 1080, 1440, 2160].contains(height)) throw ArgumentError('Unsupported export resolution.');
    final output = await _outputPath('PixelMagic_${height}p');
    return _run('-y -i ' + _quote(input) + ' -vf "scale=-2:$height" -c:v mpeg4 -q:v 2 -c:a aac -b:a 192k -movflags +faststart ' +
        _quote(output), output, 'Resolution export');
  }


  static Future<String> rotate({required String input, int quarterTurns = 1}) async {
    if (quarterTurns < 1 || quarterTurns > 3) throw ArgumentError('Rotation must be 90, 180 or 270 degrees.');
    final output = await _outputPath('PixelMagic_Rotate');
    final filters = {1: 'transpose=1', 2: 'hflip,vflip', 3: 'transpose=2'};
    return _run('-y -i ' + _quote(input) + ' -vf "${filters[quarterTurns]}" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' + _quote(output), output, 'Rotate video');
  }

  static Future<String> flip({required String input, bool horizontal = true}) async {
    final output = await _outputPath('PixelMagic_Flip');
    final filter = horizontal ? 'hflip' : 'vflip';
    return _run('-y -i ' + _quote(input) + ' -vf "$filter" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' + _quote(output), output, 'Flip video');
  }

  static Future<String> mute({required String input}) async {
    final output = await _outputPath('PixelMagic_Mute');
    return _run('-y -i ' + _quote(input) + ' -c:v copy -an -movflags +faststart ' + _quote(output), output, 'Mute video');
  }

  static Future<String> fadeAudio({required String input, required double durationSeconds, double fadeSeconds = 2}) async {
    if (durationSeconds <= 0 || fadeSeconds <= 0 || fadeSeconds * 2 > durationSeconds) throw ArgumentError('Invalid audio fade duration.');
    final output = await _outputPath('PixelMagic_AudioFade');
    final outStart = durationSeconds - fadeSeconds;
    return _run('-y -i ' + _quote(input) + ' -af "afade=t=in:st=0:d=$fadeSeconds,afade=t=out:st=$outStart:d=$fadeSeconds" -c:v copy -c:a aac -b:a 192k -movflags +faststart ' + _quote(output), output, 'Audio fade');
  }

  static Future<String> sharpen({required String input, double amount = 1}) async {
    if (amount < 0.1 || amount > 3) throw ArgumentError('Sharpen amount out of range.');
    final output = await _outputPath('PixelMagic_Sharpen');
    return _run('-y -i ' + _quote(input) + ' -vf "unsharp=5:5:$amount:5:5:0" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' + _quote(output), output, 'Sharpen video');
  }

  static Future<String> vignette({required String input, double angle = 0.7}) async {
    if (angle < 0.1 || angle > 1.5) throw ArgumentError('Vignette strength out of range.');
    final output = await _outputPath('PixelMagic_Vignette');
    return _run('-y -i ' + _quote(input) + ' -vf "vignette=angle=$angle" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' + _quote(output), output, 'Vignette effect');
  }

  static Future<String> denoise({required String input}) async {
    final output = await _outputPath('PixelMagic_Denoise');
    return _run('-y -i ' + _quote(input) + ' -vf "hqdn3d=1.5:1.5:6:6" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' + _quote(output), output, 'Video denoise');
  }

  static Future<String> sepia({required String input}) async {
    final output = await _outputPath('PixelMagic_Sepia');
    return _run('-y -i ' + _quote(input) + ' -vf "colorchannelmixer=.393:.769:.189:0:.349:.686:.168:0:.272:.534:.131" -c:v mpeg4 -q:v 3 -c:a copy -movflags +faststart ' + _quote(output), output, 'Sepia effect');
  }

  static Future<String> extractAudio({required String input}) async {
    final dir = await getApplicationDocumentsDirectory();
    final folder = Directory('${dir.path}/PixelMagicDownloads');
    if (!await folder.exists()) await folder.create(recursive: true);
    final output = '${folder.path}/PixelMagic_Audio_${DateTime.now().millisecondsSinceEpoch}.m4a';
    final session = await FFmpegKit.execute('-y -i ' + _quote(input) + ' -vn -c:a aac -b:a 192k ' + _quote(output));
    final code = await session.getReturnCode();
    if (!ReturnCode.isSuccess(code) || !await File(output).exists()) throw Exception('Audio extraction failed.');
    await LocalDownloads.registerFile(output, mediaType: 'audio');
    return output;
  }


  static Future<String> mixMusic({
    required String input,
    required String audio,
    double musicVolume = 0.35,
    double originalVolume = 1,
  }) async {
    if (musicVolume < 0 || musicVolume > 2 || originalVolume < 0 || originalVolume > 2) {
      throw ArgumentError('Audio levels must be between 0 and 2.');
    }
    final output = await _outputPath('PixelMagic_AudioMix');
    final graph = '[0:a]volume=$originalVolume[a0];[1:a]volume=$musicVolume[a1];[a0][a1]amix=inputs=2:duration=first:dropout_transition=2[a]';
    final command = '-y -i ' + _quote(input) + ' -stream_loop -1 -i ' + _quote(audio) +
      ' -filter_complex "$graph" -map 0:v:0 -map "[a]" -c:v copy -c:a aac -b:a 192k -shortest -movflags +faststart ' + _quote(output);
    return _run(command, output, 'Music mix');
  }

  static Future<String> exportAdvanced({
    required String input,
    required int height,
    required int fps,
    required int bitrateMbps,
  }) async {
    if (![720, 1080, 1440, 2160].contains(height)) throw ArgumentError('Unsupported export resolution.');
    if (![24, 25, 30, 50, 60].contains(fps)) throw ArgumentError('Unsupported frame rate.');
    if (![2, 4, 8, 12, 20].contains(bitrateMbps)) throw ArgumentError('Unsupported bitrate.');
    final output = await _outputPath('PixelMagic_Export');
    final command = '-y -i ' + _quote(input) +
      ' -vf "scale=-2:$height" -r $fps -c:v mpeg4 -b:v ${bitrateMbps}M -maxrate ${bitrateMbps}M -bufsize ${bitrateMbps * 2}M -c:a aac -b:a 192k -movflags +faststart ' + _quote(output);
    return _run(command, output, 'Advanced video export');
  }


  static Future<String> exportForSocial({
    required String input,
    required int width,
    required int height,
    required String fitMode,
  }) async {
    if (width < 144 || height < 144 || width > 4096 || height > 4096 ||
        width.isOdd || height.isOdd) {
      throw ArgumentError('Video dimensions must be even numbers between 144 and 4096.');
    }
    if (fitMode != 'fit' && fitMode != 'fill') {
      throw ArgumentError('Unknown video fit mode.');
    }
    final output = await _outputPath('PixelMagic_Social');
    final filter = fitMode == 'fill'
        ? 'scale=$width:$height:force_original_aspect_ratio=increase,crop=$width:$height'
        : 'scale=$width:$height:force_original_aspect_ratio=decrease,pad=$width:$height:(ow-iw)/2:(oh-ih)/2:black';
    final command = '-y -i ' + _quote(input) +
        ' -vf "$filter" -c:v mpeg4 -q:v 3 -c:a aac -b:a 192k -movflags +faststart ' +
        _quote(output);
    return _run(command, output, 'Social size video export');
  }


}
