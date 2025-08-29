import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/node_profile.dart';

class ProfileService {
  static const _key = 'custom_profiles';

  Future<List<NodeProfile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list.map((e) => NodeProfile.fromJson(e)).toList();
  }

  Future<void> save(List<NodeProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();

    // MUST convert to List before jsonEncode; the previous MappedIterable
    // caused "Converting object to an encodable object failed".
    final encodable = profiles
        .where((p) => !p.builtin)
        .map((p) => p.toJson())
        .toList(); // <- crucial

    await prefs.setString(_key, jsonEncode(encodable));
  }
}
