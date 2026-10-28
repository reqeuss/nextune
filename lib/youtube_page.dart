import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

const ytAccent = Color(0xFFB8A1FF);
const ytSurface = Color(0xFF141620);
const ytSurface2 = Color(0xFF1D2030);
const ytMint = Color(0xFF83E8D0);

class YoutubeTrack {
  const YoutubeTrack({required this.id,required this.title,required this.channel,required this.thumbnail});
  final String id,title,channel,thumbnail;
  Map<String,dynamic> toJson()=>{'id':id,'title':title,'channel':channel,'thumbnail':thumbnail};
  factory YoutubeTrack.fromJson(Map<String,dynamic> j)=>YoutubeTrack(
    id:j['id'] as String? ?? '',title:j['title'] as String? ?? 'Sans titre',
    channel:j['channel'] as String? ?? 'YouTube',thumbnail:j['thumbnail'] as String? ?? '',
  );
}

class YoutubePage extends StatefulWidget {
  const YoutubePage({super.key});
  @override State<YoutubePage> createState()=>_YoutubePageState();
}
class _YoutubePageState extends State<YoutubePage> {
  static const String _buildApiKey=String.fromEnvironment('YOUTUBE_API_KEY');
  final TextEditingController _search=TextEditingController();
  final TextEditingController _keyInput=TextEditingController();
  final List<YoutubeTrack> _results=[],_recommendations=[],_queue=[],_history=[],_favorites=[];
  YoutubePlayerController? _player;
  YoutubeTrack? _current;
  String _apiKey=_buildApiKey;
  String? _error;
  bool _loading=false,_loadingRecommendations=false,_shuffle=false,_repeat=false,_showVideo=true;
  int _queueIndex=-1;
  int _section=0;

  @override void initState(){super.initState();_restore();}

