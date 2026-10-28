import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:just_audio/just_audio.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'youtube_page.dart';

void main() => runApp(const NextuneApp());

const _accent = Color(0xFFB79AFF);
const _accent2 = Color(0xFF7C4DFF);
const _bg = Color(0xFF0B0A10);
const _card = Color(0xFF17151F);
const _card2 = Color(0xFF211C2C);

class NextuneApp extends StatelessWidget {
  const NextuneApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Nextune',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: _bg,
      colorScheme: ColorScheme.fromSeed(seedColor: _accent2, brightness: Brightness.dark),
      sliderTheme: const SliderThemeData(showValueIndicator: ShowValueIndicator.always),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    ),
    home: const HomePage(),
  );
}

class Track {
  Track(this.path, this.title, {this.favorite = false});
  final String path;
  final String title;
  bool favorite;

  Map<String, dynamic> toJson() => {'path': path, 'title': title, 'favorite': favorite};

  factory Track.fromJson(Map<String, dynamic> json) => Track(
    json['path'] as String,
    json['title'] as String? ?? 'Titre inconnu',
    favorite: json['favorite'] == true,
  );
}

class Playlist {
  Playlist(this.name, {List<String>? paths}) : paths = paths ?? [];
  String name;
  final List<String> paths;

  Map<String, dynamic> toJson() => {'name': name, 'paths': paths};

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    json['name'] as String? ?? 'Playlist',
    paths: (json['paths'] as List? ?? []).whereType<String>().toList(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const _effectsChannel = MethodChannel('nextune/audio_effects');
  final AudioPlayer _player = AudioPlayer();
  final List<Track> _tracks = [];
  final List<Playlist> _playlists = [];

  int _tab = 0;
  int _current = -1;
  int? _sessionId;
  int _repeat = 0; // 0 off, 1 track, 2 queue
  bool _ready = false;
  bool _shuffle = false;
  String _preset = 'Normal';
  double _pitch = 1.0;
  double _speed = 1.0;

  @override
  void initState() {
    super.initState();
    _player.androidAudioSessionIdStream.listen((id) {
      _sessionId = id;
      _applyNativeEffect();
    });
    _player.processingStateStream.listen((state) async {
      if (state != ProcessingState.completed || _tracks.isEmpty || _current < 0) return;
      if (_repeat == 1) {
        await _play(_current);
      } else if (_shuffle && _tracks.length > 1) {
        final choices = List<int>.generate(_tracks.length, (i) => i)
          .where((i) => i != _current).toList()..shuffle();
        await _play(choices.first);
      } else if (_current + 1 < _tracks.length) {
        await _play(_current + 1);
      } else if (_repeat == 2) {
        await _play(0);
      }
    });
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final rawTracks = prefs.getString('tracks');
      if (rawTracks != null) {
        _tracks.addAll((jsonDecode(rawTracks) as List)
          .map((item) => Track.fromJson(Map<String, dynamic>.from(item))));
      }
      final rawPlaylists = prefs.getString('playlists');
      if (rawPlaylists != null) {
        _playlists.addAll((jsonDecode(rawPlaylists) as List)
          .map((item) => Playlist.fromJson(Map<String, dynamic>.from(item))));
      }
    } catch (_) {}
    if (mounted) setState(() => _ready = true);
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('tracks', jsonEncode(_tracks.map((t) => t.toJson()).toList()));
    await prefs.setString('playlists', jsonEncode(_playlists.map((p) => p.toJson()).toList()));
  }

