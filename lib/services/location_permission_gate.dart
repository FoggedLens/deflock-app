import 'package:geolocator/geolocator.dart';

/// Single-flight guard around [Geolocator.requestPermission].
///
/// The Android geolocator plugin can only track one in-flight permission
/// request at a time. If a second `requestPermission()` call is made while
/// the system dialog from a first call is still pending, the plugin tries to
/// reply to the same result callback twice and crashes with
/// `IllegalStateException: Reply already submitted`.
///
/// We have more than one place in the app that may want to (re)check/request
/// location permission around app startup (GPS controller, first-launch
/// prompt). Rather than coordinate all of them, just make sure only one real
/// native call is ever in flight - everyone else awaits that same result.
Future<LocationPermission>? _inFlight;

Future<LocationPermission> requestLocationPermissionOnce() {
  return _inFlight ??= Geolocator.requestPermission().whenComplete(() {
    _inFlight = null;
  });
}