  Future<void> _restore() async {
    final prefs=await SharedPreferences.getInstance();
    try {
      if(_buildApiKey.isEmpty)_apiKey=prefs.getString('youtubeApiKey')??'';
      _history.addAll(_decodeList(prefs.getString('ytHistory')));
      _favorites.addAll(_decodeList(prefs.getString('ytFavorites')));
    } catch (_) {}
    if(!mounted)return;
    setState((){});
    if(_apiKey.isNotEmpty) _loadRecommendations();
  }
  List<YoutubeTrack> _decodeList(String? raw){
    if(raw==null)return [];
    return (jsonDecode(raw) as List).map((x)=>YoutubeTrack.fromJson(Map<String,dynamic>.from(x))).where((x)=>x.id.isNotEmpty).toList();
  }
  Future<void> _saveLists() async {
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString('ytHistory',jsonEncode(_history.take(60).map((x)=>x.toJson()).toList()));
    await prefs.setString('ytFavorites',jsonEncode(_favorites.map((x)=>x.toJson()).toList()));
  }
  Future<void> _configureKey() async {
    if(_buildApiKey.isNotEmpty){
      if(!mounted)return;
      await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
        title:const Text('YouTube API configurée'),
        content:const Text('Nextune utilise le secret YOUTUBE_API_KEY injecté par GitHub Actions. La clé intégrée à une APK peut être extraite : garde cette APK pour ton usage personnel et limite la clé dans Google Cloud. La recherche exige YouTube Data API v3 activée et un quota disponible.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Compris'))],
      ));
      return;
    }
    _keyInput.text=_apiKey;
    final value=await showDialog<String>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Connecter YouTube'),
      content:Column(mainAxisSize:MainAxisSize.min,children:[
        const Text('Clé YouTube Data API v3',style:TextStyle(color:Colors.white70)),
        const SizedBox(height:10),
        TextField(controller:_keyInput,obscureText:true,autofocus:true,decoration:const InputDecoration(hintText:'AIza…',border:OutlineInputBorder())),
      ]),
      actions:[TextButton(onPressed:()=>Navigator.pop(ctx),child:const Text('Annuler')),FilledButton(onPressed:()=>Navigator.pop(ctx,_keyInput.text.trim()),child:const Text('Enregistrer'))],
    ));
    if(value==null||value.isEmpty)return;
    final prefs=await SharedPreferences.getInstance();
    await prefs.setString('youtubeApiKey',value);
    if(!mounted)return;
    setState((){_apiKey=value;_error=null;});
    await _loadRecommendations();
    if(_search.text.trim().isNotEmpty)await _find();
  }

  Future<List<YoutubeTrack>> _searchApi(String query,{int maxResults=15}) async {
    if(_apiKey.isEmpty)throw Exception('Clé API manquante. Ouvre les réglages YouTube.');
    final uri=Uri.https('www.googleapis.com','/youtube/v3/search',{
      'part':'snippet','type':'video','maxResults':'$maxResults','q':query,
      'key':_apiKey,'safeSearch':'moderate','videoEmbeddable':'true','videoSyndicated':'true',
    });
    final response=await http.get(uri).timeout(const Duration(seconds:18));
    Map<String,dynamic> data={};
    try{data=jsonDecode(response.body) as Map<String,dynamic>;}catch(_){}
    if(response.statusCode!=200){
      final error=data['error'] as Map<String,dynamic>?;
      final errors=error?['errors'] as List?;
      final firstError=errors!=null&&errors.isNotEmpty?errors.first:null;
      final reason=firstError is Map?firstError['reason']?.toString():null;
      final message=error?['message']?.toString()??'Erreur HTTP ${response.statusCode}';
      if(reason=='quotaExceeded'||message.toLowerCase().contains('quota'))throw Exception('Quota YouTube épuisé. Réessaie après la réinitialisation du quota.');
      if(response.statusCode==403)throw Exception('Accès refusé. Vérifie la clé, les restrictions et YouTube Data API v3.');
      if(response.statusCode==400)throw Exception('Paramètres de recherche refusés : $message');
      throw Exception(message);
    }
    final items=(data['items'] as List? ?? []).whereType<Map<String,dynamic>>();
    return items.map((item){
      final id=item['id'] as Map<String,dynamic>? ?? {};
      final snippet=item['snippet'] as Map<String,dynamic>? ?? {};
      final thumbs=snippet['thumbnails'] as Map<String,dynamic>? ?? {};
      final thumb=(thumbs['maxres']??thumbs['high']??thumbs['medium']??thumbs['default']) as Map<String,dynamic>?;
      return YoutubeTrack(id:id['videoId']?.toString()??'',title:_clean(snippet['title']?.toString()??'Sans titre'),channel:snippet['channelTitle']?.toString()??'YouTube',thumbnail:thumb?['url']?.toString()??'');
    }).where((t)=>t.id.isNotEmpty).toList();
  }
  String _clean(String s)=>s.replaceAll(RegExp(r'&amp;'),'&').replaceAll(RegExp(r'&#39;'),"'").replaceAll(RegExp(r'&quot;'),'"').replaceAll(RegExp(r'<[^>]*>'),'').trim();

  Future<void> _find() async {
    final q=_search.text.trim();if(q.isEmpty)return;
    FocusScope.of(context).unfocus();
    if(_apiKey.isEmpty){await _configureKey();if(_apiKey.isEmpty)return;}
    setState((){_loading=true;_error=null;_section=0;});
    try{
      final found=await _searchApi(q);
      if(!mounted)return;
      setState((){_results..clear()..addAll(found);_loading=false;});
      if(found.isEmpty)setState(()=>_error='Aucun résultat. Essaie un titre ou un artiste différent.');
    }catch(e){if(!mounted)return;setState((){_loading=false;_error=e.toString().replaceFirst('Exception: ','');});}
  }
  Future<void> _loadRecommendations() async {
    if(_apiKey.isEmpty||_loadingRecommendations)return;
    setState(()=>_loadingRecommendations=true);
    try{
      final recs=await _searchApi('popular music mix new releases nightcore',maxResults:12);
      if(!mounted)return;
      setState(()=>_recommendations..clear()..addAll(recs));
    }catch(e){
      if(mounted&&_recommendations.isEmpty)setState(()=>_error='Recommandations indisponibles : ${e.toString().replaceFirst('Exception: ','')}');
    }finally{if(mounted)setState(()=>_loadingRecommendations=false);}
  }
  Future<void> _recommendSimilar() async {
    final track=_current;if(track==null)return;
    setState(()=>_loadingRecommendations=true);
    try{
      final recs=await _searchApi('${track.title} similar songs ${track.channel}',maxResults:12);
      if(!mounted)return;
      setState(()=>_recommendations..clear()..addAll(recs.where((x)=>x.id!=track.id)));
      await _saveLists();
    }catch(e){if(mounted)setState(()=>_error='Impossible de charger les suggestions : ${e.toString().replaceFirst('Exception: ','')}');}
    finally{if(mounted)setState(()=>_loadingRecommendations=false);}
  }

  Future<void> _play(YoutubeTrack track,{List<YoutubeTrack>? from}) async {
    if(from!=null){
      final source=List<YoutubeTrack>.from(from);
      _queue..clear()..addAll(source);
      if(_shuffle&&_queue.length>1){
        final selected=track;
        _queue.shuffle();
        _queue.removeWhere((x)=>x.id==selected.id);
        _queue.insert(0,selected);
      }
      _queueIndex=_queue.indexWhere((x)=>x.id==track.id);
    }else{
      final found=_queue.indexWhere((x)=>x.id==track.id);
      if(found>=0){_queueIndex=found;}else{_queue.add(track);_queueIndex=_queue.length-1;}
    }
    setState(()=>_current=track);
    if(!_history.any((x)=>x.id==track.id))_history.insert(0,track);else{_history.removeWhere((x)=>x.id==track.id);_history.insert(0,track);}
    if(_history.length>60)_history.removeRange(60,_history.length);
    await _saveLists();
    try{
      if(_player==null){
        _player=YoutubePlayerController(params:const YoutubePlayerParams(
          showControls:true,showFullscreenButton:true,interfaceLanguage:'fr',privacyEnhancedMode:true,
        ));
        if(mounted)setState((){});
        await _player!.loadVideoById(videoId:track.id);
      }else{await _player!.loadVideoById(videoId:track.id);}
    }catch(_){
      if(mounted)setState(()=>_error='YouTube ne peut pas lire cette vidéo dans le lecteur intégré. Essaie un autre résultat : certaines vidéos bloquent la lecture intégrée.');
    }
  }
  Future<void> _step(int delta) async {
    if(_queue.isEmpty)return;
    var next=_queueIndex+delta;
    if(_shuffle&&_queue.length>1){
      final choices=List.generate(_queue.length,(i)=>i).where((i)=>i!=_queueIndex).toList()..shuffle();
      next=choices.first;
    }else if(next<0||next>=_queue.length){if(_repeat)next=delta>0?0:_queue.length-1;else return;}
    _queueIndex=next;await _play(_queue[next]);
  }
  bool _isFavorite(YoutubeTrack t)=>_favorites.any((x)=>x.id==t.id);
  Future<void> _toggleFavorite(YoutubeTrack t) async {
    setState((){if(_isFavorite(t)){_favorites.removeWhere((x)=>x.id==t.id);}else{_favorites.insert(0,t);}});
    await _saveLists();
  }
  @override void dispose(){_search.dispose();_keyInput.dispose();_player?.close();super.dispose();}

  @override Widget build(BuildContext context)=>ListView(padding:const EdgeInsets.fromLTRB(18,10,18,28),children:[
    Row(children:[
      Container(width:42,height:42,decoration:BoxDecoration(gradient:const LinearGradient(colors:[ytAccent,ytMint]),borderRadius:BorderRadius.circular(14)),child:const Icon(Icons.play_arrow_rounded,color:Color(0xFF0A0A11),size:29)),
      const SizedBox(width:11),
      const Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[Text('YOUTUBE',style:TextStyle(fontSize:24,fontWeight:FontWeight.w900,letterSpacing:-.6)),Text('Search • listen • discover',style:TextStyle(fontSize:10,color:Colors.white54,letterSpacing:.5))])),
      IconButton(onPressed:_configureKey,tooltip:'Configuration API',icon:Icon(Icons.tune_rounded,color:_apiKey.isNotEmpty?ytMint:Colors.white70)),
    ]),
    const SizedBox(height:17),
    Container(decoration:BoxDecoration(color:ytSurface,borderRadius:BorderRadius.circular(17),border:Border.all(color:ytAccent.withValues(alpha:.2))),child:Row(children:[
      const SizedBox(width:14),const Icon(Icons.search_rounded,color:ytAccent),const SizedBox(width:7),
      Expanded(child:TextField(controller:_search,textInputAction:TextInputAction.search,onSubmitted:(_)=>_find(),decoration:const InputDecoration(hintText:'Titre, artiste, remix, nightcore…',border:InputBorder.none,contentPadding:EdgeInsets.symmetric(vertical:16)))),
      IconButton(onPressed:_loading?null:_find,icon:const Icon(Icons.arrow_forward_rounded,color:ytMint)),
    ])),
    const SizedBox(height:13),
    Wrap(spacing:7,runSpacing:7,children:[
      _sectionChip('Découvrir',0,Icons.auto_awesome_rounded),
      _sectionChip('Recherche',1,Icons.search_rounded),
      _sectionChip('Récents',2,Icons.history_rounded),
      _sectionChip('Favoris',3,Icons.favorite_rounded),
      _sectionChip('File',4,Icons.queue_music_rounded),
    ]),
    if(_current!=null&&_player!=null)...[
      const SizedBox(height:18),
      Container(padding:const EdgeInsets.all(12),decoration:BoxDecoration(color:ytSurface,borderRadius:BorderRadius.circular(23),border:Border.all(color:ytAccent.withValues(alpha:.2))),child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        ClipRRect(borderRadius:BorderRadius.circular(17),child:AspectRatio(aspectRatio:16/9,child:Stack(fit:StackFit.expand,children:[
          _cover(_current!,fit:BoxFit.cover),
          if(_showVideo)YoutubePlayer(controller:_player!,aspectRatio:16/9),
        ]))),
        const SizedBox(height:13),
        Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
          ClipRRect(borderRadius:BorderRadius.circular(11),child:SizedBox(width:58,height:58,child:_cover(_current!))),
          const SizedBox(width:11),
          Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(_current!.title,maxLines:2,overflow:TextOverflow.ellipsis,style:const TextStyle(fontSize:15,fontWeight:FontWeight.w900)),
            const SizedBox(height:4),Text(_current!.channel,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white54,fontSize:11)),
            const SizedBox(height:5),const Text('LECTEUR YOUTUBE OFFICIEL',style:TextStyle(color:ytMint,fontSize:8,fontWeight:FontWeight.w900,letterSpacing:1)),
          ])),
          IconButton(onPressed:()=>_toggleFavorite(_current!),icon:Icon(_isFavorite(_current!)?Icons.favorite:Icons.favorite_border,color:_isFavorite(_current!)?const Color(0xFFFF7C9E):ytAccent)),
        ]),
        const SizedBox(height:7),
        Row(mainAxisAlignment:MainAxisAlignment.spaceAround,children:[
          IconButton(onPressed:()=>setState(()=>_shuffle=!_shuffle),color:_shuffle?ytMint:Colors.white54,tooltip:'Aléatoire',icon:const Icon(Icons.shuffle_rounded)),
          IconButton(onPressed:()=>_step(-1),icon:const Icon(Icons.skip_previous_rounded,size:30)),
          IconButton(onPressed:()=>_player?.playVideo(),icon:const Icon(Icons.play_circle_fill_rounded,size:42,color:ytAccent)),
          IconButton(onPressed:()=>_player?.pauseVideo(),icon:const Icon(Icons.pause_circle_filled_rounded,size:36)),
          IconButton(onPressed:()=>_step(1),icon:const Icon(Icons.skip_next_rounded,size:30)),
          IconButton(onPressed:()=>setState(()=>_repeat=!_repeat),color:_repeat?ytMint:Colors.white54,tooltip:'Répéter',icon:const Icon(Icons.repeat_rounded)),
        ]),
        Row(children:[
          Expanded(child:TextButton.icon(onPressed:()=>setState(()=>_showVideo=!_showVideo),icon:Icon(_showVideo?Icons.image_outlined:Icons.smart_display_outlined),label:Text(_showVideo?'Afficher la cover':'Afficher la vidéo'))),
          Expanded(child:TextButton.icon(onPressed:_recommendSimilar,icon:const Icon(Icons.auto_awesome_rounded),label:const Text('Sons similaires'))),
        ]),
      ])),
    ],
    if(_loading||_loadingRecommendations)const Padding(padding:EdgeInsets.all(20),child:Center(child:CircularProgressIndicator(color:ytAccent))),
    if(_error!=null)Container(margin:const EdgeInsets.only(top:12),padding:const EdgeInsets.all(13),decoration:BoxDecoration(color:ytSurface2,borderRadius:BorderRadius.circular(14)),child:Row(crossAxisAlignment:CrossAxisAlignment.start,children:[
      const Icon(Icons.info_outline_rounded,color:Color(0xFFFFD18A),size:19),const SizedBox(width:9),Expanded(child:Text(_error!,style:const TextStyle(color:Colors.white70,fontSize:12,height:1.4))),IconButton(onPressed:()=>setState(()=>_error=null),icon:const Icon(Icons.close,size:17)),
    ])),
    const SizedBox(height:19),
    if(_section==0)...[
      Row(children:[const Expanded(child:Text('POUR DÉCOUVRIR',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1))),IconButton(onPressed:_loadRecommendations,icon:const Icon(Icons.refresh_rounded,color:ytAccent))]),
      const SizedBox(height:4),const Text('Suggestions générées depuis la recherche YouTube publique.',style:TextStyle(color:Colors.white54,fontSize:11)),
      const SizedBox(height:11),
      if(_apiKey.isEmpty)_empty(Icons.key_rounded,'Connecte YouTube','Ajoute ta clé API pour rechercher et afficher les suggestions.',_configureKey)
      else if(_recommendations.isEmpty&&!_loadingRecommendations)_empty(Icons.auto_awesome_rounded,'Pas encore de suggestions','Appuie sur actualiser pour réessayer.',_loadRecommendations)
      else ..._recommendations.map((t)=>_trackTile(t,from:_recommendations)),
    ] else if(_section==1)...[
      Row(children:[const Expanded(child:Text('RÉSULTATS',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1))),Text('${_results.length}',style:const TextStyle(color:Colors.white54,fontSize:11))]),
      const SizedBox(height:10),
      if(_results.isEmpty&&!_loading)_empty(Icons.search_rounded,'Cherche ton prochain son','Tape un titre ou un artiste dans la barre en haut.',null)
      else ..._results.map((t)=>_trackTile(t,from:_results)),
    ] else if(_section==2)...[
      const Text('ÉCOUTÉS RÉCEMMENT',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1)),
      const SizedBox(height:10),
      if(_history.isEmpty)_empty(Icons.history_rounded,'Rien pour le moment','Les titres lancés apparaîtront ici.',null)
      else ..._history.map((t)=>_trackTile(t,from:_history)),
    ] else if(_section==3)...[
      const Text('TES FAVORIS',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1)),
      const SizedBox(height:10),
      if(_favorites.isEmpty)_empty(Icons.favorite_border_rounded,'Garde tes pépites','Appuie sur le cœur d’un titre pour le sauvegarder.',null)
      else ..._favorites.map((t)=>_trackTile(t,from:_favorites)),
    ] else ...[
      Row(children:[const Expanded(child:Text('FILE D’ATTENTE',style:TextStyle(fontWeight:FontWeight.w900,letterSpacing:1.1))),Text('${_queue.length} titres',style:const TextStyle(color:Colors.white54,fontSize:11))]),
      const SizedBox(height:10),
      if(_queue.isEmpty)_empty(Icons.queue_music_rounded,'La file est vide','Lance un titre depuis les résultats ou les suggestions.',null)
      else ..._queue.asMap().entries.map((e)=>_trackTile(e.value,active:e.key==_queueIndex,from:_queue)),
    ],
  ]);

  Widget _sectionChip(String label,int value,IconData icon)=>ChoiceChip(selected:_section==value,onSelected:(_)=>setState(()=>_section=value),avatar:Icon(icon,size:15,color:_section==value?const Color(0xFF090A0F):ytAccent),label:Text(label),labelStyle:TextStyle(fontSize:11,fontWeight:FontWeight.w700,color:_section==value?const Color(0xFF090A0F):Colors.white),selectedColor:ytMint,backgroundColor:ytSurface,side:BorderSide(color:_section==value?ytMint:Colors.white12));
  Widget _trackTile(YoutubeTrack t,{bool active=false,List<YoutubeTrack>? from})=>Container(margin:const EdgeInsets.only(bottom:9),decoration:BoxDecoration(color:active?ytAccent.withValues(alpha:.12):ytSurface,borderRadius:BorderRadius.circular(16),border:Border.all(color:active?ytAccent.withValues(alpha:.3):Colors.white.withValues(alpha:.025))),child:ListTile(
    onTap:()=>_play(t,from:from),contentPadding:const EdgeInsets.symmetric(horizontal:10,vertical:4),
    leading:ClipRRect(borderRadius:BorderRadius.circular(11),child:SizedBox(width:88,height:57,child:_cover(t))),
    title:Text(t.title,maxLines:2,overflow:TextOverflow.ellipsis,style:TextStyle(fontSize:12,fontWeight:FontWeight.w800,color:active?ytAccent:Colors.white)),
    subtitle:Text(t.channel,maxLines:1,overflow:TextOverflow.ellipsis,style:const TextStyle(color:Colors.white54,fontSize:10)),
    trailing:IconButton(onPressed:()=>_toggleFavorite(t),icon:Icon(_isFavorite(t)?Icons.favorite:Icons.favorite_border,color:_isFavorite(t)?const Color(0xFFFF7C9E):Colors.white38,size:20)),
  ));
  Widget _cover(YoutubeTrack t,{BoxFit fit=BoxFit.cover})=>t.thumbnail.isEmpty?Container(color:ytSurface2,child:const Icon(Icons.music_note_rounded,color:ytAccent,size:34)):Image.network(t.thumbnail,fit:fit,errorBuilder:(_,__,___)=>Container(color:ytSurface2,child:const Icon(Icons.music_note_rounded,color:ytAccent,size:34)));
  Widget _empty(IconData icon,String title,String sub,VoidCallback? action)=>Container(padding:const EdgeInsets.all(23),decoration:BoxDecoration(color:ytSurface,borderRadius:BorderRadius.circular(19)),child:Column(children:[
    Icon(icon,size:35,color:ytAccent),const SizedBox(height:10),Text(title,style:const TextStyle(fontWeight:FontWeight.w900)),const SizedBox(height:6),Text(sub,textAlign:TextAlign.center,style:const TextStyle(color:Colors.white54,fontSize:11,height:1.45)),
    if(action!=null)...[const SizedBox(height:12),FilledButton.tonal(onPressed:action,child:const Text('Réessayer'))],
  ]));
}
