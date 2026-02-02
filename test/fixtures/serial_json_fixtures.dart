/// Builds a canonical FlockSquawk serial JSON detection event.
///
/// All fields have sensible defaults that can be overridden individually.
Map<String, dynamic> makeDetectionJson({
  String event = 'target_detected',
  String radio = 'WiFi',
  int channel = 6,
  int rssi = -45,
  String mac = 'B4:1E:52:AA:BB:CC',
  String label = 'Flock-a1b2c3',
  int certainty = 90,
  int alertLevel = 3,
  String category = 'flock_safety_camera',
  Map<String, int>? detectors,
}) {
  return {
    'event': event,
    'source': {
      'radio': radio,
      'channel': channel,
      'rssi': rssi,
    },
    'target': {
      'mac': mac,
      'label': label,
      'certainty': certainty,
      'alert_level': alertLevel,
      'category': category,
      'detectors': detectors ?? {'ssid_format': 75, 'flock_oui': 90},
    },
  };
}
