import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/operator_profile.dart';

class OperatorProfileService {
  static const _key = 'operator_profiles';

  Future<List<OperatorProfile>> load() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString(_key);
    if (jsonStr == null) return [];
    final list = jsonDecode(jsonStr) as List<dynamic>;
    return list.map((e) => OperatorProfile.fromJson(e)).toList();
  }

  Future<void> save(List<OperatorProfile> profiles) async {
    final prefs = await SharedPreferences.getInstance();
    final encodable = profiles.map((p) => p.toJson()).toList();
    await prefs.setString(_key, jsonEncode(encodable));
  }
}