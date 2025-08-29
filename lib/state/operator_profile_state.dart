import 'package:flutter/material.dart';

import '../models/operator_profile.dart';
import '../services/operator_profile_service.dart';

class OperatorProfileState extends ChangeNotifier {
  final List<OperatorProfile> _profiles = [];

  List<OperatorProfile> get profiles => List.unmodifiable(_profiles);

  Future<void> init() async {
    _profiles.addAll(await OperatorProfileService().load());
  }

  void addOrUpdateProfile(OperatorProfile p) {
    final idx = _profiles.indexWhere((x) => x.id == p.id);
    if (idx >= 0) {
      _profiles[idx] = p;
    } else {
      _profiles.add(p);
    }
    OperatorProfileService().save(_profiles);
    notifyListeners();
  }

  void deleteProfile(OperatorProfile p) {
    _profiles.removeWhere((x) => x.id == p.id);
    OperatorProfileService().save(_profiles);
    notifyListeners();
  }
}