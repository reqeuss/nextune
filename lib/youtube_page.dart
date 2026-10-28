import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

const _purple = Color(0xFF9B6BFF);
const _panel = Color(0xFF171620);

class YoutubeTrack {
  const YoutubeTrack(this.id, this.title, this.channel, this.thumbnail);
  final String id, title, channel, thumbnail;
}

class YoutubePage extends StatefulWidget {
  const YoutubePage({super.key});
  @override
  State<YoutubePage> createState() => _YoutubePageState();
}

class _YoutubePageState extends State<YoutubePage> {
  final _search = TextEditingController();
  final _keyInput = TextEditingController();
  final List<YoutubeTrack> _results = [], _queue = [];
  YoutubePlayerController? _player;
  YoutubeTrack? _current;
  String _apiKey = const String.fromEnvironment('YOUTUBE_API_KEY');
  String? _error;
  bool _loading = false, _shuffle = false, _repeat = false;
  int _queueIndex = -1;

  @override
  void initState() { super.initState(); _loadKey(); }

  Future<void> _loadKey() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('youtubeApiKey') ?? '';
    if (saved.isNotEmpty && mounted) setState(() => _apiKey = saved);
  }

  Future<void> _configureKey() async {
    _keyInput.text = _apiKey;
    final value = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Configurer YouTube'),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const Text('Colle ta clé YouTube Data API v3 pour afficher les résultats de recherche.', style: TextStyle(color: Colors.white70)),
        const SizedBox(height: 12),
        TextField(controller: _keyInput, obscureText: true, decoration: const InputDecoration(labelText: 'Clé API', border: OutlineInputBorder())),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, _keyInput.text.trim()), child: const Text('Enregistrer')),
      ],
    ));
    if (value == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('youtubeApiKey', value);
    if (!mounted) return;
    setState(() { _apiKey = value; _error = null; });
    if (_search.text.trim().isNotEmpty) _find();
  }

  Future<void> _find() async {
    final q = _search.text.trim();
    if (q.isEmpty) return;
    if (_apiKey.isEmpty) {
      setState(() => _error = 'Configure ta clé YouTube Data API v3 pour afficher les morceaux.');
      await _configureKey();
      return;
    }
    FocusScope.of(context).unfocus();
    setState(() { _loading = true; _error = null; });
    try {
      final uri = Uri.https('www.googleapis.com', '/youtube/v3/search', {
        'part': 'snippet', 'type': 'video', 'maxResults': '25', 'q': q,
        'key': _apiKey, 'safeSearch': 'moderate',
      });
      final res = await http.get(uri).timeout(const Duration(seconds: 15));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (res.statusCode != 200) {
        final message = (data['error'] as Map<String, dynamic>?)?['message']?.toString();
        throw Exception(message ?? 'Erreur YouTube (${res.statusCode})');
      }
      final items = (data['items'] as List? ?? []).whereType<Map<String, dynamic>>();
      final found = items.map((item) {
        final id = item['id'] as Map<String, dynamic>? ?? {};
        final sn = item['snippet'] as Map<String, dynamic>? ?? {};
        final thumbs = sn['thumbnails'] as Map<String, dynamic>? ?? {};
        final thumb = (thumbs['high'] ?? thumbs['medium'] ?? thumbs['default']) as Map<String, dynamic>?;
        return YoutubeTrack(id['videoId']?.toString() ?? '', sn['title']?.toString() ?? 'Sans titre',
          sn['channelTitle']?.toString() ?? 'YouTube', thumb?['url']?.toString() ?? '');
      }).where((t) => t.id.isNotEmpty).toList();
      if (!mounted) return;
      setState(() { _results..clear()..addAll(found); _loading = false; });
      if (found.isEmpty) setState(() => _error = 'Aucun résultat trouvé. Essaie une autre recherche.');
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '');
      setState(() { _loading = false; _error = 'Recherche impossible : $message'; });
    }
  }

  Future<void> _play(YoutubeTrack track) async {
    final existing = _queue.indexWhere((t) => t.id == track.id);
    if (existing >= 0) {
      _queueIndex = existing;
    } else {
      _queue..clear()..addAll(_shuffle ? (List<YoutubeTrack>.from(_results)..shuffle()) : _results);
      _queueIndex = _queue.indexWhere((t) => t.id == track.id);
      if (_queueIndex < 0) { _queue.insert(0, track); _queueIndex = 0; }
    }
    setState(() { _current = track; _error = null; });
    if (_player == null) {
      _player = YoutubePlayerController(params: const YoutubePlayerParams(
        showControls: true, showFullscreenButton: true, interfaceLanguage: 'fr', privacyEnhancedMode: true,
      ));
      setState(() {});
      _player!.loadVideoById(videoId: track.id);
    } else {
      await _player!.loadVideoById(videoId: track.id);
    }
  }

  Future<void> _step(int delta) async {
    if (_queue.isEmpty) return;
    var next = _queueIndex + delta;
    if (next < 0 || next >= _queue.length) {
      if (_repeat) { next = delta > 0 ? 0 : _queue.length - 1; } else { return; }
    }
    await _play(_queue[next]);
  }

  @override
  void dispose() { _search.dispose(); _keyInput.dispose(); _player?.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) => ListView(padding: const EdgeInsets.fromLTRB(18, 10, 18, 28), children: [
    Row(children: [
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('YOUTUBE', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w900, letterSpacing: 1.2)),
        SizedBox(height: 3), Text('Trouve un son et lance-le ici.', style: TextStyle(color: Colors.white60)),
      ])),
      IconButton(onPressed: _configureKey, tooltip: 'Configurer YouTube', icon: const Icon(Icons.settings_outlined)),
    ]),
    const SizedBox(height: 16),
    Container(decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: _purple.withValues(alpha: .25))),
      child: Row(children: [
        const SizedBox(width: 14), const Icon(Icons.search_rounded, color: _purple), const SizedBox(width: 8),
        Expanded(child: TextField(controller: _search, textInputAction: TextInputAction.search, onSubmitted: (_) => _find(),
          decoration: const InputDecoration(hintText: 'Artiste, titre, nightcore…', border: InputBorder.none))),
        IconButton(onPressed: _loading ? null : _find, icon: const Icon(Icons.arrow_forward_rounded, color: _purple)),
      ])),
    if (_current != null && _player != null) ...[
      const SizedBox(height: 18),
      Container(clipBehavior: Clip.antiAlias, decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(22), border: Border.all(color: _purple.withValues(alpha: .3))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          YoutubePlayer(controller: _player!, aspectRatio: 16 / 9),
          Padding(padding: const EdgeInsets.fromLTRB(15, 13, 12, 10), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_current!.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4), Text(_current!.channel, style: const TextStyle(color: Colors.white54, fontSize: 12)),
            Row(children: [
              IconButton(onPressed: () => setState(() => _shuffle = !_shuffle), tooltip: 'Aléatoire', color: _shuffle ? _purple : Colors.white54, icon: const Icon(Icons.shuffle_rounded)),
              IconButton(onPressed: () => _step(-1), icon: const Icon(Icons.skip_previous_rounded, size: 30)),
              IconButton(onPressed: () => _player?.play(), icon: const Icon(Icons.play_arrow_rounded, size: 30)),
              IconButton(onPressed: () => _player?.pause(), icon: const Icon(Icons.pause_rounded, size: 28)),
              IconButton(onPressed: () => _step(1), icon: const Icon(Icons.skip_next_rounded, size: 30)),
              IconButton(onPressed: () => setState(() => _repeat = !_repeat), tooltip: 'Répéter la file', color: _repeat ? _purple : Colors.white54, icon: const Icon(Icons.repeat_rounded)),
            ]),
          ])),
        ])),
      const SizedBox(height: 20),
      Row(children: [const Expanded(child: Text('FILE D’ATTENTE', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1))), Text('${_queue.length} titres', style: const TextStyle(color: Colors.white54, fontSize: 12))]),
      const SizedBox(height: 8),
      ..._queue.asMap().entries.map((e) => _tile(e.value, e.key == _queueIndex, () => _play(e.value))),
    ],
    if (_loading) const Padding(padding: EdgeInsets.all(28), child: Center(child: CircularProgressIndicator())),
    if (_error != null) Container(padding: const EdgeInsets.all(14), margin: const EdgeInsets.only(top: 12), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(14)), child: Text(_error!, style: const TextStyle(color: Colors.white70))),
    if (!_loading && _results.isNotEmpty) ...[
      const SizedBox(height: 22),
      Row(children: [const Expanded(child: Text('RÉSULTATS', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1))), Text('${_results.length} vidéos', style: const TextStyle(color: Colors.white54, fontSize: 12))]),
      const SizedBox(height: 8),
      ..._results.map((t) => _tile(t, _current?.id == t.id, () => _play(t))),
    ],
    if (!_loading && _results.isEmpty && _error == null && _current == null)
      Container(margin: const EdgeInsets.only(top: 24), padding: const EdgeInsets.all(25), decoration: BoxDecoration(color: _panel, borderRadius: BorderRadius.circular(20)), child: const Column(children: [
        Icon(Icons.graphic_eq_rounded, color: _purple, size: 44), SizedBox(height: 10),
        Text('Quel son tu cherches ?', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)), SizedBox(height: 5),
        Text('Cherche un titre, touche un résultat et écoute-le dans le lecteur intégré.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)),
      ])),
  ]);

  Widget _tile(YoutubeTrack t, bool active, VoidCallback onTap) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    decoration: BoxDecoration(color: active ? _purple.withValues(alpha: .14) : _panel, borderRadius: BorderRadius.circular(15)),
    child: ListTile(contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      leading: ClipRRect(borderRadius: BorderRadius.circular(9), child: SizedBox(width: 88, height: 56,
        child: t.thumbnail.isEmpty ? const ColoredBox(color: Color(0xFF292438), child: Icon(Icons.music_note, color: _purple))
        : Image.network(t.thumbnail, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const ColoredBox(color: Color(0xFF292438), child: Icon(Icons.music_note, color: _purple))))),
      title: Text(t.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: active ? _purple : Colors.white)),
      subtitle: Text(t.channel, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white54)),
      trailing: Icon(active ? Icons.graphic_eq_rounded : Icons.play_circle_outline_rounded, color: _purple, size: 25),
      onTap: onTap),
  );
}
