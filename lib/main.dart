import 'dart:convert';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'youtube_page.dart';

const ink = Color(0xFF090A0F);
const surface = Color(0xFF141620);
const surface2 = Color(0xFF1D2030);
const violet = Color(0xFFB8A1FF);
const cyan = Color(0xFF83E8D0);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NextuneApp());
}

class NextuneApp extends StatelessWidget {
  const NextuneApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nextune', debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true, brightness: Brightness.dark, scaffoldBackgroundColor: ink,
      colorScheme: ColorScheme.fromSeed(seedColor: violet, brightness: Brightness.dark),
      sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
    ),
    home: const PlayerHome(),
  );
}

class Song {
  Song({required this.path, required this.title, this.artist = 'Artiste inconnu', this.album = '', this.cover, this.favorite = false});
  final String path;
  String title, artist, album;
  String? cover;
  bool favorite;
  Map<String, dynamic> toJson() => {'path':path,'title':title,'artist':artist,'album':album,'cover':cover,'favorite':favorite};
  factory Song.fromJson(Map<String,dynamic> j) => Song(
    path: j['path'] as String, title: j['title'] as String? ?? 'Sans titre',
    artist: j['artist'] as String? ?? 'Artiste inconnu', album: j['album'] as String? ?? '',
    cover: j['cover'] as String?, favorite: j['favorite'] == true,
  );
}
class MusicList {
  MusicList(this.name, {List<String>? paths}) : paths = paths ?? [];
  String name; final List<String> paths;
  Map<String,dynamic> toJson() => {'name':name,'paths':paths};
  factory MusicList.fromJson(Map<String,dynamic> j) => MusicList(j['name'] as String? ?? 'Playlist', paths:(j['paths'] as List? ?? []).whereType<String>().toList());
}

class PlayerHome extends StatefulWidget {
  const PlayerHome({super.key});
  @override State<PlayerHome> createState() => _PlayerHomeState();
}
class _PlayerHomeState extends State<PlayerHome> {
  static const _fx = MethodChannel('nextune/audio_effects');
  final AudioPlayer player = AudioPlayer();
  final List<Song> songs = [];
  final List<MusicList> playlists = [];
  int tab = 0, current = -1, repeat = 0;
  int? sessionId;
  bool ready = false, shuffle = false;
  String preset = 'Original';
  double pitch = 1, speed = 1, bass = 0, treble = 0, reverb = 0;

