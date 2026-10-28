import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'youtube_page.dart';

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
class Playlist {
  Playlist(this.name, {List<String>? paths}) : paths = paths ?? [];
  String name;
  final List<String> paths;
  Map<String, dynamic> toJson() => {'name': name, 'paths': paths};
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
    j['name'] as String? ?? 'Playlist',
    paths: (j['paths'] as List? ?? []).whereType<String>().toList(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}
class _HomePageState extends State<HomePage> {
  static const effectsChannel = MethodChannel('nextune/audio_effects');
  final AudioPlayer player = AudioPlayer();
  final List<Track> tracks = [];
  final List<Playlist> playlists = [];
  int current = -1, tab = 0;
  int? audioSessionId;
  Playlist? selectedPlaylist;
  bool ready = false, shuffle = false;
  int repeatMode = 0; // 0 = off, 1 = current track, 2 = playlist
  String effect = 'Normal';

  @override
  void initState() {
    super.initState();
    player.androidAudioSessionIdStream.listen((id) {
      audioSessionId = id;
      applyEffect(effect);
    });
    player.processingStateStream.listen((state) async {
      if (state != ProcessingState.completed || tracks.isEmpty || current < 0) return;
      if (repeatMode == 1) { await play(current); return; }
      if (shuffle && tracks.length > 1) {
        final choices = List<int>.generate(tracks.length, (i) => i).where((i) => i != current).toList()..shuffle();
        await play(choices.first);
      } else if (current + 1 < tracks.length) {
        await play(current + 1);
      } else if (repeatMode == 2) {
        await play(0);
      }
    });
    load();
  }
  Future<void> load() async {
    final p = await SharedPreferences.getInstance();
    try {
      final raw = p.getString('tracks');
      if (raw != null) tracks.addAll((jsonDecode(raw) as List).map((e) => Track.fromJson(Map<String,dynamic>.from(e))));
      final savedPlaylists = p.getString('playlists');
      if (savedPlaylists != null) playlists.addAll((jsonDecode(savedPlaylists) as List).map((e) => Playlist.fromJson(Map<String,dynamic>.from(e))));
    } catch (_) {}
    if (mounted) setState(() => ready = true);
  }
  Future<void> save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tracks', jsonEncode(tracks.map((t) => t.toJson()).toList()));
    await p.setString('playlists', jsonEncode(playlists.map((p) => p.toJson()).toList()));
  }
  Future<void> applyEffect(String value) async {
    effect = value;
    if (value == 'Nightcore') {
      await player.setSpeed(1.2);
    } else if (value == 'Slowed + Reverb') {
      await player.setSpeed(0.85);
    } else {
      await player.setSpeed(1.0);
    }
    try {
      await effectsChannel.invokeMethod('setEffect', {'sessionId': audioSessionId, 'effect': value});
    } catch (_) {}
    if (mounted) setState(() {});
  }
  Future<void> createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Nouvelle playlist'),
      content: TextField(controller: controller, autofocus: true, maxLength: 40,
        decoration: const InputDecoration(hintText: 'Ex. : Night drive'),
        onSubmitted: (v) => Navigator.pop(context, v.trim())),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Créer')),
      ],
    ));
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    if (playlists.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cette playlist existe déjà.')));
      return;
    }
    playlists.add(Playlist(name.trim()));
    await save();
    if (mounted) setState(() {});
  }
  Future<void> addToPlaylist(Track track) async {
    if (playlists.isEmpty) {
      await createPlaylist();
      if (playlists.isEmpty) return;
    }
    final chosen = await showModalBottomSheet<Playlist>(context: context, backgroundColor: surface,
      builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Ajouter à une playlist', style: TextStyle(fontWeight: FontWeight.bold))),
        ...playlists.map((p) => ListTile(leading: const Icon(Icons.queue_music, color: violet),
          title: Text(p.name), subtitle: Text('${p.paths.length} titres'), onTap: () => Navigator.pop(context, p))),
      ])));
    if (chosen == null) return;
    if (!chosen.paths.contains(track.path)) chosen.paths.add(track.path);
    await save();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ajouté à « ${chosen.name} »')));
    }
  }
  Future<void> renamePlaylist(Playlist playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Renommer la playlist'),
      content: TextField(controller: controller, autofocus: true, maxLength: 40),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Enregistrer')),
      ],
    ));
    controller.dispose();
    if (name == null || name.isEmpty) return;
    playlist.name = name;
    await save();
    if (mounted) setState(() {});
  }
  Future<void> deletePlaylist(Playlist playlist) async {
    final ok = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Supprimer cette playlist ?'),
      content: Text('« ${playlist.name} » sera supprimée. Les fichiers audio resteront sur ton téléphone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
      ],
    ));
    if (ok != true) return;
    playlists.remove(playlist);
    if (selectedPlaylist == playlist) selectedPlaylist = null;
    await save();
    if (mounted) setState(() {});
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
      NavigationBar(backgroundColor:const Color(0xFF101017),indicatorColor:violet.withValues(alpha:.2),selectedIndex:tab,onDestinationSelected:(v) { if (v == 4) player.pause(); setState(() { tab=v; selectedPlaylist=null; }); },destinations:const [
        NavigationDestination(icon:Icon(Icons.home_outlined),selectedIcon:Icon(Icons.home),label:'Accueil'),
        NavigationDestination(icon:Icon(Icons.queue_music),label:'Playlists'),
        NavigationDestination(icon:Icon(Icons.favorite_border),selectedIcon:Icon(Icons.favorite),label:'Favoris'),
        NavigationDestination(icon:Icon(Icons.tune),label:'Réglages'),
        NavigationDestination(icon:Icon(Icons.smart_display_outlined),selectedIcon:Icon(Icons.smart_display),label:'YouTube')
      ])
    ])));
  }

  Widget page() {
    if (tab == 4) return const YoutubePage();
    if (tab == 3) return ListView(padding:const EdgeInsets.all(20),children:[
      const Text('Réglages',style:TextStyle(fontSize:28,fontWeight:FontWeight.w900)),
      const SizedBox(height:8),const Text('Tes données restent sur ton appareil.',style:TextStyle(color:Colors.white54)),
      const SizedBox(height:24),
      setting(Icons.save_alt,'Exporter une sauvegarde','Exporter les titres et favoris',exportBackup),
      setting(Icons.file_open,'Importer une sauvegarde','Restaurer les métadonnées',importBackup),
      const SizedBox(height:24),const Text('ÉGALISEUR — APERÇU',style:TextStyle(color:violet,letterSpacing:1.5,fontWeight:FontWeight.bold)),
      const SizedBox(height:12),
      ...['Bass Boost','BassMax','Nightcore','Slowed + Reverb','Normal'].map((e)=>RadioListTile<String>(value:e,groupValue:effect,title:Text(e),activeColor:violet,onChanged:(v) { if (v != null) applyEffect(v); })),
      const Text('Nightcore et Slowed changent la vitesse en direct. Bass Boost et BassMax activent le traitement audio Android lorsqu’il est pris en charge.',style:TextStyle(color:Colors.white38,fontSize:12))
    ]);
    if (tab == 1) {
      if (selectedPlaylist != null) {
        final playlist = selectedPlaylist!;
        final list = tracks.where((t) => playlist.paths.contains(t.path)).toList();
        return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
          Row(children: [
            IconButton(onPressed: () => setState(() => selectedPlaylist = null), icon: const Icon(Icons.arrow_back)),
            Expanded(child: Text(playlist.name, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900))),
            IconButton(onPressed: () => renamePlaylist(playlist), icon: const Icon(Icons.edit_outlined)),
            IconButton(onPressed: () => deletePlaylist(playlist), icon: const Icon(Icons.delete_outline, color: Colors.redAccent)),
          ]),
          Text('${list.length} titres • fichiers locaux disponibles hors connexion', style: const TextStyle(color: Colors.white54)),
          const SizedBox(height: 16),
          if (list.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Text('Playlist vide. Ajoute des titres depuis ta bibliothèque.', textAlign: TextAlign.center)),
          ...list.map((t) => ListTile(
            leading: const Icon(Icons.music_note, color: violet),
            title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: const Text('Fichier local'),
            onTap: () => play(tracks.indexOf(t)),
            trailing: IconButton(icon: const Icon(Icons.remove_circle_outline), onPressed: () async { playlist.paths.remove(t.path); await save(); if (mounted) setState(() {}); }),
          )),
        ]);
      }
      return ListView(padding: const EdgeInsets.fromLTRB(20, 8, 20, 24), children: [
        Row(children: [
          const Expanded(child: Text('Tes playlists', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900))),
          FilledButton.icon(onPressed: createPlaylist, icon: const Icon(Icons.add), label: const Text('Créer')),
        ]),
        const SizedBox(height: 8),
        const Text('Tes playlists sont enregistrées sur ce téléphone.', style: TextStyle(color: Colors.white54)),
        const SizedBox(height: 16),
        if (playlists.isEmpty) Container(padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(20)), child: const Column(children: [
          Icon(Icons.queue_music, size: 42, color: violet), SizedBox(height: 10),
          Text('Crée ta première playlist', style: TextStyle(fontWeight: FontWeight.bold)),
          SizedBox(height: 6), Text('Puis ajoute tes titres depuis la bibliothèque.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
        ...playlists.map((p) => Container(margin: const EdgeInsets.only(bottom: 9), decoration: BoxDecoration(color: surface, borderRadius: BorderRadius.circular(16)), child: ListTile(
          leading: Container(width: 46, height: 46, decoration: BoxDecoration(color: violet.withValues(alpha: .15), borderRadius: BorderRadius.circular(12)), child: const Icon(Icons.queue_music, color: violet)),
          title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          subtitle: Text('${p.paths.length} titres'),
          onTap: () => setState(() => selectedPlaylist = p),
          trailing: PopupMenuButton<String>(onSelected: (v) { if (v == 'rename') renamePlaylist(p); if (v == 'delete') deletePlaylist(p); }, itemBuilder: (_) => const [
            PopupMenuItem(value: 'rename', child: Text('Renommer')),
            PopupMenuItem(value: 'delete', child: Text('Supprimer')),
          ]),
        ))),
      ]);
    }
    final list = tab == 2 ? tracks.where((t)=>t.favorite).toList() : tracks;
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
      Row(children:[Expanded(child:Text(tab==2?'Tes favoris':'Ta bibliothèque',style:const TextStyle(fontSize:20,fontWeight:FontWeight.bold))),Text('${list.length} titres',style:const TextStyle(color:Colors.white54,fontSize:12))]),
      const SizedBox(height:12),
      if(list.isEmpty) Container(padding:const EdgeInsets.all(26),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(20)),child:const Column(children:[Icon(Icons.album_outlined,size:42,color:violet),SizedBox(height:10),Text('Ta musique commence ici',style:TextStyle(fontWeight:FontWeight.bold)),SizedBox(height:6),Text('Importe des fichiers audio depuis ton téléphone.',textAlign:TextAlign.center,style:TextStyle(color:Colors.white54,fontSize:12))]))
      else ...list.map((t) {
        final i=tracks.indexOf(t), active=i==current;
        return Container(margin:const EdgeInsets.only(bottom:8),decoration:BoxDecoration(color:active?violet.withValues(alpha:.13):surface,borderRadius:BorderRadius.circular(15)),child:ListTile(onTap:()=>play(i),leading:Container(width:42,height:42,decoration:BoxDecoration(color:const Color(0xFF292438),borderRadius:BorderRadius.circular(12)),child:Icon(active&&player.playing?Icons.equalizer:Icons.music_note,color:violet)),title:Text(t.title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontWeight:FontWeight.w600,color:active?violet:Colors.white)),subtitle:const Text('Fichier local',style:TextStyle(fontSize:11,color:Colors.white54)),trailing:Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(onPressed: () => addToPlaylist(t), tooltip: 'Ajouter à une playlist', icon: const Icon(Icons.playlist_add, color: violet)),
          IconButton(onPressed:()async{setState(()=>t.favorite=!t.favorite);await save();},icon:Icon(t.favorite?Icons.favorite:Icons.favorite_border,color:t.favorite?const Color(0xFFFF6C9D):Colors.white38)),
        ])));
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
    Row(mainAxisAlignment: MainAxisAlignment.end, children: [
      IconButton(visualDensity: VisualDensity.compact, tooltip: 'Lecture aléatoire', onPressed: () => setState(() => shuffle = !shuffle), icon: Icon(Icons.shuffle_rounded, size: 19, color: shuffle ? violet : Colors.white38)),
      IconButton(visualDensity: VisualDensity.compact, tooltip: repeatMode == 0 ? 'Répétition désactivée' : repeatMode == 1 ? 'Répéter ce titre' : 'Répéter la playlist', onPressed: () => setState(() => repeatMode = (repeatMode + 1) % 3), icon: Icon(repeatMode == 1 ? Icons.repeat_one_rounded : Icons.repeat_rounded, size: 19, color: repeatMode == 0 ? Colors.white38 : violet)),
      const SizedBox(width: 8),
    ]),
    StreamBuilder<Duration?>(stream:player.durationStream,builder:(c,d)=>StreamBuilder<Duration>(stream:player.positionStream,builder:(c,p){
      final max=(d.data??Duration.zero).inMilliseconds.toDouble().clamp(1.0,double.infinity).toDouble();
      final value=(p.data??Duration.zero).inMilliseconds.toDouble().clamp(0.0,max).toDouble();
      return Slider(padding:EdgeInsets.zero,value:value,max:max,onChanged:(v)=>player.seek(Duration(milliseconds:v.round())));
    }))
  ]));
}