  Future<void> _addTracks() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.audio, allowMultiple: true);
    if (result == null) return;
    var added = 0;
    for (final file in result.files) {
      final path = file.path;
      if (path == null || _tracks.any((track) => track.path == path)) continue;
      _tracks.add(Track(path, file.name.replaceAll(RegExp(r'\.[^.]+$'), '')));
      added++;
    }
    await _save();
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$added titre(s) ajouté(s)')));
    }
    if (_current < 0 && _tracks.isNotEmpty) await _play(0);
  }

  Future<void> _play(int index) async {
    if (index < 0 || index >= _tracks.length) return;
    try {
      await _player.setFilePath(_tracks[index].path);
      if (!mounted) return;
      setState(() => _current = index);
      await _player.setSpeed(_speed);
      try { await _player.setPitch(_pitch); } catch (_) {}
      await _player.play();
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Impossible de lire ce fichier audio.')),
      );
    }
  }

  Future<void> _togglePlayback() async {
    if (_current < 0) {
      if (_tracks.isEmpty) {
        await _addTracks();
      } else {
        await _play(0);
      }
    } else if (_player.playing) {
      await _player.pause();
    } else {
      await _player.play();
    }
    if (mounted) setState(() {});
  }

  Future<void> _next() async {
    if (_tracks.isEmpty) return;
    if (_shuffle && _tracks.length > 1) {
      final choices = List<int>.generate(_tracks.length, (i) => i)
        .where((i) => i != _current).toList()..shuffle();
      await _play(choices.first);
    } else {
      await _play(_current < 0 || _current + 1 >= _tracks.length ? 0 : _current + 1);
    }
  }

  Future<void> _previous() async {
    if (_tracks.isEmpty) return;
    if (_player.position > const Duration(seconds: 3)) {
      await _player.seek(Duration.zero);
      return;
    }
    await _play(_current <= 0 ? _tracks.length - 1 : _current - 1);
  }

  Future<void> _setPreset(String name) async {
    setState(() {
      _preset = name;
      switch (name) {
        case 'Nightcore':
          _speed = 1.12;
          _pitch = 1.22;
          break;
        case 'Slowed + Reverb':
          _speed = 0.85;
          _pitch = 0.82;
          break;
        case 'Bass Boost':
        case 'BassMax':
        case 'Normal':
        default:
          _speed = 1.0;
          _pitch = 1.0;
      }
    });
    await _applyPitchAndSpeed();
    await _applyNativeEffect();
  }

  Future<void> _applyPitchAndSpeed() async {
    try { await _player.setSpeed(_speed); } catch (_) {}
    try { await _player.setPitch(_pitch); } catch (_) {
      if (mounted && _pitch != 1.0) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Le réglage du pitch est disponible sur Android avec le moteur audio actuel.')),
        );
      }
    }
  }

  Future<void> _applyNativeEffect() async {
    try {
      await _effectsChannel.invokeMethod('setEffect', {
        'sessionId': _sessionId,
        'effect': _preset,
      });
    } catch (_) {}
  }

  Future<void> _setPitch(double value) async {
    setState(() { _pitch = value; _preset = 'Personnalisé'; });
    try {
      await _player.setPitch(value);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Le pitch n’est pas disponible sur cette plateforme.')),
      );
    }
  }

  Future<void> _setSpeed(double value) async {
    setState(() { _speed = value; _preset = 'Personnalisé'; });
    try { await _player.setSpeed(value); } catch (_) {}
  }

  Future<void> _createPlaylist() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: const Text('Nouvelle playlist'),
      content: TextField(controller: controller, autofocus: true, maxLength: 40,
        decoration: const InputDecoration(hintText: 'Ex. : Night drive')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: const Text('Créer')),
      ],
    ));
    controller.dispose();
    if (name == null || name.trim().isEmpty) return;
    if (_playlists.any((p) => p.name.toLowerCase() == name.toLowerCase())) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cette playlist existe déjà.')),
      );
      return;
    }
    _playlists.add(Playlist(name.trim()));
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _addToPlaylist(Track track) async {
    if (_playlists.isEmpty) await _createPlaylist();
    if (_playlists.isEmpty || !mounted) return;
    final chosen = await showModalBottomSheet<Playlist>(
      context: context, backgroundColor: _card,
      builder: (context) => SafeArea(child: ListView(shrinkWrap: true, children: [
        const ListTile(title: Text('Ajouter à une playlist')),
        ..._playlists.map((playlist) => ListTile(
          leading: const Icon(Icons.queue_music_rounded, color: _accent),
          title: Text(playlist.name),
          subtitle: Text('${playlist.paths.length} titre(s)'),
          onTap: () => Navigator.pop(context, playlist),
        )),
      ])),
    );
    if (chosen == null) return;
    if (!chosen.paths.contains(track.path)) chosen.paths.add(track.path);
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _renamePlaylist(Playlist playlist) async {
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
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _deletePlaylist(Playlist playlist) async {
    final confirm = await showDialog<bool>(context: context, builder: (context) => AlertDialog(
      title: const Text('Supprimer la playlist ?'),
      content: Text('La playlist « ${playlist.name} » sera supprimée. Les fichiers audio restent sur le téléphone.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Supprimer')),
      ],
    ));
    if (confirm != true) return;
    _playlists.remove(playlist);
    await _save();
    if (mounted) setState(() {});
  }

  Future<void> _exportBackup() async {
    final file = File('${Directory.systemTemp.path}/nextune-backup.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'app': 'Nextune', 'version': 2,
      'tracks': _tracks.map((t) => t.toJson()).toList(),
      'playlists': _playlists.map((p) => p.toJson()).toList(),
    }));
    await Share.shareXFiles([XFile(file.path)], text: 'Sauvegarde Nextune');
  }

  Future<void> _importBackup() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json']);
    if (result == null || result.files.single.path == null) return;
    try {
      final data = jsonDecode(await File(result.files.single.path!).readAsString()) as Map<String, dynamic>;
      for (final item in (data['tracks'] as List? ?? [])) {
        final track = Track.fromJson(Map<String, dynamic>.from(item));
        if (await File(track.path).exists() && !_tracks.any((t) => t.path == track.path)) _tracks.add(track);
      }
      for (final item in (data['playlists'] as List? ?? [])) {
        final playlist = Playlist.fromJson(Map<String, dynamic>.from(item));
        if (!_playlists.any((p) => p.name == playlist.name)) _playlists.add(playlist);
      }
      await _save();
      if (mounted) setState(() {});
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Ce fichier de sauvegarde est invalide.')),
      );
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = _current >= 0 && _current < _tracks.length ? _tracks[_current] : null;
    return Scaffold(
      body: SafeArea(child: Column(children: [
        _topBar(),
        Expanded(child: !_ready
          ? const Center(child: CircularProgressIndicator())
          : _tab == 4 ? const YoutubePage()
          : _tab == 3 ? _settingsPage()
          : _tab == 2 ? _playlistsPage()
          : _libraryPage(favoritesOnly: _tab == 1)),
        if (currentTrack != null) _miniPlayer(currentTrack),
        NavigationBar(
          backgroundColor: const Color(0xFF100E16),
          indicatorColor: _accent.withValues(alpha: .16),
          selectedIndex: _tab,
          onDestinationSelected: (value) async {
            if (value == 4 && _player.playing) await _player.pause();
            setState(() => _tab = value);
          },
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home_rounded), label: 'Accueil'),
            NavigationDestination(icon: Icon(Icons.favorite_border_rounded), selectedIcon: Icon(Icons.favorite_rounded), label: 'Favoris'),
            NavigationDestination(icon: Icon(Icons.queue_music_rounded), label: 'Playlists'),
            NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Effets'),
            NavigationDestination(icon: Icon(Icons.smart_display_outlined), selectedIcon: Icon(Icons.smart_display_rounded), label: 'YouTube'),
          ],
        ),
      ])),
    );
  }

  Widget _topBar() => Padding(
    padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
    child: Row(children: [
      Container(
        width: 46, height: 46,
        decoration: BoxDecoration(
          gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [_accent, _accent2]),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.graphic_eq_rounded, color: Color(0xFF100B18), size: 28),
      ),
      const SizedBox(width: 12),
      const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('NEXTUNE', style: TextStyle(fontSize: 21, fontWeight: FontWeight.w900, letterSpacing: 2)),
        Text('YOUR SOUND. YOUR RULES.', style: TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.4)),
      ])),
      IconButton(onPressed: _addTracks, tooltip: 'Importer de la musique', icon: const Icon(Icons.add_rounded, color: _accent, size: 29)),
    ]),
  );

  Widget _libraryPage({bool favoritesOnly = false}) {
    final list = favoritesOnly ? _tracks.where((t) => t.favorite).toList() : _tracks;
    return ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
      if (!favoritesOnly) ...[
        Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: const LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF302442), Color(0xFF17131F)]),
            borderRadius: BorderRadius.circular(25),
            border: Border.all(color: _accent.withValues(alpha: .2)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('TA MUSIQUE.\nTON AMBIANCE.', style: TextStyle(fontSize: 29, height: 1.08, fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            const Text('Tes fichiers, tes playlists et tes effets audio.', style: TextStyle(color: Colors.white60)),
            const SizedBox(height: 18),
            FilledButton.icon(onPressed: _addTracks, icon: const Icon(Icons.library_music_rounded), label: const Text('Importer des titres')),
          ]),
        ),
        const SizedBox(height: 24),
      ],
      Row(children: [
        Expanded(child: Text(favoritesOnly ? 'TES FAVORIS' : 'TA BIBLIOTHÈQUE', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: .7))),
        Text('${list.length} titre(s)', style: const TextStyle(color: Colors.white54, fontSize: 12)),
      ]),
      const SizedBox(height: 12),
      if (list.isEmpty) _emptyCard(
        favoritesOnly ? Icons.favorite_border_rounded : Icons.album_rounded,
        favoritesOnly ? 'Pas encore de favoris' : 'Ta musique commence ici',
        favoritesOnly ? 'Appuie sur le cœur d’un titre pour le retrouver ici.' : 'Importe des fichiers audio enregistrés sur ton téléphone.',
      ) else ...list.map((track) {
        final index = _tracks.indexOf(track);
        final active = index == _current;
        return Container(
          margin: const EdgeInsets.only(bottom: 9),
          decoration: BoxDecoration(
            color: active ? _accent.withValues(alpha: .12) : _card,
            borderRadius: BorderRadius.circular(17),
            border: Border.all(color: active ? _accent.withValues(alpha: .3) : Colors.white.withValues(alpha: .035)),
          ),
          child: ListTile(
            onTap: () => _play(index),
            contentPadding: const EdgeInsets.symmetric(horizontal: 11, vertical: 4),
            leading: Container(
              width: 46, height: 46,
              decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(13)),
              child: Icon(active && _player.playing ? Icons.equalizer_rounded : Icons.music_note_rounded, color: _accent),
            ),
            title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.w700, color: active ? _accent : Colors.white)),
            subtitle: Text(active ? _preset : 'Fichier local', style: const TextStyle(color: Colors.white54, fontSize: 11)),
            trailing: PopupMenuButton<String>(
              onSelected: (value) async {
                if (value == 'favorite') { setState(() => track.favorite = !track.favorite); await _save(); }
                if (value == 'playlist') await _addToPlaylist(track);
              },
              itemBuilder: (_) => [
                PopupMenuItem(value: 'favorite', child: Row(children: [
                  Icon(track.favorite ? Icons.favorite : Icons.favorite_border, size: 18), const SizedBox(width: 10),
                  Text(track.favorite ? 'Retirer des favoris' : 'Ajouter aux favoris'),
                ])),
                const PopupMenuItem(value: 'playlist', child: Row(children: [
                  Icon(Icons.playlist_add, size: 18), SizedBox(width: 10), Text('Ajouter à une playlist'),
                ])),
              ],
            ),
          ),
        );
      }),
    ]);
  }

  Widget _playlistsPage() => ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 24), children: [
    Row(children: [
      const Expanded(child: Text('TES PLAYLISTS', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
      FilledButton.icon(onPressed: _createPlaylist, icon: const Icon(Icons.add), label: const Text('Créer')),
    ]),
    const SizedBox(height: 8),
    const Text('Organise tes morceaux comme tu veux.', style: TextStyle(color: Colors.white54)),
    const SizedBox(height: 18),
    if (_playlists.isEmpty) _emptyCard(Icons.queue_music_rounded, 'Crée ta première playlist', 'Ajoute tes titres locaux à des collections personnalisées.'),
    ..._playlists.map((playlist) {
      final items = _tracks.where((t) => playlist.paths.contains(t.path)).toList();
      return Container(
        margin: const EdgeInsets.only(bottom: 10),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(18)),
        child: ListTile(
          leading: Container(width: 48, height: 48, decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.queue_music_rounded, color: _accent)),
          title: Text(playlist.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${items.length} titre(s)', style: const TextStyle(color: Colors.white54)),
          onTap: () async {
            if (items.isNotEmpty) await _play(_tracks.indexOf(items.first));
            if (mounted && items.isNotEmpty) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Lecture de « ${playlist.name} » : la file locale est lancée.')));
          },
          trailing: PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'rename') _renamePlaylist(playlist);
              if (value == 'delete') _deletePlaylist(playlist);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Renommer')),
              PopupMenuItem(value: 'delete', child: Text('Supprimer')),
            ],
          ),
        ),
      );
    }),
    const SizedBox(height: 12),
    _actionCard(Icons.save_alt_rounded, 'Exporter une sauvegarde', 'Copier les métadonnées et playlists', _exportBackup),
    _actionCard(Icons.file_open_rounded, 'Importer une sauvegarde', 'Restaurer une sauvegarde JSON', _importBackup),
  ]);

  Widget _settingsPage() => ListView(padding: const EdgeInsets.fromLTRB(18, 8, 18, 28), children: [
    const Text('STUDIO AUDIO', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w900)),
    const SizedBox(height: 5),
    const Text('Façonne le son de tes fichiers locaux.', style: TextStyle(color: Colors.white54)),
    const SizedBox(height: 20),
    Container(
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(22), border: Border.all(color: _accent.withValues(alpha: .18))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Expanded(child: Text('PRÉRÉGLAGES', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1))),
          Text(_preset.toUpperCase(), style: const TextStyle(color: _accent, fontSize: 10, fontWeight: FontWeight.bold)),
        ]),
        const SizedBox(height: 13),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _presetChip('Normal', Icons.graphic_eq_rounded),
          _presetChip('Nightcore', Icons.bolt_rounded),
          _presetChip('Slowed + Reverb', Icons.waves_rounded),
          _presetChip('Bass Boost', Icons.speaker_rounded),
          _presetChip('BassMax', Icons.surround_sound_rounded),
        ]),
      ]),
    ),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.fromLTRB(17, 16, 17, 12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(22)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Expanded(child: Text('PITCH', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1))), Text('${_pitch.toStringAsFixed(2)}×', style: const TextStyle(color: _accent, fontWeight: FontWeight.bold))]),
        const Text('Hauteur du son • Android', style: TextStyle(color: Colors.white54, fontSize: 12)),
        Slider(value: _pitch.clamp(.5, 2.0), min: .5, max: 2.0, divisions: 30, label: '${_pitch.toStringAsFixed(2)}×', onChanged: _setPitch),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Plus grave', style: TextStyle(color: Colors.white38, fontSize: 11)), Text('Plus aigu', style: TextStyle(color: Colors.white38, fontSize: 11))]),
        const SizedBox(height: 15),
        Row(children: [const Expanded(child: Text('VITESSE', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1))), Text('${_speed.toStringAsFixed(2)}×', style: const TextStyle(color: _accent, fontWeight: FontWeight.bold))]),
        const Text('Vitesse de lecture', style: TextStyle(color: Colors.white54, fontSize: 12)),
        Slider(value: _speed.clamp(.5, 2.0), min: .5, max: 2.0, divisions: 30, label: '${_speed.toStringAsFixed(2)}×', onChanged: _setSpeed),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: const [Text('Slowed', style: TextStyle(color: Colors.white38, fontSize: 11)), Text('Rapide', style: TextStyle(color: Colors.white38, fontSize: 11))]),
      ]),
    ),
    const SizedBox(height: 12),
    Container(
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(color: _card2, borderRadius: BorderRadius.circular(17)),
      child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.info_outline_rounded, color: _accent),
        SizedBox(width: 10),
        Expanded(child: Text('Le pitch et la vitesse s’appliquent aux fichiers audio locaux. Le lecteur YouTube intégré garde ses propres contrôles et ne peut pas recevoir ces effets.', style: TextStyle(color: Colors.white70, fontSize: 12, height: 1.4))),
      ]),
    ),
    const SizedBox(height: 22),
    const Text('LECTURE', style: TextStyle(color: _accent, fontWeight: FontWeight.w900, letterSpacing: 1)),
    const SizedBox(height: 8),
    _actionCard(Icons.shuffle_rounded, 'Lecture aléatoire', _shuffle ? 'Activée' : 'Désactivée', () => setState(() => _shuffle = !_shuffle), trailing: Icon(_shuffle ? Icons.check_circle : Icons.circle_outlined, color: _shuffle ? _accent : Colors.white38)),
    _actionCard(Icons.repeat_rounded, 'Répétition', const ['Désactivée', 'Titre actuel', 'Toute la file'][_repeat], () => setState(() => _repeat = (_repeat + 1) % 3), trailing: Icon(_repeat == 0 ? Icons.repeat : _repeat == 1 ? Icons.repeat_one : Icons.repeat_rounded, color: _repeat == 0 ? Colors.white38 : _accent)),
    const SizedBox(height: 16),
    _actionCard(Icons.save_alt_rounded, 'Exporter une sauvegarde', 'Bibliothèque et playlists', _exportBackup),
    _actionCard(Icons.file_open_rounded, 'Importer une sauvegarde', 'Restaurer un fichier JSON', _importBackup),
  ]);

  Widget _presetChip(String name, IconData icon) {
    final selected = _preset == name;
    return ChoiceChip(
      selected: selected,
      onSelected: (_) => _setPreset(name),
      avatar: Icon(icon, size: 17, color: selected ? _bg : _accent),
      label: Text(name),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: selected ? _bg : Colors.white),
      selectedColor: _accent,
      backgroundColor: _card2,
      side: BorderSide(color: selected ? _accent : Colors.white12),
    );
  }

  Widget _miniPlayer(Track track) => Container(
    margin: const EdgeInsets.fromLTRB(10, 0, 10, 8),
    padding: const EdgeInsets.fromLTRB(12, 7, 12, 3),
    decoration: BoxDecoration(color: const Color(0xFF211A2D), borderRadius: BorderRadius.circular(20), border: Border.all(color: _accent.withValues(alpha: .22))),
    child: Column(children: [
      Row(children: [
        Container(width: 42, height: 42, decoration: BoxDecoration(gradient: const LinearGradient(colors: [_accent2, Color(0xFF3B285C)]), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.music_note_rounded)),
        const SizedBox(width: 10),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          Text(_preset, style: const TextStyle(color: _accent, fontSize: 10)),
        ])),
        IconButton(visualDensity: VisualDensity.compact, onPressed: _previous, icon: const Icon(Icons.skip_previous_rounded)),
        StreamBuilder<PlayerState>(stream: _player.playerStateStream, builder: (context, snapshot) => IconButton(
          onPressed: _togglePlayback,
          icon: Icon(snapshot.data?.playing == true ? Icons.pause_circle_filled_rounded : Icons.play_circle_fill_rounded, size: 35, color: _accent),
        )),
        IconButton(visualDensity: VisualDensity.compact, onPressed: _next, icon: const Icon(Icons.skip_next_rounded)),
      ]),
      StreamBuilder<Duration?>(stream: _player.durationStream, builder: (context, durationSnapshot) =>
        StreamBuilder<Duration>(stream: _player.positionStream, builder: (context, positionSnapshot) {
          final duration = durationSnapshot.data ?? Duration.zero;
          final max = duration.inMilliseconds.toDouble().clamp(1.0, double.infinity).toDouble();
          final value = (positionSnapshot.data ?? Duration.zero).inMilliseconds.toDouble().clamp(0.0, max).toDouble();
          return Slider(
            padding: EdgeInsets.zero, min: 0, max: max, value: value,
            onChanged: (v) => _player.seek(Duration(milliseconds: v.round())),
          );
        })),
    ]),
  );

  Widget _emptyCard(IconData icon, String title, String subtitle) => Container(
    padding: const EdgeInsets.all(25),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(21)),
    child: Column(children: [
      Icon(icon, color: _accent, size: 42),
      const SizedBox(height: 10),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(subtitle, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white54, fontSize: 12, height: 1.4)),
    ]),
  );

  Widget _actionCard(IconData icon, String title, String subtitle, VoidCallback action, {Widget? trailing}) => Container(
    margin: const EdgeInsets.only(bottom: 9),
    decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16)),
    child: ListTile(
      onTap: action,
      leading: Icon(icon, color: _accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
      subtitle: Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 11)),
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded, color: Colors.white38),
    ),
  );
}
