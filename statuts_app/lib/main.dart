import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';

import 'store.dart';

void main() => runApp(const StatutsApp());

class StatutsApp extends StatelessWidget {
  const StatutsApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Statuts',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF075E54), useMaterial3: true),
      darkTheme: ThemeData(
          colorSchemeSeed: const Color(0xFF075E54),
          brightness: Brightness.dark,
          useMaterial3: true),
      home: const Gate(),
    );
  }
}

// ───────────────────────── Dates (FR, sans dépendance de locale) ─────────────────────────
const _jours = ['lundi', 'mardi', 'mercredi', 'jeudi', 'vendredi', 'samedi', 'dimanche'];
const _mois = [
  'janvier', 'février', 'mars', 'avril', 'mai', 'juin',
  'juillet', 'août', 'septembre', 'octobre', 'novembre', 'décembre'
];
String fmtDate(String s) {
  final d = DateTime.parse(s);
  return '${_jours[d.weekday - 1]} ${d.day} ${_mois[d.month - 1]}';
}

String fmtSize(int b) =>
    b > 1048576 ? '${(b / 1048576).toStringAsFixed(1)} Mo' : '${(b / 1024).round()} Ko';

// ───────────────────────── Code d'accès ─────────────────────────
String _hash(String pin) => sha256.convert(utf8.encode('statuts|$pin')).toString();

class Gate extends StatefulWidget {
  const Gate({super.key});
  @override
  State<Gate> createState() => _GateState();
}