  Song? get now => current >= 0 && current < songs.length ? songs[current] : null;
  @override void initState() {
    super.initState();
    player.androidAudioSessionIdStream.listen((id) { sessionId = id; _applyFx(); });
    player.processingStateStream.listen((state) { if (state == ProcessingState.completed) _advance(); });
    _restore();
  }
  Future<void> _restore() async {
    final p = await SharedPreferences.getInstance();
    try {
      songs.addAll((jsonDecode(p.getString('tracks') ?? '[]') as List).map((x) => Song.fromJson(Map<String,dynamic>.from(x))));
      playlists.addAll((jsonDecode(p.getString('playlists') ?? '[]') as List).map((x) => MusicList.fromJson(Map<String,dynamic>.from(x))));
    } catch (_) {}
    if (mounted) setState(() => ready = true);
  }
  Future<void> _save() async {
    final p = await SharedPreferences.getInstance();
    await p.setString('tracks', jsonEncode(songs.map((s) => s.toJson()).toList()));
    await p.setString('playlists', jsonEncode(playlists.map((s) => s.toJson()).toList()));
  }
  Future<void> _importSongs() async {
    final picked = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (picked == null) return;
    var added = 0;
    for (final f in picked.files) {
      final path = f.path;
      if (path == null || songs.any((s) => s.path == path)) continue;
      var title = f.name.replaceAll(RegExp(r'\.[^.]+$'), '');
      const artist = 'Artiste inconnu';
      songs.add(Song(path:path, title:title, artist:artist));
      added++;
    }
    await _save();
    if (mounted) { setState(() {}); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$added titre(s) importé(s)'))); }
    if (current < 0 && songs.isNotEmpty) await _play(0);
  }
  Future<void> _play(int index) async {
    if (index < 0 || index >= songs.length) return;
    try {
      await player.setFilePath(songs[index].path);
      if (!mounted) return;
      setState(() => current = index);
      await player.setSpeed(speed);
      try { await player.setPitch(pitch); } catch (_) {}
      await _applyFx();
      await player.play();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Fichier inaccessible ou format non pris en charge. Réimporte le titre si nécessaire.')));
    }
  }
  Future<void> _toggle() async {
    if (now == null) { if (songs.isEmpty) { await _importSongs(); } else { await _play(0); } }
    else if (player.playing) { await player.pause(); }
    else { await player.play(); }
    if (mounted) setState(() {});
  }
  Future<void> _advance() async {
    if (songs.isEmpty || current < 0) return;
    if (repeat == 1) { await _play(current); return; }
    if (shuffle && songs.length > 1) {
      final options = List.generate(songs.length, (i) => i)..remove(current)..shuffle();
      await _play(options.first); return;
    }
    if (current + 1 < songs.length) { await _play(current + 1); }
    else if (repeat == 2) { await _play(0); }
  }
  Future<void> _previous() async {
    if (now == null) return;
    if (player.position > const Duration(seconds: 3)) { await player.seek(Duration.zero); return; }
    await _play(current <= 0 ? songs.length - 1 : current - 1);
  }
  Future<void> _applyFx() async {
    try { await _fx.invokeMethod('setEffect', {'sessionId':sessionId,'effect':preset,'bass':bass,'treble':treble,'reverb':reverb}); } catch (_) {}
  }
  Future<void> _setPreset(String name) async {
    setState(() {
      preset = name;
      switch(name) {
        case 'Nightcore': speed = 1.12; pitch = 1.22; bass = .15; reverb = 0; break;
        case 'Slowed + Reverb': speed = .82; pitch = .85; reverb = .8; bass = .1; break;
        case 'Bass Boost': speed = 1; pitch = 1; bass = .75; reverb = 0; break;
        case 'BassMax': speed = 1; pitch = 1; bass = 1; reverb = .1; break;
        case 'Dream': speed = .95; pitch = 1.03; reverb = .7; bass = .1; break;
        default: speed = 1; pitch = 1; bass = 0; treble = 0; reverb = 0;
      }
    });
    try { await player.setSpeed(speed); } catch (_) {}
    try { await player.setPitch(pitch); } catch (_) {}
    await _applyFx();
  }
  Future<void> _setPitch(double v) async { setState(() { pitch=v; preset='Personnalisé'; }); try { await player.setPitch(v); } catch (_) {} }
  Future<void> _setSpeed(double v) async { setState(() { speed=v; preset='Personnalisé'; }); try { await player.setSpeed(v); } catch (_) {} }
  Future<void> _newPlaylist() async {
    final c = TextEditingController();
    final name = await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Nouvelle playlist'),content:TextField(controller:c,autofocus:true,decoration:const InputDecoration(hintText:'Late night, Nightcore…')),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(ctx,c.text.trim()),child:const Text('Créer'))]));
    c.dispose();
    if (name == null || name.isEmpty) return;
    playlists.add(MusicList(name)); await _save(); if(mounted)setState((){});
  }
  Future<void> _addToPlaylist(Song song) async {
    if (playlists.isEmpty) await _newPlaylist();
    if (!mounted || playlists.isEmpty) return;
    final chosen = await showModalBottomSheet<MusicList>(context:context,backgroundColor:surface,builder:(ctx)=>SafeArea(child:ListView(shrinkWrap:true,children:[
      const ListTile(title:Text('Ajouter à la playlist')),
      ...playlists.map((p)=>ListTile(title:Text(p.name),leading:const Icon(Icons.queue_music,color:violet),onTap:()=>Navigator.pop(ctx,p)))
    ])));
    if (chosen == null) return;
    if (!chosen.paths.contains(song.path)) chosen.paths.add(song.path);
    await _save(); if(mounted)setState((){});
  }
  Future<void> _export() async {
    final f = File('${Directory.systemTemp.path}/nextune-backup.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert({'tracks':songs.map((s)=>s.toJson()).toList(),'playlists':playlists.map((p)=>p.toJson()).toList()}));
    await Share.shareXFiles([XFile(f.path)],text:'Sauvegarde Nextune');
  }
  @override void dispose() { player.dispose(); super.dispose(); }

  @override Widget build(BuildContext context) => Scaffold(
    body: SafeArea(child: Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(20,14,20,12),child:Row(children:[
        Container(width:42,height:42,decoration:BoxDecoration(gradient:const LinearGradient(colors:[violet,cyan]),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.graphic_eq_rounded,color:ink,size:27)),
        const SizedBox(width:11),
        const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('nextune',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900,letterSpacing:-.7)),Text('YOUR SOUND, REIMAGINED',style:TextStyle(fontSize:9,color:Colors.white54,letterSpacing:1.6))])),
        IconButton(onPressed:_importSongs,icon:const Icon(Icons.add_circle_outline_rounded,color:violet,size:27)),
      ])),
      Expanded(child:!ready?const Center(child:CircularProgressIndicator()):IndexedStack(index:tab,children:[
        _home(),_library(favorites:true),_playlistsPage(),_effects(),const YoutubePage()
      ])),
      if(now != null) _miniPlayer(),
      NavigationBar(
        backgroundColor:const Color(0xFF101119),indicatorColor:violet.withValues(alpha:.17),
        selectedIndex:tab,onDestinationSelected:(v)=>setState(()=>tab=v),
        destinations:const [
          NavigationDestination(icon:Icon(Icons.grid_view_rounded),label:'Découvrir'),
          NavigationDestination(icon:Icon(Icons.favorite_border),selectedIcon:Icon(Icons.favorite),label:'Favoris'),
          NavigationDestination(icon:Icon(Icons.queue_music_rounded),label:'Playlists'),
          NavigationDestination(icon:Icon(Icons.equalizer_rounded),label:'Studio'),
          NavigationDestination(icon:Icon(Icons.play_circle_outline_rounded),selectedIcon:Icon(Icons.play_circle),label:'YouTube'),
        ],
      )
    ])),
  );

  Widget _home() => ListView(padding:const EdgeInsets.fromLTRB(20,8,20,25),children:[
    Container(
      padding:const EdgeInsets.all(22),clipBehavior:Clip.antiAlias,
      decoration:BoxDecoration(gradient:const LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF292541),Color(0xFF151822),Color(0xFF102725)]),borderRadius:BorderRadius.circular(28),border:Border.all(color:Colors.white.withValues(alpha:.07))),
      child:Stack(children:[
        Positioned(right:-16,top:-16,child:Icon(Icons.graphic_eq_rounded,size:140,color:Colors.white.withValues(alpha:.045))),
        Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          const Text('YOUR PERSONAL\nSOUND SPACE',style:TextStyle(fontSize:28,height:1.06,fontWeight:FontWeight.w900,letterSpacing:-.8)),
          const SizedBox(height:9),const Text('Tes morceaux. Tes effets. Ton univers.',style:TextStyle(color:Colors.white70,fontSize:12)),
          const SizedBox(height:18),Wrap(spacing:9,runSpacing:9,children:[
            FilledButton.icon(onPressed:_importSongs,icon:const Icon(Icons.add_rounded),label:const Text('Importer')),
            OutlinedButton.icon(onPressed:()=>setState(()=>tab=4),icon:const Icon(Icons.play_arrow_rounded),label:const Text('YouTube')),
          ])
        ])
      ]),
    ),
    const SizedBox(height:25),
    Row(children:[const Expanded(child:Text('EN COURS DE LECTURE',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1,fontSize:12))),Text('${songs.length} titres',style:const TextStyle(color:Colors.white54,fontSize:11))]),
    const SizedBox(height:12),
    if(now != null) _featuredPlayer() else _empty('Aucun morceau lancé','Importe tes fichiers audio ou découvre de la musique sur YouTube.',Icons.album_rounded),
    const SizedBox(height:26),
    Row(children:[const Expanded(child:Text('TA BIBLIOTHÈQUE',style:TextStyle(fontSize:17,fontWeight:FontWeight.w900))),TextButton(onPressed:_importSongs,child:const Text('Ajouter +'))]),
    const SizedBox(height:4),
    if(songs.isEmpty) _empty('Une bibliothèque à toi','Ajoute des fichiers audio pour commencer.',Icons.library_music_rounded)
    else ...songs.take(8).toList().asMap().entries.map((e)=>_songTile(e.value,e.key,compact:true)),
    if(songs.length>8) Center(child:TextButton(onPressed:()=>setState(()=>tab=1),child:const Text('Voir les favoris'))),
  ]);

  Widget _featuredPlayer() {
    final s=now!;
    return Container(padding:const EdgeInsets.all(15),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(24),border:Border.all(color:violet.withValues(alpha:.15))),child:Column(children:[
      ClipRRect(borderRadius:BorderRadius.circular(19),child:AspectRatio(aspectRatio:1,child:_art(s,fit:BoxFit.cover))),
      const SizedBox(height:15),
      Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(s.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:18,fontWeight:FontWeight.w900)),
        const SizedBox(height:4),Text(s.artist,style:const TextStyle(color:Colors.white54,fontSize:12)),
        if(s.album.isNotEmpty) Text(s.album,style:const TextStyle(color:Colors.white38,fontSize:10)),
      ])),IconButton(onPressed:()async{setState(()=>s.favorite=!s.favorite);await _save();},icon:Icon(s.favorite?Icons.favorite:Icons.favorite_border,color:s.favorite?const Color(0xFFFF7895):violet))]),
      _progress(),
      Row(mainAxisAlignment:MainAxisAlignment.spaceEvenly,children:[
        IconButton(onPressed:()=>setState(()=>shuffle=!shuffle),color:shuffle?cyan:Colors.white54,icon:const Icon(Icons.shuffle_rounded)),
        IconButton(onPressed:_previous,icon:const Icon(Icons.skip_previous_rounded,size:34)),
        StreamBuilder<PlayerState>(stream:player.playerStateStream,builder:(ctx,snap)=>IconButton(onPressed:_toggle,icon:Icon(snap.data?.playing==true?Icons.pause_circle_filled_rounded:Icons.play_circle_fill_rounded,size:58,color:violet))),
        IconButton(onPressed:_advance,icon:const Icon(Icons.skip_next_rounded,size:34)),
        IconButton(onPressed:()=>setState(()=>repeat=(repeat+1)%3),color:repeat>0?cyan:Colors.white54,icon:Icon(repeat==1?Icons.repeat_one_rounded:Icons.repeat_rounded)),
      ]),
    ]));
  }

  Widget _progress()=>StreamBuilder<Duration?>(stream:player.durationStream,builder:(ctx,d)=>StreamBuilder<Duration>(stream:player.positionStream,builder:(ctx,p){
    final duration=d.data??Duration.zero; final max=duration.inMilliseconds.toDouble().clamp(1.0,double.infinity).toDouble();
    final value=(p.data??Duration.zero).inMilliseconds.toDouble().clamp(0.0,max).toDouble();
    String time(Duration x)=>'${x.inMinutes.toString().padLeft(2,'0')}:${(x.inSeconds%60).toString().padLeft(2,'0')}';
    return Column(children:[Slider(value:value,min:0,max:max,onChanged:(v)=>player.seek(Duration(milliseconds:v.round())),activeColor:violet,inactiveColor:Colors.white12),Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(time(p.data??Duration.zero),style:const TextStyle(color:Colors.white38,fontSize:10)),Text(time(duration),style:const TextStyle(color:Colors.white38,fontSize:10))])]);
  }));

  Widget _library({bool favorites=false}) {
    final list=favorites?songs.where((s)=>s.favorite).toList():songs;
    return ListView(padding:const EdgeInsets.fromLTRB(20,12,20,25),children:[
      Text(favorites?'TES FAVORIS':'TOUTE TA MUSIQUE',style:const TextStyle(fontSize:23,fontWeight:FontWeight.w900)),
      const SizedBox(height:5),Text('${list.length} morceau(x)',style:const TextStyle(color:Colors.white54,fontSize:12)),
      const SizedBox(height:18),
      if(list.isEmpty)_empty(favorites?'Pas encore de favoris':'Bibliothèque vide',favorites?'Ajoute tes morceaux préférés avec le cœur.':'Importe des fichiers audio depuis ton appareil.',favorites?Icons.favorite_border:Icons.library_music_rounded)
      else ...list.map((s)=>_songTile(s,songs.indexOf(s))),
    ]);
  }
  Widget _songTile(Song s,int index,{bool compact=false})=>Container(margin:const EdgeInsets.only(bottom:9),decoration:BoxDecoration(color:index==current?const Color(0xFF222337):surface,borderRadius:BorderRadius.circular(17),border:Border.all(color:index==current?violet.withValues(alpha:.25):Colors.white.withValues(alpha:.025))),child:ListTile(
    onTap:()=>_play(index),contentPadding: EdgeInsets.symmetric(horizontal:11,vertical:compact?1:4),
    leading:ClipRRect(borderRadius:BorderRadius.circular(12),child:SizedBox(width:compact?47:54,height:compact?47:54,child:_art(s))),
    title:Text(s.title,maxLines:1,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:13,fontWeight:FontWeight.w800,color:index==current?violet:Colors.white)),
    subtitle:Text(s.artist,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:11,color:Colors.white54)),
    trailing:PopupMenuButton<String>(onSelected:(v)async{if(v=='fav'){setState(()=>s.favorite=!s.favorite);await _save();}if(v=='playlist')await _addToPlaylist(s);if(v=='play')await _play(index);},itemBuilder:(_)=>[
      PopupMenuItem(value:'fav',child:Text(s.favorite?'Retirer des favoris':'Ajouter aux favoris')),
      const PopupMenuItem(value:'playlist',child:Text('Ajouter à une playlist')),
      const PopupMenuItem(value:'play',child:Text('Lire maintenant')),
    ]),
  ));
  Widget _art(Song s,{BoxFit fit=BoxFit.cover}) {
    if(s.cover!=null){try{return Image.memory(base64Decode(s.cover!),fit:fit,errorBuilder:(_,__,___)=>_artFallback());}catch(_){}}
    return _artFallback();
  }
  Widget _artFallback()=>Container(decoration:const BoxDecoration(gradient:LinearGradient(begin:Alignment.topLeft,end:Alignment.bottomRight,colors:[Color(0xFF6554A8),Color(0xFF192D40)])),child:const Center(child:Icon(Icons.graphic_eq_rounded,color:Colors.white70,size:36)));
  Widget _empty(String title,String subtitle,IconData icon)=>Container(padding:const EdgeInsets.all(25),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(22)),child:Column(children:[Icon(icon,size:40,color:violet),const SizedBox(height:12),Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),const SizedBox(height:6),Text(subtitle,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white54,fontSize:12,height:1.45))]));
  Widget _playlistsPage()=>ListView(padding:const EdgeInsets.fromLTRB(20,12,20,25),children:[
    Row(children:[const Expanded(child:Text('PLAYLISTS',style:TextStyle(fontSize:23,fontWeight:FontWeight.w900))),FilledButton.icon(onPressed:_newPlaylist,icon:const Icon(Icons.add),label:const Text('Créer'))]),
    const SizedBox(height:7),const Text('Fais une collection pour chaque ambiance.',style:TextStyle(color:Colors.white54,fontSize:12)),const SizedBox(height:17),
    if(playlists.isEmpty)_empty('Ta première playlist','Crée une collection puis ajoute tes morceaux via le menu de chaque titre.',Icons.queue_music_rounded),
    ...playlists.map((p){final items=songs.where((s)=>p.paths.contains(s.path)).toList();return Container(margin:const EdgeInsets.only(bottom:10),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(18)),child:ListTile(leading:Container(width:48,height:48,decoration:BoxDecoration(color:surface2,borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.queue_music_rounded,color:cyan)),title:Text(p.name,style:const TextStyle(fontWeight:FontWeight.w800)),subtitle:Text('${items.length} morceaux',style:const TextStyle(color:Colors.white54,fontSize:11)),onTap:()=>items.isNotEmpty?_play(songs.indexOf(items.first)):null,trailing:IconButton(icon:const Icon(Icons.delete_outline,color:Colors.white54),onPressed:()async{playlists.remove(p);await _save();if(mounted)setState((){});})));}),
    const SizedBox(height:14),OutlinedButton.icon(onPressed:_export,icon:const Icon(Icons.ios_share),label:const Text('Exporter une sauvegarde')),
  ]);
  Widget _effects()=>ListView(padding:const EdgeInsets.fromLTRB(20,12,20,28),children:[
    const Text('SOUND STUDIO',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900,letterSpacing:-.5)),
    const SizedBox(height:5),const Text('Sculpte ton son en direct.',style:TextStyle(color:Colors.white54,fontSize:12)),const SizedBox(height:19),
    Container(padding:const EdgeInsets.all(17),decoration:BoxDecoration(gradient:const LinearGradient(colors:[Color(0xFF27243E),Color(0xFF171A25)]),borderRadius:BorderRadius.circular(22)),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Text('PRESETS',style:TextStyle(fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1.4)),const SizedBox(height:12),
      Wrap(spacing:8,runSpacing:8,children:[
        _presetChip('Original',Icons.graphic_eq),_presetChip('Nightcore',Icons.bolt),_presetChip('Slowed + Reverb',Icons.waves),
        _presetChip('Bass Boost',Icons.speaker),_presetChip('BassMax',Icons.surround_sound),_presetChip('Dream',Icons.nightlight_round),
      ])
    ])),
    const SizedBox(height:12),
    _sliderCard('PITCH','Hauteur du son',pitch,.5,2,(v)=>_setPitch(v),left:'GRAVE',right:'AIGU'),
    _sliderCard('SPEED','Vitesse de lecture',speed,.5,2,(v)=>_setSpeed(v),left:'SLOWED',right:'NIGHTCORE'),
    _sliderCard('BASS','Renfort des basses',bass,0,1,(v)async{setState(()=>bass=v);await _applyFx();},left:'DOUX',right:'PUISSANT'),
    _sliderCard('TREBLE','Aigus',treble,0,1,(v)async{setState(()=>treble=v);await _applyFx();},left:'DOUX',right:'BRILLANT'),
    _sliderCard('REVERB','Ambiance / réverbération',reverb,0,1,(v)async{setState(()=>reverb=v);await _applyFx();},left:'SEC',right:'SPACIEUX'),
    const SizedBox(height:12),
    Container(padding:const EdgeInsets.all(14),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(16)),child:const Text('Les effets dépendent des capacités audio du téléphone. Le pitch et les effets sont appliqués aux fichiers locaux, pas au lecteur YouTube officiel.',style:TextStyle(color:Colors.white54,fontSize:11,height:1.45))),
    const SizedBox(height:15),
    ListTile(leading:const Icon(Icons.shuffle,color:cyan),title:const Text('Lecture aléatoire'),trailing:Switch(value:shuffle,onChanged:(v)=>setState(()=>shuffle=v))),
    ListTile(leading:const Icon(Icons.repeat,color:cyan),title:const Text('Répétition'),subtitle:Text(['Désactivée','Titre actuel','Toute la file'][repeat]),trailing:IconButton(onPressed:()=>setState(()=>repeat=(repeat+1)%3),icon:const Icon(Icons.sync_rounded))),
  ]);
  Widget _sliderCard(String title,String sub,double value,double min,double max,ValueChanged<double> onChanged,{required String left,required String right})=>Container(margin:const EdgeInsets.only(bottom:10),padding:const EdgeInsets.fromLTRB(15,14,15,10),decoration:BoxDecoration(color:surface,borderRadius:BorderRadius.circular(18)),child:Column(children:[
    Row(children:[Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(title,style:const TextStyle(fontSize:11,fontWeight:FontWeight.w900,letterSpacing:1.1)),const SizedBox(height:3),Text(sub,style:const TextStyle(color:Colors.white54,fontSize:11))])),Text('${value.toStringAsFixed(2)}×',style:const TextStyle(color:violet,fontWeight:FontWeight.w900))]),
    Slider(value:value.clamp(min,max).toDouble(),min:min,max:max,divisions:30,onChanged:onChanged,activeColor:violet,inactiveColor:Colors.white12),
    Row(mainAxisAlignment:MainAxisAlignment.spaceBetween,children:[Text(left,style:const TextStyle(color:Colors.white38,fontSize:9,letterSpacing:1)),Text(right,style:const TextStyle(color:Colors.white38,fontSize:9,letterSpacing:1))]),
  ]));
  Widget _presetChip(String name,IconData icon){final selected=preset==name;return ChoiceChip(selected:selected,onSelected:(_)=>_setPreset(name),avatar:Icon(icon,size:16,color:selected?ink:violet),label:Text(name),labelStyle:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:selected?ink:Colors.white),selectedColor:cyan,backgroundColor:surface2,side:BorderSide(color:selected?cyan:Colors.white12));}
  Widget _miniPlayer()=>Container(margin:const EdgeInsets.fromLTRB(10,0,10,8),padding:const EdgeInsets.fromLTRB(10,7,10,7),decoration:BoxDecoration(color:const Color(0xFF1C1C2B),borderRadius:BorderRadius.circular(18),border:Border.all(color:violet.withValues(alpha:.2))),child:Row(children:[
    ClipRRect(borderRadius:BorderRadius.circular(11),child:SizedBox(width:43,height:43,child:_art(now!))),
    const SizedBox(width:10),Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text(now!.title,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(fontWeight:FontWeight.w800,fontSize:12)),Text(now!.artist,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white54,fontSize:10))])),
    IconButton(onPressed:_previous,visualDensity:VisualDensity.compact,icon:const Icon(Icons.skip_previous_rounded)),
    StreamBuilder<PlayerState>(stream:player.playerStateStream,builder:(ctx,s)=>IconButton(onPressed:_toggle,visualDensity:VisualDensity.compact,icon:Icon(s.data?.playing==true?Icons.pause_rounded:Icons.play_arrow_rounded,color:violet,size:29))),
    IconButton(onPressed:_advance,visualDensity:VisualDensity.compact,icon:const Icon(Icons.skip_next_rounded)),
  ]));
}
