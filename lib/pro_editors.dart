// ignore_for_file: deprecated_member_use, prefer_interpolation_to_compose_strings

import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:gal/gal.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart';
import 'local_downloads.dart';
import 'local_video_engine.dart';

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
  double rotation = 0, zoom = 1, frameWidth = 0;
  bool flip = false, original = false, saving = false;
  String preset = 'Original';
  String overlayText = '';

  List<double> get matrix {
    final s = saturation, c = contrast;
    final r = .213 * (1 - s), g = .715 * (1 - s), b = .072 * (1 - s);
    return [
      (r+s)*c,g*c,b*c,0,128*(1-c)+brightness*255+warmth*32,
      r*c,(g+s)*c,b*c,0,128*(1-c)+brightness*255,
      r*c,g*c,(b+s)*c,0,128*(1-c)+brightness*255-warmth*32,
      0,0,0,1,0
    ];
  }

  Future<void> choose() async {
    final p = await picker.pickImage(source: ImageSource.gallery, imageQuality: 100);
    if (p != null && mounted) setState(() { photo=p; brightness=0; contrast=1; saturation=1; warmth=0; rotation=0; zoom=1; frameWidth=0; flip=false; preset='Original'; original=false; overlayText=''; });
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
    });
  }
  Future<void> save() async {
    if (photo==null || saving) return;
    setState(()=>saving=true);
    try {
      final boundary=previewKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary==null) throw Exception('Preview is not ready');
      final image=await boundary.toImage(pixelRatio: 3);
      final data=await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data==null) throw Exception('Could not render image');
      final path=await LocalDownloads.saveImageBytes(data.buffer.asUint8List());
      await Gal.requestAccess(); await Gal.putImage(path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('PRO photo exported to Gallery and Downloads.')));
    } catch(e) { if(mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Export failed: '+e.toString()))); }
    finally { if(mounted) setState(()=>saving=false); }
  }
  Widget control(String name,double value,double min,double max,ValueChanged<double> update) => Column(crossAxisAlignment: CrossAxisAlignment.start,children:[
    Row(children:[Expanded(child:Text(name)),Text(value.toStringAsFixed(2),style:const TextStyle(color:_gold))]),
    Slider(value:value,min:min,max:max,onChanged:original?null:(v)=>setState(() { update(v); preset='Custom'; }))
  ]);
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Professional Photo Editor  •  PRO')),
    body: ListView(padding:const EdgeInsets.all(16),children:[
      if(photo==null) InkWell(onTap:choose,child:Container(height:230,decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(18),border:Border.all(color:_gold)),child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.add_photo_alternate,size:54,color:_gold),SizedBox(height:10),Text('Choose a photo to edit')])))
      else ...[
        RepaintBoundary(key:previewKey,child:AspectRatio(aspectRatio:4/5,child:ClipRRect(borderRadius:BorderRadius.circular(16),child:ColoredBox(color:_panel,child:Stack(fit:StackFit.expand,children:[original?Image.file(File(photo!.path),fit:BoxFit.contain):Transform.rotate(angle:rotation,child:Transform(alignment:Alignment.center,transform:Matrix4.identity()..scale((flip?-1.0:1.0)*zoom,zoom),child:ColorFiltered(colorFilter:ColorFilter.matrix(matrix),child:Image.file(File(photo!.path),fit:BoxFit.contain)))),if(overlayText.isNotEmpty) Center(child:Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:6),color:Colors.black45,child:Text(overlayText,style:const TextStyle(color:Colors.white,fontSize:22,fontWeight:FontWeight.bold)))),if(frameWidth>0) DecoratedBox(decoration:BoxDecoration(border:Border.all(color:Colors.white,width:frameWidth*4))) ]))))),
        Row(children:[Expanded(child:Text('Preset: '+preset)),TextButton.icon(onPressed:()=>setState(()=>original=!original),icon:const Icon(Icons.compare),label:Text(original?'Show edit':'Before / After'))]),
        control('Brightness / Exposure',brightness,-.5,.5,(v)=>brightness=v),
        control('Contrast',contrast,.5,1.8,(v)=>contrast=v),
        control('Saturation',saturation,0,2,(v)=>saturation=v),
        control('Temperature',warmth,-1,1,(v)=>warmth=v),
        const Text('01 · Professional Color Lab',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        const SizedBox(height:6),
        const Text('Professional presets',style:TextStyle(fontWeight:FontWeight.bold)),
        Wrap(spacing:7,children:['Original','Cinematic','Vivid','Warm','Cool','Matte','B&W','Moody'].map((p)=>ChoiceChip(label:Text(p),selected:preset==p,onSelected:(_)=>setPreset(p))).toList()),
        const SizedBox(height:16),
        const Text('02 · Composition & Crop',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        control('Crop / Zoom',zoom,1,2.5,(v)=>zoom=v),
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
        OutlinedButton.icon(onPressed:choose,icon:const Icon(Icons.photo_library),label:const Text('Change photo')),
      ],
      const SizedBox(height:18),
      _planned(Icons.auto_fix_high,'AI Retouch & Object Eraser','Requires a dedicated AI model/API; not active yet.'),
      _planned(Icons.layers,'AI Background Studio & Selective Masks','AI subject masks and background replacement are not active yet.'),
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
  double start=0,end=0,speed=1,volume=1;
  String filter='Original';
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
  Future<void> music() async {final p=await FilePicker.platform.pickFiles(type:FileType.audio);final path=p?.files.single.path;if(path!=null)await run((v)=>LocalVideoEngine.addMusic(input:v,audio:path),'Music added and exported.');}
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
      if(c==null) InkWell(onTap:busy?null:choose,child:Container(height:220,decoration:BoxDecoration(color:_panel,borderRadius:BorderRadius.circular(18),border:Border.all(color:_gold)),child:const Column(mainAxisAlignment:MainAxisAlignment.center,children:[Icon(Icons.video_library,size:54,color:_gold),SizedBox(height:10),Text('Choose a video for PRO editing')])))
      else ...[
        ClipRRect(borderRadius:BorderRadius.circular(14),child:AspectRatio(aspectRatio:c.value.aspectRatio,child:VideoPlayer(c))),
        Row(children:[IconButton.filled(onPressed:busy?null:()=>setState(()=>c.value.isPlaying?c.pause():c.play()),icon:Icon(c.value.isPlaying?Icons.pause:Icons.play_arrow)),Expanded(child:VideoProgressIndicator(c,allowScrubbing:!busy,padding:const EdgeInsets.all(12))),Text(time(c.value.position)+' / '+time(duration),style:const TextStyle(fontSize:10))]),
        OutlinedButton.icon(onPressed:busy?null:choose,icon:const Icon(Icons.video_file),label:const Text('Choose another video')),
        const Text('01 · Timeline & Clip Editing',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        if(max>1)RangeSlider(min:0,max:max,values:RangeValues(start.clamp(0,max),end.clamp(0,max)),onChanged:busy?null:(v)=>setState(() { start=v.start; end=v.end; })),
        FilledButton.tonalIcon(onPressed:busy||end<=start?null:()=>run((v)=>LocalVideoEngine.trim(input:v,start:Duration(milliseconds:(start*1000).round()),end:Duration(milliseconds:(end*1000).round())),'Trimmed video exported.'),icon:const Icon(Icons.content_cut),label:const Text('Trim and export')),
        const SizedBox(height:12),const Text('02 · Speed & Motion',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        _slider('Speed',speed,.5,2,'×',(v)=>speed=v),
        FilledButton.tonalIcon(onPressed:busy||speed==1?null:()=>run((v)=>LocalVideoEngine.setSpeed(input:v,speed:speed),'Speed updated.'),icon:const Icon(Icons.speed),label:const Text('Apply speed')),
        _slider('Volume',volume,0,2,'',(v)=>volume=v),
        FilledButton.tonalIcon(onPressed:busy||volume==1?null:()=>run((v)=>LocalVideoEngine.setVolume(input:v,volume:volume),'Volume updated.'),icon:const Icon(Icons.volume_up),label:const Text('Apply volume')),
        const SizedBox(height:12),const Text('03 · Professional Color Grading',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        Wrap(spacing:7,runSpacing:7,children:['Original','Cinematic','Vintage','Retro','B&W','HDR','Vivid','Warm','Cool','Film','Moody','Portrait'].map((p)=>ChoiceChip(label:Text(p),selected:filter==p,onSelected:busy||p=='Original'?null:(_)=>setState(()=>filter=p))).toList()),
        FilledButton.tonalIcon(onPressed:busy||filter=='Original'?null:()=>run((v)=>LocalVideoEngine.applyFilter(input:v,filter:filter),filter+' look applied.'),icon:const Icon(Icons.color_lens),label:const Text('Apply selected look')),
        const SizedBox(height:12),const Text('04 · Audio Studio',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:busy?null:music,icon:const Icon(Icons.music_note),label:const Text('Add music')),
          OutlinedButton.icon(onPressed:busy?null:title,icon:const Icon(Icons.text_fields),label:const Text('Add title')),
          OutlinedButton.icon(onPressed:busy?null:merge,icon:const Icon(Icons.call_merge),label:const Text('Merge clip')),
        ]),
        const SizedBox(height:12),const Text('05 · Background, Effects & Motion',style:TextStyle(fontWeight:FontWeight.bold,fontSize:16)),
        Wrap(spacing:8,children:[
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.reverse(input:v),'Video reversed.'),icon:const Icon(Icons.swap_horiz),label:const Text('Reverse')),
          OutlinedButton.icon(onPressed:busy?null:()=>run((v)=>LocalVideoEngine.fade(input:v),'Fade in/out applied.'),icon:const Icon(Icons.gradient),label:const Text('Fade transition')),
        ]),
        OutlinedButton.icon(onPressed:busy?null:chooseBackground,icon:const Icon(Icons.wallpaper),label:Text(backgroundPath==null?'Choose photo/video background':'Background selected')),
        FilledButton.tonalIcon(onPressed:busy||backgroundPath==null?null:()=>run((v)=>LocalVideoEngine.chromaKeyBackground(input:v,background:backgroundPath!),'Green-screen background replaced. Use a solid green source.'),icon:const Icon(Icons.layers),label:const Text('Replace green background')),
      ],
      if(busy)const Padding(padding:EdgeInsets.all(14),child:Center(child:CircularProgressIndicator())),
      if(status!=null)Text(status!,style:const TextStyle(color:_gold)),
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.redAccent)),
      const SizedBox(height:14),
      _planned(Icons.person_search,'AI Video Background Removal','AI segmentation for normal backgrounds still needs a dedicated video model/API.'),
      _planned(Icons.person_search,'AI Video Background Removal','Requires a video segmentation model or configured AI video API.'),
      _planned(Icons.timeline,'Multi-track timeline, keyframes & motion tracking','Requires a dedicated non-linear editing project engine.'),
      _planned(Icons.timeline,'Multi-track timeline, keyframes & motion tracking','Needs a dedicated non-linear editing project engine; not active yet.'),
      _planned(Icons.high_quality,'2K / 4K export, speed ramp & advanced transitions','Not active yet; device performance and codec support must be tested.'),
    ]),floatingActionButton:c==null?FloatingActionButton.extended(onPressed:choose,icon:const Icon(Icons.video_library),label:const Text('Choose video')):null);
  }
  Widget _slider(String title,double value,double min,double max,String suffix,ValueChanged<double> change)=>Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Row(children:[Expanded(child:Text(title)),Text(value.toStringAsFixed(2)+suffix,style:const TextStyle(color:_gold))]),Slider(value:value,min:min,max:max,onChanged:busy?null:(v)=>setState(()=>change(v)))]);
}
Widget _planned(IconData icon,String title,String detail)=>Card(color:_panel,child:ListTile(leading:Icon(icon,color:_gold),title:Text(title),subtitle:Text(detail,style:const TextStyle(color:Colors.white54,fontSize:11)),trailing:const Icon(Icons.hourglass_top,color:Colors.white38)));