class _GateState extends State<Gate> with WidgetsBindingObserver {
  SharedPreferences? prefs;
  Store? store;
  bool unlocked = false;
  DateTime? pausedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final pr = await SharedPreferences.getInstance();
    final st = await Store.open();
    setState(() {
      prefs = pr;
      store = st;
      // Le code n'est demandé qu'à la création, après un verrouillage manuel (🔒),
      // ou à chaque ouverture si l'option est activée dans les réglages.
      unlocked = pr.getString('pin') != null &&
          !(pr.getBool('autolock') ?? false) &&
          !(pr.getBool('locked') ?? false);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.paused) pausedAt = DateTime.now();
    if (s == AppLifecycleState.resumed && pausedAt != null) {
      // Reverrouillage automatique seulement si l'option est activée (et pas pendant un partage < 2 min).
      if ((prefs?.getBool('autolock') ?? false) &&
          DateTime.now().difference(pausedAt!) > const Duration(minutes: 2)) {
        setState(() => unlocked = false);
      }
      pausedAt = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (prefs == null || store == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!unlocked) {
      return LockScreen(prefs: prefs!, onUnlock: () => setState(() => unlocked = true));
    }
    return Home(store: store!, prefs: prefs!, onLock: () {
      prefs!.setBool('locked', true);
      setState(() => unlocked = false);
    });
  }
}

class LockScreen extends StatefulWidget {
  const LockScreen({super.key, required this.prefs, required this.onUnlock});
  final SharedPreferences prefs;
  final VoidCallback onUnlock;
  @override
  State<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<LockScreen> {
  final pin = TextEditingController();
  final pin2 = TextEditingController();
  String err = '';
  bool get hasPin => widget.prefs.getString('pin') != null;

  void submit() {
    if (hasPin) {
      if (_hash(pin.text) == widget.prefs.getString('pin')) {
        widget.prefs.setBool('locked', false);
        widget.onUnlock();
      } else {
        setState(() => err = 'Code incorrect');
        pin.clear();
      }
    } else {
      if (pin.text.length < 4) return setState(() => err = 'Au moins 4 caractères');
      if (pin.text != pin2.text) return setState(() => err = 'Les codes ne correspondent pas');
      widget.prefs.setString('pin', _hash(pin.text));
      widget.prefs.setBool('locked', false);
      widget.onUnlock();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.primary,
      body: Center(
        child: Card(
          margin: const EdgeInsets.all(24),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 340),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.lock_outline, size: 40),
                const SizedBox(height: 8),
                Text(hasPin ? 'Accès privé' : 'Créer votre code',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(hasPin ? 'Entrez votre code' : 'Choisissez un code (4 caractères minimum)',
                    textAlign: TextAlign.center),
                const SizedBox(height: 16),
                TextField(
                  controller: pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  autofocus: true,
                  decoration: const InputDecoration(border: OutlineInputBorder(), hintText: '••••'),
                  onSubmitted: (_) => hasPin ? submit() : null,
                ),
                if (!hasPin) ...[
                  const SizedBox(height: 10),
                  TextField(
                    controller: pin2,
                    obscureText: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                        border: OutlineInputBorder(), hintText: 'Confirmer'),
                  ),
                ],
                SizedBox(
                    height: 28,
                    child: Center(
                        child: Text(err, style: TextStyle(color: cs.error, fontSize: 13)))),
                SizedBox(
                    width: double.infinity,
                    child: FilledButton(onPressed: submit, child: Text(hasPin ? 'Entrer' : 'Enregistrer'))),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Écran principal ─────────────────────────
class Home extends StatefulWidget {
  const Home({super.key, required this.store, required this.prefs, required this.onLock});
  final Store store;
  final SharedPreferences prefs;
  final VoidCallback onLock;
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int tab = 0;
  String filter = 'todo';
  Post? editing;

  Store get st => widget.store;
  int get batch => widget.prefs.getInt('batch') ?? kMaxFiles;

  void refresh() => setState(() {});

  List<Post> get due {
    final now = DateTime.now();
    return st.posts.where((e) => e.dueOn(now)).toList();
  }

  void toast(String m) =>
      ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(m)));

  Future<void> shareLot(Post post, int lot) async {
    final start = lot * batch;
    final rels = post.files.skip(start).take(batch).toList();
    final files = <XFile>[];
    for (final r in rels) {
      final path = st.abs(post, r);
      if (await File(path).exists()) files.add(XFile(path));
    }
    if (files.isEmpty && post.caption.isEmpty) return toast('Rien à partager');
    if (post.caption.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: post.caption));
    }
    try {
      final res = await Share.shareXFiles(files, text: post.caption.isEmpty ? null : post.caption);
      if (res.status == ShareResultStatus.dismissed) return;
    } catch (e) {
      return toast('Partage impossible : $e');
    }
    final isLast = (lot + 1) * batch >= post.files.length;
    if (!mounted || !isLast) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Statut publié ?'),
        content: const Text('Avez-vous publié ce statut sur WhatsApp ?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Pas encore')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Oui, publié')),
        ],
      ),
    );
    if (ok == true) await setDone(post, true);
  }

  Future<void> setDone(Post post, bool done) async {
    if (post.recurring) {
      // Statut récurrent : on coche seulement le jour d'aujourd'hui.
      final t = ymd(DateTime.now());
      post.doneDates.remove(t);
      if (done) post.doneDates.add(t);
    } else {
      post.done = done;
      post.doneAt = done ? DateTime.now().millisecondsSinceEpoch : null;
    }
    await st.save();
    refresh();
    toast(done ? 'Publié ✓' : 'Remis à publier');
  }

  Future<void> remove(Post post) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Supprimer ce statut ?'),
        content: const Text('Les fichiers seront effacés de l\'appli.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Supprimer')),
        ],
      ),
    );
    if (ok == true) {
      await st.deletePost(post);
      refresh();
    }
  }

  Future<void> batchDialog() async {
    var v = batch.toDouble();
    var auto = widget.prefs.getBool('autolock') ?? false;
    await showDialog<void>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, set) => AlertDialog(
          title: const Text('Réglages'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('Si WhatsApp refuse ou coupe un envoi trop gros, diminuez ce nombre : '
                'un statut de plus de fichiers sera alors partagé en plusieurs lots.'),
            Slider(value: v, min: 5, max: 50, divisions: 9, label: v.round().toString(),
                onChanged: (x) => set(() => v = x)),
            Text('${v.round()} fichiers par envoi'),
            const Divider(height: 24),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Demander le code à chaque ouverture'),
              subtitle: const Text('Désactivé : le code n\'est demandé qu\'après le bouton 🔒.'),
              value: auto,
              onChanged: (x) => set(() => auto = x),
            ),
          ]),
          actions: [
            TextButton(
                onPressed: () {
                  widget.prefs.setInt('batch', v.round());
                  widget.prefs.setBool('autolock', auto);
                  Navigator.pop(c);
                  refresh();
                },
                child: const Text('OK'))
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final titles = ['Aujourd\'hui', 'Planning', editing == null ? 'Nouveau statut' : 'Modifier'];
    final nDue = due.length;
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[tab]),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Theme.of(context).colorScheme.onPrimary,
        actions: [
          IconButton(icon: const Icon(Icons.tune), tooltip: 'Réglages', onPressed: batchDialog),
          IconButton(icon: const Icon(Icons.lock_outline), tooltip: 'Verrouiller', onPressed: widget.onLock),
        ],
      ),
      body: SafeArea(child: _body()),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() {
          if (i == 2 && tab != 2) editing = null;
          tab = i;
        }),
        destinations: [
          NavigationDestination(
              icon: Badge(isLabelVisible: nDue > 0, label: Text('$nDue'), child: const Icon(Icons.send_outlined)),
              label: 'Aujourd\'hui'),
          const NavigationDestination(icon: Icon(Icons.calendar_month_outlined), label: 'Planning'),
          const NavigationDestination(icon: Icon(Icons.add_circle_outline), label: 'Ajouter'),
        ],
      ),
    );
  }

  Widget _body() {
    if (tab == 2) {
      return PostForm(
        key: ValueKey(editing?.id ?? 'new'),
        store: st,
        post: editing,
        onDone: () => setState(() {
          editing = null;
          tab = 1;
          filter = 'todo';
        }),
        onCancel: () => setState(() {
          editing = null;
          tab = 1;
        }),
      );
    }
    final t = ymd(DateTime.now());
    if (tab == 0) {
      final doneToday = st.posts.where((e) => e.recurring
          ? e.doneDates.contains(t)
          : e.done && e.doneAt != null && ymd(DateTime.fromMillisecondsSinceEpoch(e.doneAt!)) == t);
      final next = st.posts.where((e) => !e.recurring && !e.done && e.date.compareTo(t) > 0).firstOrNull;
      return ListView(padding: const EdgeInsets.all(16), children: [
        if (due.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 48),
            child: Column(children: [
              const Text('🎉', style: TextStyle(fontSize: 44)),
              const SizedBox(height: 8),
              Text('Rien à publier aujourd\'hui.${next != null ? '\nProchain statut : ${fmtDate(next.date)}' : ''}',
                  textAlign: TextAlign.center),
            ]),
          )
        else ...[
          _h('À publier (${due.length})'),
          ...due.map(_card),
        ],
        if (doneToday.isNotEmpty) ...[_h('Publiés aujourd\'hui'), ...doneToday.map(_card)],
      ]);
    }
    final recurring = filter == 'done' ? <Post>[] : st.posts.where((e) => e.recurring).toList();
    final list = st.posts
        .where((e) => !e.recurring && (filter == 'todo' ? !e.done : filter == 'done' ? e.done : true))
        .toList();
    if (filter == 'done') list.sort((a, b) => b.date.compareTo(a.date));
    final kids = <Widget>[
      Wrap(spacing: 8, children: [
        for (final f in const [['todo', 'À publier'], ['done', 'Publiés'], ['all', 'Tous']])
          ChoiceChip(label: Text(f[1]), selected: filter == f[0], onSelected: (_) => setState(() => filter = f[0])),
      ]),
      const SizedBox(height: 8),
    ];
    if (recurring.isNotEmpty) {
      kids.add(_h('🔁 Statuts récurrents'));
      kids.addAll(recurring.map(_card));
    }
    if (list.isEmpty && recurring.isEmpty) {
      kids.add(const Padding(padding: EdgeInsets.all(48), child: Center(child: Text('Aucun statut ici.'))));
    }
    var last = '';
    for (final e in list) {
      if (e.date != last) {
        kids.add(_h(fmtDate(e.date)));
        last = e.date;
      }
      kids.add(_card(e));
    }
    return ListView(padding: const EdgeInsets.all(16), children: kids);
  }

  Widget _h(String s) => Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Text(s.toUpperCase(),
          style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12, color: Theme.of(context).hintColor)));

  Widget _card(Post post) {
    final t = ymd(DateTime.now());
    final isDone = post.doneOn(t);
    final late = !post.recurring && !post.done && post.date.compareTo(t) < 0;
    final cs = Theme.of(context).colorScheme;
    final lots = (post.files.length / batch).ceil();
    return Card(
      key: ValueKey(post.id),
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (post.files.isNotEmpty)
            SizedBox(
              height: 112,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: post.files.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (_, i) => Thumb(path: st.abs(post, post.files[i]), size: 112),
              ),
            ),
          if (post.files.isNotEmpty) const SizedBox(height: 8),
          if (post.caption.isNotEmpty) Padding(padding: const EdgeInsets.only(bottom: 6), child: Text(post.caption)),
          Wrap(spacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (post.recurring) Chip(label: Text('🔁 ${post.repeatLabel}'), backgroundColor: cs.tertiaryContainer, visualDensity: VisualDensity.compact),
            if (isDone) Chip(label: Text(post.recurring ? '✓ Publié aujourd\'hui' : '✓ Publié'), visualDensity: VisualDensity.compact)
            else if (late) Chip(label: const Text('En retard'), backgroundColor: cs.errorContainer, visualDensity: VisualDensity.compact)
            else if (!post.recurring && post.date == t) Chip(label: const Text('Aujourd\'hui'), backgroundColor: cs.primaryContainer, visualDensity: VisualDensity.compact),
            Text('${post.recurring ? 'Dès le ${fmtDate(post.date)}' : fmtDate(post.date)}${post.time.isEmpty ? '' : ' · ${post.time}'} · ${post.files.length} fichier${post.files.length > 1 ? 's' : ''}',
                style: TextStyle(fontSize: 12, color: Theme.of(context).hintColor)),
          ]),
          const SizedBox(height: 8),
          if (!isDone)
            for (var l = 0; l < (lots == 0 ? 1 : lots); l++)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF25D366),
                        foregroundColor: const Color(0xFF04361F),
                        padding: const EdgeInsets.symmetric(vertical: 14)),
                    onPressed: () => shareLot(post, l),
                    icon: const Icon(Icons.send),
                    label: Text(lots <= 1
                        ? 'Partager sur WhatsApp'
                        : 'Partager lot ${l + 1}/$lots'),
                  ),
                ),
              ),
          Wrap(spacing: 4, children: [
            if (!isDone && post.caption.isNotEmpty)
              TextButton.icon(
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: post.caption));
                    toast('Légende copiée ✓');
                  },
                  icon: const Icon(Icons.copy, size: 18),
                  label: const Text('Légende')),
            if (!isDone)
              TextButton.icon(onPressed: () => setDone(post, true), icon: const Icon(Icons.check, size: 18), label: const Text('Publié'))
            else
              TextButton.icon(onPressed: () => setDone(post, false), icon: const Icon(Icons.undo, size: 18), label: const Text('Remettre à publier')),
            IconButton(
                tooltip: 'Modifier',
                onPressed: () => setState(() {
                      editing = post;
                      tab = 2;
                    }),
                icon: const Icon(Icons.edit_outlined)),
            IconButton(tooltip: 'Supprimer', onPressed: () => remove(post), icon: Icon(Icons.delete_outline, color: cs.error)),
          ]),
        ]),
      ),
    );
  }
}

