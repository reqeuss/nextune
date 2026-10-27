import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const NextuneApp());
const violet = Color(0xFF9B6BFF);
const surface = Color(0xFF171620);

class NextuneApp extends StatelessWidget {
  const NextuneApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nextune', debugShowCheckedModeBanner: false,
    theme: ThemeData(useMaterial3: true, brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF09090E),
      colorScheme: ColorScheme.fromSeed(seedColor: violet, brightness: Brightness.dark)),
    home: const HomePage(),
  );
}

class Track {
  Track(this.path, this.title, {this.favorite = false});
  final String path;
  final String title;
  bool favorite;
  Map<String, dynamic> toJson() => {'path': path, 'title': title, 'favorite': favorite};
  factory Track.fromJson(Map<String, dynamic> j) => Track(j['path'] as String, j['title'] as String, favorite: j['favorite'] == true);
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  final AudioPlayer player = AudioPlayer();
  final List<Track> tracks = [];
  int current = -1, tab = 0;
  bool ready = false;
  String effect = 'Normal';

  @override
  void initState() { super.initState(); load(); }
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString('tracks');
      if (raw != null) tracks.addAll((jsonDecode(raw) as List).map((e) => Track.fromJson(Map<String,dynamic>.from(e))));
    } catch (_) {}
    if (mounted) setState(() => ready = true);
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tracks', jsonEncode(tracks.map((t) => t.toJson()).toList()));
  }
  Future<void> add() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (result == null) return;
    for (final f in result.files) {
      if (f.path == null || tracks.any((t) => t.path == f.path)) continue;
      final name = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      tracks.add(Track(f.path!, name));
    }
    await save();
    if (mounted) setState(() {});
    if (current < 0 && tracks.isNotEmpty) play(0);
  }
  Future<void> play(int i) async {
    if (i < 0 || i >= tracks.length) return;
    try {
      await player.setFilePath(tracks[i].path);
      setState(() => current = i);
      await player.play();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lecture impossible pour ce fichier.')));
    }
  }
  Future<void> toggle() async {
    if (current < 0) { if (tracks.isEmpty) { await add(); } else { await play(0); } }
    else if (player.playing) { await player.pause(); }
    else { await player.play(); }
    if (mounted) setState(() {});
  }
  Future<void> next() async {
    if (tracks.isNotEmpty) await play(current < 0 || current + 1 >= tracks.length ? 0 : current + 1);
  }
  Future<void> previous() async {
    if (tracks.isEmpty) return;
    if (player.position.inSeconds > 3) { await player.seek(Duration.zero); return; }
    await play(current <= 0 ? tracks.length - 1 : current - 1);
  }
  Future<void> exportBackup() async {
    final f = File('${Directory.systemTemp.path}/nextune-backup.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert({'app':'Nextune','version':1,'tracks':tracks.map((t)=>t.toJson()).toList()}));
    await Share.shareXFiles([XFile(f.path)], text: 'Sauvegarde Nextune');
  }
  Future<void> importBackup() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (r == null || r.files.single.path == null) return;
    try {
      final data = jsonDecode(await File(r.files.single.path!).readAsString()) as Map<String,dynamic>;
      for (final item in (data['tracks'] as List)) {
        final t = Track.fromJson(Map<String,dynamic>.from(item));
        if (await File(t.path).exists() && !tracks.any((x)=>x.path==t.path)) tracks.add(t);
      }
      await save(); if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sauvegarde invalide.')));
    }
  }
  @override
  void dispose() { player.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final now = current >= 0 && current < tracks.length ? tracks[current] : null;
    return Scaffold(body: SafeArea(child: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(20,16,16,12), child: Row(children: [
        Container(width:44,height:44,decoration:BoxDecoration(gradient:const LinearGradient(colors:[violet,Color(0xFF5633B4)]),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.graphic_eq_rounded)),
        const SizedBox(width:12),
        const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('NEXTUNE',style:TextStyle(fontWeight:FontWeight.w900,fontSize:21,letterSpacing:2)),
          Text('YOUR SOUND. YOUR RULES.',style:TextStyle(fontSize:9,color:Colors.white54,letterSpacing:1.4))
        ])),
        IconButton(onPressed:add,icon:const Icon(Icons.add_circle_outline_rounded,color:violet,size:29))
      ])),
      Expanded(child: ready ? page() : const Center(child:CircularProgressIndicator())),
      if (now != null) miniPlayer(now),
      NavigationBar(backgroundColor:const Color(0xFF101017),indicatorColor:violet.withValues(alpha:.2),selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),destinations:const [
        NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Accueil'),
        NavigationDestination(icon:Icon(Icons.favorite_border),selectedIcon:Icon(Icons.favorite),label:'Favoris'),
        NavigationDestination(icon:Icon(Icons.tune),label:'Réglages')
      ])
    ])));
  }

  Widget page() {
    if (tab == 2) return ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Réglages',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),const Text('Tes données restent sur ton appareil.',style:TextStyle(color:Colors.white54)),
      const SizedBox(height:24),
      setting(Icons.save_alt,'Exporter une sauvegarde','Exporter les titres et favoris',exportBackup),
      setting(Icons.file_open,'Importer une sauvegarde','Restaurer les métadonnées',importBackup),
      const SizedBox(height:24),const Text('ÉGALISEUR — APERÇU',style:TextStyle(color:violet,letterSpacing:1.5,fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      ...['Bass Boost','BassMax','Nightcore','Slowed + Reverb','Normal'].map((e)=>RadioListTile<String>(value:e,groupValue:effect,title:Text(e),activeColor:violet,onChanged:(v)=>setState(()=>effect=v!))),
      const Text('Les effets sont pour le moment des aperçus : le traitement du son sera ajouté ensuite.',style:TextStyle(color:Colors.white38,fontSize:12))
    ]);
    final list = tab == 1 ? tracks.where((t)=>t.favorite).toList() : tracks;
    return ListView(padding:const EdgeInsets.fromLTRB(20,8,20,24),children:[
      if (tab == 0)
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF30234E), Color(0xFF14131D)],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: violet.withValues(alpha: .25)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'TON UNIVERS\\nSONORE.',
                style: TextStyle(
                  fontSize: 30,
                  height: 1.08,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Toute ta musique. À ta façon.',
                style: TextStyle(color: Colors.white60),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: add,
                icon: const Icon(Icons.library_music),
                label: const Text('Importer ma musique'),
              ),
            ],
          ),
        ),
      const SizedBox(height:24),
      Row(children:[Expanded(child:Text(tab==1?'Tes favoris':'Ta bibliothèque',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),Text('${list.length} titres',style:const TextStyle(color:Colors.white54,fontSize:12))]),
      const SizedBox(height:12),
      if(list.isEmpty) Container(padding:const EdgeInsets.all(26),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(20)),child:const Column(children:[Icon(Icons.album_outlined,size:42,color:violet),SizedBox(height:10),Text('Ta musique commence ici',style:TextStyle(fontWeight:FontWeight.bold)),SizedBox(height:6),Text('Importe des fichiers audio depuis ton téléphone.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white54,fontSize:12))]))
      else ...list.map((t) {
        final i=tracks.indexOf(t), active=i==current;
        return Container(margin:const EdgeInsets.only(bottom:8),decoration:BoxDecoration(color:active?violet.withValues(alpha:.13):surface,borderRadius:BorderRadius.circular(15)),child:ListTile(onTap:()=>play(i),leading:Container(width:42,height:42,decoration:BoxDecoration(color:const Color(0xFF292438),borderRadius:BorderRadius.circular(12)),child:Icon(active&&player.playing?Icons.equalizer:Icons.music_note,color:violet)),title:Text(t.title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontWeight:FontWeight.w600,color:active?violet:Colors.white)),subtitle:const Text('Fichier local',style:TextStyle(fontSize:11,color:Colors.white54)),trailing:IconButton(onPressed:()async{setState(()=>t.favorite=!t.favorite);await save();},icon:Icon(t.favorite?Icons.favorite:Icons.favorite_border,color:t.favorite?const Color(0xFFFF6C9D):Colors.white38))));
      })
    ]);
  }

  Widget setting(IconData icon,String title,String sub,VoidCallback action)=>Container(margin:const EdgeInsets.only(bottom:10),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(16)),child:ListTile(leading:Icon(icon,color:violet),title:Text(title,style:const TextStyle(fontWeight:FontWeight.bold)),subtitle:Text(sub,style:const TextStyle(color:Colors.white54,fontSize:11)),trailing:const Icon(Icons.chevron_right),onTap:action));

  Widget miniPlayer(Track t)=>Container(margin:const EdgeInsets.fromLTRB(12,0,12,8),padding:const EdgeInsets.all(8),decoration:BoxDecoration(color:const Color(0xFF201B2E),borderRadius:BorderRadius.circular(17),border:Border.all(color:violet.withValues(alpha:.25))),child:Column(children:[
    Row(children:[
      Container(width:38,height:38,decoration:BoxDecoration(color:violet.withValues(alpha:.18),borderRadius:BorderRadius.circular(10)),child:const Icon(Icons.music_note,color:violet)),
      const SizedBox(width:9),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(t.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.bold,fontSize:13)),Text(effect,style:const TextStyle(color:violet,fontSize:10))])),
      IconButton(onPressed:previous,icon:const Icon(Icons.skip_previous_rounded)),
      StreamBuilder<PlayerState>(stream:player.playerStateStream,builder:(c,s)=>IconButton(onPressed:toggle,icon:Icon(s.data?.playing==true?Icons.pause_rounded:Icons.play_arrow_rounded,color:violet,size:30))),
      IconButton(onPressed:next,icon:const Icon(Icons.skip_next_rounded))
    ]),
    StreamBuilder<Duration?>(stream:player.durationStream,builder:(c,d)=>StreamBuilder<Duration>(stream:player.positionStream,builder:(c,p){
      final max=(d.data??Duration.zero).inMilliseconds.toDouble().clamp(1.0,double.infinity).toDouble();
      final value=(p.data??Duration.zero).inMilliseconds.toDouble().clamp(0.0,max).toDouble();
      return Slider(padding:EdgeInsets.zero,value:value,max:max,onChanged:(v)=>player.seek(Duration(milliseconds:v.round())));
    }))
  ]));
}
