// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings

import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_downloads.dart';
import 'local_video_engine.dart';
import 'local_background_remover.dart';
import 'pixelmagic_ai_studio.dart';
import 'design_studio.dart';
import 'video_export_options.dart';

const _gold = Color(0xFFFFD479);
const _panel = Color(0xFF111F2B);

class ProPhotoEditorScreen extends StatefulWidget {
  const ProPhotoEditorScreen({super.key});
  @override
  State<ProPhotoEditorScreen> createState() => _ProPhotoEditorScreenState();
}
class _ProPhotoEditorScreenState extends State<ProPhotoEditorScreen> {
  final picker = ImagePicker();
  final previewKey = GlobalKey();
  XFile? photo;
  double brightness = 0, contrast = 1, saturation = 1, warmth = 0;
  double rotation = 0, zoom = 1, frameWidth = 0, redMix = 1, greenMix = 1, blueMix = 1, blur = 0, cropAspect = .8, tint = 0, vignette = 0;
  bool flip = false, original = false, saving = false;
  String preset = 'Original';
  String overlayText = '';

  List<double> get matrix {
    final s = saturation, c = contrast;
    final r = .213 * (1 - s), g = .715 * (1 - s), b = .072 * (1 - s);
    return [
      (r+s)*c*redMix,g*c*redMix,b*c*redMix,0,128*(1-c)+brightness*255+warmth*32,
      r*c*greenMix,(g+s)*c*greenMix,b*c*greenMix,0,128*(1-c)+brightness*255+tint*24,
      r*c*blueMix,g*c*blueMix,(b+s)*c*blueMix,0,128*(1-c)+brightness*255-warmth*32,
      0,0,0,1,0
    ];
  }

  Future<void> choose() async {
    final p = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (p != null && mounted) setState(() { photo=p; brightness=0; contrast=1; saturation=1; warmth=0; rotation=0; zoom=1; frameWidth=0; redMix=1; greenMix=1; blueMix=1; blur=0; flip=false; preset='Original'; original=false; overlayText=''; });
  }
  void setPreset(String p) {
    setState(() {
      preset=p; brightness=0; contrast=1; saturation=1; warmth=0;
      if (p=='Cinematic') { contrast=1.18; saturation=.82; warmth=-.12; }
      if (p=='Vivid') { contrast=1.12; saturation=1.35; }
      if (p=='Warm') { warmth=.65; saturation=1.08; }
      if (p=='Cool') { warmth=-.65; saturation=1.04; }
      if (p=='Matte') { contrast=.86; saturation=.78; brightness=.04; }
      if (p=='B&W') saturation=0;
      if (p=='Moody') { contrast=1.24; saturation=.72; brightness=-.07; }
      if (p=='Sepia') { warmth=.8; saturation=.62; contrast=1.08; }
      if (p=='Soft') { contrast=.88; saturation=.92; brightness=.025; }
      if (p=='High Key') { brightness=.16; contrast=.9; saturation=.82; }
      if (p=='Low Key') { brightness=-.15; contrast=1.2; saturation=.9; }
    });
  }