class Thumb extends StatelessWidget {
  const Thumb({super.key, required this.path, required this.size});
  final String path;
  final double size;
  @override
  Widget build(BuildContext context) {
    final vid = isVideo(path);
    final len = File(path).existsSync() ? File(path).lengthSync() : 0;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: size * 0.75,
        height: size,
        child: Stack(fit: StackFit.expand, children: [
          vid
              ? Container(color: Colors.black87, child: const Icon(Icons.play_circle_outline, color: Colors.white, size: 40))
              : Image.file(File(path), fit: BoxFit.cover, cacheWidth: 300,
                  errorBuilder: (_, __, ___) => const ColoredBox(color: Colors.black12, child: Icon(Icons.broken_image))),
          Positioned(
              left: 4,
              bottom: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
                child: Text('${vid ? '🎬 ' : ''}${fmtSize(len)}', style: const TextStyle(color: Colors.white, fontSize: 10)),
              )),
        ]),
      ),
    );
  }
}

// ───────────────────────── Formulaire (jusqu'à 50 fichiers) ─────────────────────────
class PostForm extends StatefulWidget {
  const PostForm({super.key, required this.store, this.post, required this.onDone, required this.onCancel});
  final Store store;
  final Post? post;
  final VoidCallback onDone;
  final VoidCallback onCancel;
  @override
  State<PostForm> createState() => _PostFormState();
}

