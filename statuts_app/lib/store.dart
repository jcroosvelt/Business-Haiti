import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

const int kMaxFiles = 50;

class Post {
  Post({
    required this.id,
    required this.files,
    required this.caption,
    required this.date,
    this.time = '',
    this.done = false,
    this.doneAt,
    this.repeat = 'none',
    List<int>? days,
    List<String>? doneDates,
  })  : days = days ?? [],
        doneDates = doneDates ?? [];

  final String id;
  List<String> files; // chemins relatifs au dossier média
  String caption;
  String date; // yyyy-MM-dd
  String time; // HH:mm ou vide
  bool done;
  int? doneAt;
  String repeat; // 'none' | 'daily' | 'days'
  List<int> days; // jours de la semaine (1 = lundi … 7 = dimanche) si repeat == 'days'
  List<String> doneDates; // jours déjà publiés (statuts récurrents)

  bool get recurring => repeat != 'none';
  bool runsOn(DateTime d) => repeat == 'daily' || (repeat == 'days' && days.contains(d.weekday));
  bool doneOn(String ds) => recurring ? doneDates.contains(ds) : done;

  /// À publier le jour [d] ? (statut ponctuel : jusqu'à publication ; récurrent : les jours prévus)
  bool dueOn(DateTime d) {
    final ds = ymd(d);
    if (recurring) return date.compareTo(ds) <= 0 && runsOn(d) && !doneDates.contains(ds);
    return !done && date.compareTo(ds) <= 0;
  }

  String get repeatLabel {
    if (repeat == 'daily') return 'Chaque jour';
    const n = ['lun', 'mar', 'mer', 'jeu', 'ven', 'sam', 'dim'];
    final d = [...days]..sort();
    return d.map((i) => n[i - 1]).join(', ');
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'files': files,
        'caption': caption,
        'date': date,
        'time': time,
        'done': done,
        'doneAt': doneAt,
        'repeat': repeat,
        'days': days,
        'doneDates': doneDates,
      };

  factory Post.fromJson(Map<String, dynamic> j) => Post(
        id: j['id'] as String,
        files: List<String>.from(j['files'] as List),
        caption: (j['caption'] ?? '') as String,
        date: j['date'] as String,
        time: (j['time'] ?? '') as String,
        done: (j['done'] ?? false) as bool,
        doneAt: j['doneAt'] as int?,
        repeat: (j['repeat'] ?? 'none') as String,
        days: List<int>.from((j['days'] ?? []) as List),
        doneDates: List<String>.from((j['doneDates'] ?? []) as List),
      );
}

String ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Stockage 100 % local : médias + JSON dans le dossier privé de l'appli.
class Store {
  Store._(this.root);
  final Directory root;
  List<Post> posts = [];

  static Future<Store> open() async {
    final base = await getApplicationDocumentsDirectory();
    final s = Store._(Directory(p.join(base.path, 'statuts')));
    await s.root.create(recursive: true);
    await s._load();
    return s;
  }

  File get _json => File(p.join(root.path, 'posts.json'));

  Future<void> _load() async {
    if (!await _json.exists()) return;
    try {
      final list = jsonDecode(await _json.readAsString()) as List;
      posts = list.map((e) => Post.fromJson(e as Map<String, dynamic>)).toList();
    } catch (_) {
      posts = [];
    }
  }

  Future<void> save() async {
    posts.sort((a, b) => ('${a.date}${a.time.isEmpty ? '99' : a.time}')
        .compareTo('${b.date}${b.time.isEmpty ? '99' : b.time}'));
    final tmp = File('${_json.path}.tmp');
    await tmp.writeAsString(jsonEncode(posts.map((e) => e.toJson()).toList()));
    await tmp.rename(_json.path);
  }

  String abs(Post post, String rel) => p.join(root.path, post.id, rel);

  /// Copie les fichiers choisis dans le dossier privé du post.
  Future<List<String>> importFiles(String postId, List<String> sources) async {
    final dir = Directory(p.join(root.path, postId));
    await dir.create(recursive: true);
    final existing = dir.listSync().length;
    final out = <String>[];
    for (var i = 0; i < sources.length; i++) {
      final name = '${(existing + i).toString().padLeft(3, '0')}_${p.basename(sources[i])}';
      await File(sources[i]).copy(p.join(dir.path, name));
      out.add(name);
    }
    return out;
  }

  Future<void> removeFile(Post post, String rel) async {
    final f = File(abs(post, rel));
    if (await f.exists()) await f.delete();
  }

  Future<void> deletePost(Post post) async {
    final dir = Directory(p.join(root.path, post.id));
    if (await dir.exists()) await dir.delete(recursive: true);
    posts.removeWhere((e) => e.id == post.id);
    await save();
  }
}

bool isVideo(String path) {
  final e = p.extension(path).toLowerCase();
  return const ['.mp4', '.mov', '.3gp', '.mkv', '.webm', '.avi', '.m4v'].contains(e);
}