  Future<void> saveCustomPreset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pixelmagic_photo_custom_preset', jsonEncode({
      'brightness': brightness, 'contrast': contrast, 'saturation': saturation,
      'warmth': warmth, 'red': redMix, 'green': greenMix, 'blue': blueMix, 'tint': tint, 'vignette': vignette,
      'zoom': zoom, 'blur': blur, 'frame': frameWidth, 'rotation': rotation,
      'flip': flip, 'text': overlayText, 'aspect': cropAspect,
    }));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Custom photo preset saved on this device.')));
  }

  Future<void> applyCustomPreset() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('pixelmagic_photo_custom_preset');
    if (raw == null) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No custom preset saved yet.')));
      return;
    }
    final data = jsonDecode(raw) as Map<String, dynamic>;
    if (!mounted) return;
    setState(() {
      brightness = (data['brightness'] as num).toDouble();
      contrast = (data['contrast'] as num).toDouble();
      saturation = (data['saturation'] as num).toDouble();
      warmth = (data['warmth'] as num).toDouble();
      redMix = (data['red'] as num).toDouble();
      greenMix = (data['green'] as num).toDouble();
      blueMix = (data['blue'] as num).toDouble();
      tint = (data['tint'] as num?)?.toDouble() ?? 0;
      vignette = (data['vignette'] as num?)?.toDouble() ?? 0;
      zoom = (data['zoom'] as num).toDouble();
      blur = (data['blur'] as num).toDouble();
      frameWidth = (data['frame'] as num).toDouble();
      rotation = (data['rotation'] as num).toDouble();
      flip = data['flip'] as bool;
      overlayText = data['text'] as String;
      cropAspect = (data['aspect'] as num).toDouble();
      preset = 'Custom';
      original = false;
    });
  }

  Future<void> save() async {
    if (photo==null || saving) return;
    setState(()=>saving=true);
    try {
      final decoded = img.decodeImage(await photo!.readAsBytes());
      if (decoded == null) throw Exception('Unsupported or damaged image file.');
      var output = img.bakeOrientation(decoded);
      if (rotation.abs() > .001) output = img.copyRotate(output, angle: (rotation * 180 / 3.141592653589793).round());
      if (flip) output = img.flipHorizontal(output);

      final currentRatio = output.width / output.height;
      if ((currentRatio - cropAspect).abs() > .001) {
        if (currentRatio > cropAspect) {
          final width = (output.height * cropAspect).round().clamp(1, output.width).toInt();
          output = img.copyCrop(output, x: (output.width - width) ~/ 2, y: 0, width: width, height: output.height);
        } else {
          final height = (output.width / cropAspect).round().clamp(1, output.height).toInt();
          output = img.copyCrop(output, x: 0, y: (output.height - height) ~/ 2, width: output.width, height: height);
        }
      }

      final w = output.width, h = output.height;
      final cx = (w - 1) / 2, cy = (h - 1) / 2;
      
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = output.getPixel(x, y);
          var r = p.r.toDouble() / 255, g = p.g.toDouble() / 255, b = p.b.toDouble() / 255;
          final luma = .213 * r + .715 * g + .072 * b;
          r = luma + (r - luma) * saturation;
          g = luma + (g - luma) * saturation;
          b = luma + (b - luma) * saturation;
          r = (r - .5) * contrast + .5 + brightness + warmth * .12 + redMix - 1;
          g = (g - .5) * contrast + .5 + brightness + tint * .09 + greenMix - 1;
          b = (b - .5) * contrast + .5 + brightness - warmth * .12 + blueMix - 1;
          if (vignette > 0) {
            final dx = (x - cx) / (cx == 0 ? 1 : cx);
            final dy = (y - cy) / (cy == 0 ? 1 : cy);
            final factor = (1 - (dx * dx + dy * dy) * .5 * vignette).clamp(.25, 1.0);
            r *= factor; g *= factor; b *= factor;
          }
          output.setPixelRgba(x, y,
            (r.clamp(0, 1) * 255).round(),
            (g.clamp(0, 1) * 255).round(),
            (b.clamp(0, 1) * 255).round(),
            p.a.toInt());
        }
      }
      if (blur > .5) output = img.gaussianBlur(output, radius: blur.round().clamp(1, 20).toInt());
      if (frameWidth > 0) {
        final border = (frameWidth * (w / 180)).round().clamp(1, 80);
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            if (x < border || y < border || x >= w - border || y >= h - border) {
              output.setPixelRgba(x, y, 255, 255, 255, 255);
            }
          }
        }
      }
      if (overlayText.isNotEmpty) {
        img.drawString(output, overlayText, font: img.arial48,
          x: 20, y: (h - 80).clamp(0, h - 1).toInt(),
          color: img.ColorRgb8(255, 255, 255));
      }
      final path = await LocalDownloads.saveImageBytes(img.encodePng(output));
      await Gal.requestAccess(); await Gal.putImage(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Full-resolution photo exported to Gallery and Downloads.')));
    } catch(e) {
      if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: '+e.toString())));
    } finally {
      if(mounted) setState(()=>saving=false);
    }
  }
  Future<void> exportSocialSize() async {
    if (photo == null || saving) return;
    setState(() => saving = true);
    try {
      final path = await exportPreviewAtSocialSize(context: context, previewKey: previewKey);
      if (path != null && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Exported social image: ${path.split(Platform.pathSeparator).last}')),
        );
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: $e')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Widget control(String name,double value,double min,double max,ValueChanged<double> update) => Column(crossAxisAlignment: CrossAxisAlignment.start,children:[
    Row(children:[Expanded(child:Text(name)),Text(value.toStringAsFixed(2),style:const TextStyle(color:_gold))]),
    Slider(value:value,min:min,max:max,onChanged:original?null:(v)=>setState(() { update(v); preset='Custom'; }))
  ]);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Professional Photo Editor  •  PRO')),
    body: ListView(padding:const EdgeInsets.all(16),children:[
      FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PixelMagicAiStudio())),icon:const Icon(Icons.auto_awesome),label:const Text('Open AI Image & Video Generator')),
      if(photo==null) InkWell(onTap:choose,child:Container(height:230,decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(18),border:Border.all(color:_gold)),child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.add_photo_alternate,size:54,color:_gold),SizedBox(height:10),Text('Choose a photo to edit')])))
      else ...[
        RepaintBoundary(key:previewKey,child:AspectRatio(aspectRatio:cropAspect,child:ClipRRect(borderRadius:BorderRadius.circular(16),child:ColoredBox(color:_panel,child:Stack(fit:StackFit.expand,children:[original?Image.file(File(photo!.path),fit:BoxFit.cover):Transform.rotate(angle:rotation,child:Transform(alignment:Alignment.center,transform:Matrix4.identity()..scale((flip?-1.0:1.0)*zoom,zoom),child:ColorFiltered(colorFilter:ColorFilter.matrix(matrix),child:ImageFiltered(imageFilter:ui.ImageFilter.blur(sigmaX:blur,sigmaY:blur),child:Image.file(File(photo!.path),fit:BoxFit.contain))))),if(overlayText.isNotEmpty) Center(child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),color:Colors.black45,child:Text(overlayText,style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold)))),if(frameWidth>0) DecoratedBox(decoration:BoxDecoration(border:Border.all(color:Colors.white,width:frameWidth*4))) ]))))),
        Row(children:[Expanded(child:Text('Preset: '+preset)),TextButton.icon(onPressed:()=>setState(()=>original=!original),icon:const Icon(Icons.compare),label:Text(original?'Show edit':'Before / After'))]),
        control('Brightness / Exposure',brightness,-.5,.5,(v)=>brightness=v),
        control('Contrast',contrast,.5,1.8,(v)=>contrast=v),
        control('Saturation',saturation,0,2,(v)=>saturation=v),
        control('Temperature',warmth,-1,1,(v)=>warmth=v),
        control('Tint · Green / Magenta',tint,-1,1,(v)=>tint=v),
        const SizedBox(height:8),
        const Text('RGB / HSL Fine Tuning',style:TextStyle(fontWeight:FontWeight.bold)),
        control('Red channel',redMix,.5,1.8,(v)=>redMix=v),
        control('Green channel',greenMix,.5,1.8,(v)=>greenMix=v),
        control('Blue channel',blueMix,.5,1.8,(v)=>blueMix=v),
        const Text('01 · Professional Color Lab',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:6),
        const Text('Professional presets',style:TextStyle(fontWeight:FontWeight.bold)),
        Wrap(spacing:7,children:['Original','Cinematic','Vivid','Warm','Cool','Matte','B&W','Moody','Sepia','Soft','High Key','Low Key'].map((p)=>ChoiceChip(label:Text(p),selected:preset==p,onSelected:(_)=>setPreset(p))).toList()),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:saveCustomPreset,icon:const Icon(Icons.bookmark_add),label:const Text('Save custom preset')),
          OutlinedButton.icon(onPressed:applyCustomPreset,icon:const Icon(Icons.bookmark),label:const Text('Apply saved preset')),
        ]),
        const SizedBox(height:16),
        const Text('02 · Composition & Crop',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        DropdownButton<double>(
          value: cropAspect,
          isExpanded: true,
          items: const [
            DropdownMenuItem(value: 1, child: Text('Square · 1:1')),
            DropdownMenuItem(value: .8, child: Text('Portrait · 4:5')),
            DropdownMenuItem(value: .75, child: Text('Portrait · 3:4')),
            DropdownMenuItem(value: 1.7777777778, child: Text('Landscape · 16:9')),
          ],
          onChanged: (v) => setState(() { cropAspect = v ?? .8; preset = 'Custom'; }),
        ),
        control('Crop / Zoom',zoom,1,2.5,(v)=>zoom=v),
        control('Lens blur',blur,0,8,(v)=>blur=v),
        control('Vignette',vignette,0,.85,(v)=>vignette=v),
        const SizedBox(height:10),
        const Text('03 · Creative Studio',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        control('Frame thickness',frameWidth,0,4,(v)=>frameWidth=v),
        OutlinedButton.icon(onPressed:() async {
          final t=TextEditingController(text:overlayText);
          final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Add photo title / watermark'),content:TextField(controller:t,maxLength:40),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,t.text.trim()),child:const Text('Apply'))]));
          t.dispose(); if(value!=null&&mounted)setState(()=>overlayText=value);
        },icon:const Icon(Icons.text_fields),label:const Text('Add text / watermark')),
        const SizedBox(height:10),
        const Text('04 · Transform',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:()=>setState(()=>rotation+=1.57079632679),icon:const Icon(Icons.rotate_right),label:const Text('Rotate 90°')),
          OutlinedButton.icon(onPressed:()=>setState(()=>flip=!flip),icon:const Icon(Icons.flip),label:const Text('Flip')),
          OutlinedButton.icon(onPressed:()=>setState(() { rotation=0; flip=false; }),icon:const Icon(Icons.restart_alt),label:const Text('Reset')),
        ]),
        FilledButton.icon(onPressed:saving?null:save,icon:const Icon(Icons.high_quality),label:Text(saving?'Exporting…':'Export PNG')),
       OutlinedButton.icon(onPressed:saving?null:exportSocialSize,icon:const Icon(Icons.aspect_ratio),label:const Text('Download in Facebook / Instagram / WhatsApp / YouTube size')),
       OutlinedButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const LogoWallpaperStudio())),icon:const Icon(Icons.wallpaper),label:const Text('Open Wallpaper & Banner Templates Studio  •  PRO')),
        OutlinedButton.icon(onPressed:choose,icon:const Icon(Icons.photo_library),label:const Text('Change photo')),
      ],
      const SizedBox(height:18),
      _planned(Icons.auto_fix_high,'AI Retouch & Object Eraser','Requires a dedicated AI model/API; not active yet.'),
      Card(color:_panel,child:ListTile(
        leading:const Icon(Icons.layers,color:_gold),
        title:const Text('Remove Person Background'),
        subtitle:const Text('On-device person segmentation · no API charge',style:TextStyle(color:Colors.white54,fontSize:11)),
        trailing:const Icon(Icons.arrow_forward_ios,size:16),
        onTap:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const BackgroundRemoverScreen())),
      )),
      _planned(Icons.tune,'HSL Mixer, RGB Curves & Healing Brush','Advanced precision tools are planned for the next phase.'),
    ]),
    floatingActionButton:photo==null?FloatingActionButton.extended(onPressed:choose,icon:const Icon(Icons.photo_library),label:const Text('Choose photo')):null,
  );
}