class _PostFormState extends State<PostForm> {
  late final String id;
  late List<String> existing; // déjà dans le dossier du post
  final List<String> picked = []; // chemins temporaires à importer
  final List<String> removed = [];
  late final TextEditingController cap;
  late DateTime date;
  TimeOfDay? time;
  String repeat = 'none';
  final Set<int> days = {};
  bool busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.post;
    id = e?.id ?? DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    existing = [...?e?.files];
    cap = TextEditingController(text: e?.caption ?? '');
    date = e != null ? DateTime.parse(e.date) : DateTime.now();
    repeat = e?.repeat ?? 'none';
    days.addAll(e?.days ?? const []);
    if (e != null && e.time.isNotEmpty) {
      final s = e.time.split(':');
      time = TimeOfDay(hour: int.parse(s[0]), minute: int.parse(s[1]));
    }
  }

  int get count => existing.length + picked.length;

  Future<void> pick() async {
    final room = kMaxFiles - count;
    if (room <= 0) return _msg('Maximum $kMaxFiles fichiers par statut');
    // Galerie intégrée à l'app : photos et vidéos du téléphone, sélection multiple.
    List<AssetEntity>? assets;
    try {
      assets = await AssetPicker.pickAssets(
        context,
        pickerConfig: AssetPickerConfig(
          maxAssets: room,
          requestType: RequestType.common,
          gridCount: 4,
        ),
      );
    } catch (e) {
      return _msg('Galerie indisponible : $e');
    }
    if (assets == null || assets.isEmpty) return;
    final paths = <String>[];
    for (final a in assets) {
      final f = await a.originFile;
      if (f != null) paths.add(f.path);
    }
    if (paths.isEmpty) return _msg('Impossible de lire les fichiers choisis');
    if (paths.length > room) _msg('Seuls $room fichiers ajoutés (maximum $kMaxFiles)');
    final added = paths.take(room).toList();
    setState(() => picked.addAll(added));
    _msg('${added.length} fichier${added.length > 1 ? 's' : ''} ajouté${added.length > 1 ? 's' : ''} (${picked.length + existing.length}/$kMaxFiles)');
  }

  void _msg(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> save() async {
    if (count == 0 && cap.text.trim().isEmpty) return _msg('Ajoutez une photo, une vidéo ou un texte');
    if (repeat == 'days' && days.isEmpty) return _msg('Choisissez au moins un jour');
    setState(() => busy = true);
    final st = widget.store;
    Post? post = widget.post;
    final isNew = post == null;
    post ??= Post(id: id, files: [], caption: '', date: ymd(date));
    for (final r in removed) {
      await st.removeFile(post, r);
    }
    final added = await st.importFiles(id, picked);
    post
      ..files = [...existing, ...added]
      ..caption = cap.text.trim()
      ..date = ymd(date)
      ..repeat = repeat
      ..days = (days.toList()..sort())
      ..time = time == null ? '' : '${time!.hour.toString().padLeft(2, '0')}:${time!.minute.toString().padLeft(2, '0')}';
    if (isNew) st.posts.add(post);
    await st.save();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final st = widget.store;
    final tiles = <Widget>[
      for (var i = 0; i < existing.length; i++)
        _tile(Thumb(path: p.join(st.root.path, id, existing[i]), size: 100), () => setState(() {
              removed.add(existing[i]);
              existing.removeAt(i);
            })),
      for (var i = 0; i < picked.length; i++)
        _tile(Thumb(path: picked[i], size: 100), () => setState(() => picked.removeAt(i))),
    ];
    return ListView(padding: const EdgeInsets.all(16), children: [
      Card(
        color: Theme.of(context).colorScheme.secondaryContainer,
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: Text('📌 Les fichiers sont copiés dans l\'appli (stockage privé du téléphone). '
              'Rien n\'est envoyé sur internet.'),
        ),
      ),
      const SizedBox(height: 12),
      OutlinedButton.icon(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 18)),
        onPressed: busy ? null : pick,
        icon: const Icon(Icons.add_photo_alternate_outlined),
        label: Text('Choisir photos / vidéos ($count/$kMaxFiles)'),
      ),
      if (tiles.isNotEmpty) ...[
        const SizedBox(height: 12),
        Wrap(spacing: 6, runSpacing: 6, children: tiles),
      ],
      const SizedBox(height: 16),
      TextField(
        controller: cap,
        minLines: 3,
        maxLines: 8,
        decoration: const InputDecoration(labelText: 'Légende / texte', border: OutlineInputBorder()),
      ),
      const SizedBox(height: 16),
      const Text('Répétition', style: TextStyle(fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      SegmentedButton<String>(
        showSelectedIcon: false,
        segments: const [
          ButtonSegment(value: 'none', label: Text('Une fois')),
          ButtonSegment(value: 'daily', label: Text('Chaque jour')),
          ButtonSegment(value: 'days', label: Text('Jours choisis')),
        ],
        selected: {repeat},
        onSelectionChanged: (v) => setState(() => repeat = v.first),
      ),
      if (repeat == 'days') ...[
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          for (var i = 1; i <= 7; i++)
            FilterChip(
              label: Text(const ['Lun', 'Mar', 'Mer', 'Jeu', 'Ven', 'Sam', 'Dim'][i - 1]),
              selected: days.contains(i),
              onSelected: (v) => setState(() => v ? days.add(i) : days.remove(i)),
            ),
        ]),
      ],
      if (repeat != 'none')
        const Padding(
          padding: EdgeInsets.only(top: 6),
          child: Text('Ce statut réapparaîtra dans « Aujourd\'hui » chaque matin prévu, '
              'et restera dans l\'appli pour être republié.',
              style: TextStyle(fontSize: 12)),
        ),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.event),
            label: Text('${repeat == 'none' ? '' : 'Dès le '}${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}'),
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final d = await showDatePicker(
                  context: context,
                  initialEntryMode: DatePickerEntryMode.calendarOnly,
                  initialDate: date,
                  firstDate: DateTime.now().subtract(const Duration(days: 365)),
                  lastDate: DateTime.now().add(const Duration(days: 730)));
              FocusManager.instance.primaryFocus?.unfocus();
              if (d != null) setState(() => date = d);
            },
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: OutlinedButton.icon(
            icon: const Icon(Icons.schedule),
            label: Text(time == null ? 'Heure (option)' : time!.format(context)),
            onPressed: () async {
              FocusManager.instance.primaryFocus?.unfocus();
              final t = await showTimePicker(
                  context: context,
                  initialEntryMode: TimePickerEntryMode.dial,
                  initialTime: time ?? TimeOfDay.now());
              FocusManager.instance.primaryFocus?.unfocus();
              if (t != null) setState(() => time = t);
            },
          ),
        ),
      ]),
      const SizedBox(height: 20),
      Row(children: [
        Expanded(
            child: FilledButton(
                onPressed: busy ? null : save,
                child: busy
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(widget.post == null ? 'Planifier' : 'Enregistrer'))),
        if (widget.post != null) ...[
          const SizedBox(width: 8),
          OutlinedButton(onPressed: busy ? null : widget.onCancel, child: const Text('Annuler')),
        ],
      ]),
    ]);
  }

  Widget _tile(Widget child, VoidCallback onRemove) => Stack(children: [
        child,
        Positioned(
          top: 2,
          right: 2,
          child: InkWell(
            onTap: onRemove,
            child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54, child: Icon(Icons.close, size: 16, color: Colors.white)),
          ),
        ),
      ]);
}
