import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bett_box/common/metron_session.dart';
import 'package:bett_box/providers/providers.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:synchronized/synchronized.dart';

final metronFavoritesProvider = NotifierProvider<MetronFavorites, Set<String>>(
  MetronFavorites.new,
);
final metronFavoritesOnlyProvider = NotifierProvider<MetronFavoritesOnly, bool>(
  MetronFavoritesOnly.new,
);

class MetronFavoritesOnly extends Notifier<bool> {
  @override
  bool build() {
    ref.watch(currentProfileIdProvider);
    return false;
  }

  void toggle() => state = !state;
}

class MetronFavorites extends Notifier<Set<String>> {
  final _lock = Lock();
  int _revision = 0;
  String _key = '';
  Future<void> _loaded = Future.value();
  @override
  Set<String> build() {
    ref.watch(currentProfileIdProvider);
    final revision = ++_revision;
    _key =
        'metron.favorites.${sha256.convert(utf8.encode('${MetronSession.panelUrl}/${metronSession.email.toLowerCase()}'))}';
    final key = _key;
    _loaded = () async {
      final prefs = await SharedPreferences.getInstance();
      if (ref.mounted && revision == _revision) {
        state = (prefs.getStringList(key) ?? []).toSet();
      }
    }();
    unawaited(_loaded);
    return {};
  }

  Future<void> toggle(String name) async {
    final key = _key;
    await _loaded;
    if (!ref.mounted || key != _key) return;
    final next = {...state};
    if (!next.remove(name)) next.add(name);
    state = next;
    await _lock.synchronized(() async {
      final prefs = await SharedPreferences.getInstance();
      if (!await prefs.setStringList(key, next.toList())) {
        throw StateError('Cannot save favorites');
      }
    });
  }
}