class ProVideoEditorScreen extends StatefulWidget {
  const ProVideoEditorScreen({super.key});
  @override
  State<ProVideoEditorScreen> createState()=>_ProVideoEditorScreenState();
}
class _ProVideoEditorScreenState extends State<ProVideoEditorScreen> {
  final picker=ImagePicker();
  VideoPlayerController? controller;
  bool busy=false;
  String? status,error;
  double start=0,end=0,speed=1,volume=1,gradeBrightness=0,gradeContrast=1,gradeSaturation=1,cropFraction=.85;
  int exportHeight=1080, exportFps=30, exportBitrate=8;
  String filter='Original';
  VideoExportSettings? videoExportSettings;
  bool hasSavedProject=false;
  @override
  void initState(){super.initState();_checkSavedProject();}
  Future<void> _checkSavedProject() async {
    final prefs=await SharedPreferences.getInstance();
    if(mounted)setState(()=>hasSavedProject=prefs.containsKey('pixelmagic_pro_video_project'));
  }
  Future<void> _saveProject() async {
    final c=controller;if(c==null)return;
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString('pixelmagic_pro_video_project',jsonEncode({
      'path':c.dataSource,'start':start,'end':end,'speed':speed,'volume':volume,
      'brightness':gradeBrightness,'contrast':gradeContrast,'saturation':gradeSaturation,
      'crop':cropFraction,'filter':filter,'exportHeight':exportHeight,'exportFps':exportFps,'exportBitrate':exportBitrate,
    }));
    if(mounted){setState(()=>hasSavedProject=true);ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('PRO editing project saved on this device.')));}
  }
  Future<void> _resumeProject() async {
    final prefs=await SharedPreferences.getInstance();
    final raw=prefs.getString('pixelmagic_pro_video_project');if(raw==null)return;
    try{
      final data=jsonDecode(raw) as Map<String,dynamic>;final path=data['path'] as String;
      if(!await File(path).exists()){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Saved source video is no longer available.')));return;}
      await load(path);
      if(!mounted)return;
      setState((){
        start=(data['start'] as num?)?.toDouble()??0;
        end=(data['end'] as num?)?.toDouble()??end;
        speed=(data['speed'] as num?)?.toDouble()??1;
        volume=(data['volume'] as num?)?.toDouble()??1;
        gradeBrightness=(data['brightness'] as num?)?.toDouble()??0;
        gradeContrast=(data['contrast'] as num?)?.toDouble()??1;
        gradeSaturation=(data['saturation'] as num?)?.toDouble()??1;
        cropFraction=(data['crop'] as num?)?.toDouble()??.85;
        filter=(data['filter'] as String?)??'Original';
        exportHeight=(data['exportHeight'] as int?)??1080;
        exportFps=(data['exportFps'] as int?)??30;
        exportBitrate=(data['exportBitrate'] as int?)??8;
      });
    }catch(_){if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Could not restore saved project.')));}
  }
  Future<void> choose() async { final p=await picker.pickVideo(source:ImageSource.gallery); if(p!=null) await load(p.path); }
  Future<void> load(String path) async {
    setState(()=>busy=true); await controller?.dispose();
    final c=VideoPlayerController.file(File(path));
    try { await c.initialize(); if(!mounted){await c.dispose();return;} setState(() { controller=c; start=0; end=c.value.duration.inMilliseconds/1000; busy=false; error=null; status=null; }); }
    catch(_){await c.dispose();if(mounted)setState(() { busy=false; error='This video could not be opened.'; });}
  }
  Future<void> run(Future<String> Function(String) task,String done) async {
    final c=controller; if(c==null||busy)return;
    setState(() { busy=true; error=null; status='Processing on this device…'; });
    try { await c.pause(); final output=await task(c.dataSource); await load(output); if(mounted)setState(()=>status=done); try{await Gal.requestAccess();await Gal.putVideo(output);}catch(_){} }
    catch(e){if(mounted)setState(()=>error=e.toString().replaceFirst('Exception: ',''));}
    finally{if(mounted)setState(()=>busy=false);}
  }
  String? backgroundPath;
  Future<void> chooseBackground() async {
    final p=await FilePicker.platform.pickFiles(type:FileType.custom,allowedExtensions:['jpg','jpeg','png','mp4','mov','m4v']);
    final path=p?.files.single.path;
    if(path!=null&&mounted)setState(()=>backgroundPath=path);
  }
  Future<void> music({bool mix=false}) async {final p=await FilePicker.platform.pickFiles(type:FileType.audio);final path=p?.files.single.path;if(path!=null)await run((v)=>mix?LocalVideoEngine.mixMusic(input:v,audio:path,musicVolume:.35,originalVolume:volume):LocalVideoEngine.addMusic(input:v,audio:path),'${mix?'Original audio and music mixed':'Music track replaced'} and exported.');}
  Future<void> title() async {
    final t=TextEditingController();
    final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(title:const Text('Add title'),content:TextField(controller:t,maxLength:80),actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Cancel')),FilledButton(onPressed:()=>Navigator.pop(ctx,t.text.trim()),child:const Text('Apply'))]));
    t.dispose(); if(value==null||value.isEmpty)return;
    final seconds=(controller?.value.duration.inMilliseconds??0)/1000;
    await run((v)=>LocalVideoEngine.addText(input:v,text:value,seconds:seconds),'Title added and exported.');
  }
  Future<void> merge() async {final p=await picker.pickVideo(source:ImageSource.gallery);if(p!=null&&controller!=null)await run((v)=>LocalVideoEngine.merge(first:v,second:p.path),'Clips merged.');}
  String time(Duration d)=>d.inMinutes.remainder(60).toString().padLeft(2,'0')+':'+d.inSeconds.remainder(60).toString().padLeft(2,'0');
  @override
  void dispose(){controller?.dispose();super.dispose();}
  @override
  Widget build(BuildContext context){
    final c=controller; final duration=c?.value.duration??Duration.zero; final max=duration.inMilliseconds/1000;
    return Scaffold(appBar:AppBar(title:const Text('Professional Video Editor  •  PRO')),body:ListView(padding:const EdgeInsets.all(16),children:[
      FilledButton.icon(onPressed:()=>Navigator.push(context,MaterialPageRoute(builder:(_)=>const PixelMagicAiStudio())),icon:const Icon(Icons.auto_awesome),label:const Text('Open AI Image & Video Generator')),
      if(c==null) ...[
        InkWell(onTap:busy?null:choose,child:Container(height:220,decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(18),border:Border.all(color:_gold)),child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.video_library,size:54,color:_gold),SizedBox(height:10),Text('Choose a video for PRO editing')]))),
        if(hasSavedProject) OutlinedButton.icon(onPressed:busy?null:_resumeProject,icon:const Icon(Icons.restore),label:const Text('Resume saved project')),
      ] else ...[
        ClipRRect(borderRadius:BorderRadius.circular(14),child:AspectRatio(aspectRatio:c.value.aspectRatio,child:VideoPlayer(c))),
        Row(children:[IconButton.filled(onPressed:busy?null:()=>setState(()=>c.value.isPlaying?c.pause():c.play()),icon:Icon(c.value.isPlaying?Icons.pause:Icons.play_arrow)),Expanded(child:VideoProgressIndicator(c,allowScrubbing:!busy,padding:const EdgeInsets.all(12))),Text(time(c.value.position)+' / '+time(duration),style:const TextStyle(fontSize:10))]),
        OutlinedButton.icon(onPressed:busy?null:choose,icon:const Icon(Icons.video_file),label:const Text('Choose another video')),
        OutlinedButton.icon(onPressed:busy?null:_saveProject,icon:const Icon(Icons.save),label:const Text('Save editing project')),
        if(hasSavedProject) TextButton.icon(onPressed:busy?null:_resumeProject,icon:const Icon(Icons.restore),label:const Text('Resume last saved project')),
        const Text('01 · Timeline & Clip Editing',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        if(max>1)RangeSlider(min:0,max:max,values:RangeValues(start.clamp(0,max),end.clamp(0,max)),onChanged:busy?null:(v)=>setState(() { start=v.start; end=v.end; })),
        FilledButton.tonalIcon(onPressed:busy||end<=start?null:()=>run((v)=>LocalVideoEngine.trim(input:v,start:Duration(milliseconds:(start*1000).round()),end:Duration(milliseconds:(end*1000).round())),'Trimmed video exported.'),icon:const Icon(Icons.content_cut),label:const Text('Trim and export')),
        const SizedBox(height:12),const Text('02 · Speed & Motion',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        _slider('Speed',speed,.5,2,'×',(v)=>speed=v),
        FilledButton.tonalIcon(onPressed:busy||speed==1?null:()=>run((v)=>LocalVideoEngine.setSpeed(input:v,speed:speed),'Speed updated.'),icon:const Icon(Icons.speed),label:const Text('Apply speed')),
        _slider('Volume',volume,0,2,'',(v)=>volume=v),
        FilledButton.tonalIcon(onPressed:busy||volume==1?null:()=>run((v)=>LocalVideoEngine.setVolume(input:v,volume:volume),'Volume updated.'),icon:const Icon(Icons.volume_up),label:const Text('Apply volume')),
        const SizedBox(height:12),const Text('03 · Professional Color Grading',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        _slider('Brightness',gradeBrightness,-.5,.5,'',(v)=>gradeBrightness=v),
        _slider('Contrast',gradeContrast,.5,1.8,'×',(v)=>gradeContrast=v),
        _slider('Saturation',gradeSaturation,0,2,'×',(v)=>gradeSaturation=v),
        FilledButton.tonalIcon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.adjustColor(input:v,brightness:gradeBrightness,contrast:gradeContrast,saturation:gradeSaturation),'Manual color grade applied.'),icon:const Icon(Icons.tune),label:const Text('Apply manual color grade')),
        const SizedBox(height:12),const Text('Crop & Framing',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        _slider('Center crop',cropFraction,.5,1,'',(v)=>cropFraction=v),
        FilledButton.tonalIcon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.crop(input:v,fraction:cropFraction),'Video crop applied.'),icon:const Icon(Icons.crop),label:const Text('Apply crop')),
        Wrap(spacing:7,runSpacing:7,children:['Original','Cinematic','Vintage','Retro','B&W','HDR','Vivid','Warm','Cool','Film','Moody','Portrait'].map((p)=>ChoiceChip(label:Text(p),selected:filter==p,onSelected:busy||p=='Original'?null:(_)=>setState(()=>filter=p))).toList()),
        FilledButton.tonalIcon(onPressed:busy||filter=='Original'?null:()=>run((v)=>LocalVideoEngine.applyFilter(input:v,filter:filter),filter+' look applied.'),icon:const Icon(Icons.color_lens),label:const Text('Apply selected look')),
        Wrap(spacing:8,runSpacing:8,children:[
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.sharpen(input:v),'Sharpen applied.'),icon:const Icon(Icons.hdr_strong),label:const Text('Sharpen')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.vignette(input:v),'Vignette applied.'),icon:const Icon(Icons.lens_blur),label:const Text('Vignette')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.denoise(input:v),'Video noise reduction applied.'),icon:const Icon(Icons.auto_fix_high),label:const Text('Denoise')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.sepia(input:v),'Sepia look applied.'),icon:const Icon(Icons.filter_vintage),label:const Text('Sepia')),
        ]),
        const SizedBox(height:12),const Text('04 · Audio Studio',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:busy?null:()=>music(),icon:const Icon(Icons.music_note),label:const Text('Replace music')),
          OutlinedButton.icon(onPressed:busy?null:()=>music(mix:true),icon:const Icon(Icons.graphic_eq),label:const Text('Mix music + original')),
          OutlinedButton.icon(onPressed:busy?null:title,icon:const Icon(Icons.text_fields),label:const Text('Add title')),
          OutlinedButton.icon(onPressed:busy?null:merge,icon:const Icon(Icons.call_merge),label:const Text('Merge clip')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.fadeAudio(input:v,durationSeconds:duration.inMilliseconds/1000),'Audio fade in/out applied.'),icon:const Icon(Icons.graphic_eq),label:const Text('Audio fade')),
        ]),
        const SizedBox(height:12),const Text('05 · Background, Effects & Motion',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.reverse(input:v),'Video reversed.'),icon:const Icon(Icons.swap_horiz),label:const Text('Reverse')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.fade(input:v,durationSeconds:duration.inMilliseconds/1000),'Fade in/out applied.'),icon:const Icon(Icons.gradient),label:const Text('Fade transition')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.rotate(input:v),'Rotated 90 degrees.'),icon:const Icon(Icons.rotate_right),label:const Text('Rotate 90°')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.flip(input:v),'Video flipped horizontally.'),icon:const Icon(Icons.flip),label:const Text('Flip')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.mute(input:v),'Audio removed.'),icon:const Icon(Icons.volume_off),label:const Text('Mute')),
        ]),
        OutlinedButton.icon(onPressed:busy?null:chooseBackground,icon:const Icon(Icons.wallpaper),label:Text(backgroundPath==null?'Choose photo/video background':'Background selected')),
        FilledButton.tonalIcon(onPressed:busy||backgroundPath==null?null:()=>run((v)=>LocalVideoEngine.chromaKeyBackground(input:v,background:backgroundPath!),'Green-screen background replaced. Use a solid green source.'),icon:const Icon(Icons.layers),label:const Text('Replace green background')),
        const SizedBox(height:12),const Text('06 · Export Quality',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        DropdownButton<int>(value:exportHeight,isExpanded:true,items:const [720,1080,1440,2160].map((h)=>DropdownMenuItem(value:h,child:Text(h==2160?'4K UHD':h==1440?'2K QHD':h==1080?'1080p Full HD':'720p HD'))).toList(),onChanged:busy?null:(v)=>setState(()=>exportHeight=v??1080)),
        DropdownButton<int>(value:exportFps,isExpanded:true,items:const [24,25,30,50,60].map((v)=>DropdownMenuItem(value:v,child:Text('$v FPS'))).toList(),onChanged:busy?null:(v)=>setState(()=>exportFps=v??30)),
        DropdownButton<int>(value:exportBitrate,isExpanded:true,items:const [2,4,8,12,20].map((v)=>DropdownMenuItem(value:v,child:Text('$v Mbps · bitrate'))).toList(),onChanged:busy?null:(v)=>setState(()=>exportBitrate=v??8)),
        FilledButton.tonalIcon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.exportAdvanced(input:v,height:exportHeight,fps:exportFps,bitrateMbps:exportBitrate),'Exported at selected resolution, FPS and bitrate.'),icon:const Icon(Icons.high_quality),label:const Text('Export with quality settings')),
      ],
      if(busy)const Padding(padding:EdgeInsets.all(14),child:Center(child:CircularProgressIndicator())),
      if(status!=null)Text(status!,style:const TextStyle(color:_gold)),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.redAccent)),
      const SizedBox(height:14),
      _planned(Icons.person_search,'AI Video Background Removal','AI segmentation for normal backgrounds still needs a dedicated video model/API.'),
      _planned(Icons.timeline,'Multi-track timeline, keyframes & motion tracking','Needs a dedicated non-linear editing project engine; not active yet.'),
      _planned(Icons.high_quality,'2K / 4K export, speed ramp & advanced transitions','Not active yet; device performance and codec support must be tested.'),
    ]),floatingActionButton:c==null?FloatingActionButton.extended(onPressed:choose,icon:const Icon(Icons.video_library),label:const Text('Choose video')):null);
  }
  Widget _slider(String title,double value,double min,double max,String suffix,ValueChanged<double> change)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(title)),Text(value.toStringAsFixed(2)+suffix,style:const TextStyle(color:_gold))]),Slider(value:value,min:min,max:max,onChanged:busy?null:(v)=>setState(()=>change(v)))]);
}
Widget _planned(IconData icon,String title,String detail)=>Card(color:_panel,child:ListTile(leading:Icon(icon,color:_gold),title:Text(title),subtitle:Text(detail,style:const TextStyle(color:Colors.white54,fontSize:11)),trailing:const Icon(Icons.hourglass_top,color:Colors.white38)));
