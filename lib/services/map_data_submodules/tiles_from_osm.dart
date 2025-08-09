import 'dart:math';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Fetches a tile from OSM, with in-memory retries/backoff.
/// Returns tile image bytes, or throws on persistent failure.
Future<List<int>> fetchOSMTile({
  required int z,
  required int x,
  required int y,
}) async {
  final url = 'https://tile.openstreetmap.org/$z/$x/$y.png';
  const int maxAttempts = 3;
  int attempt = 0;
  final random = Random();
  final delays = [
    0,
    3000 + random.nextInt(1000) - 500,
    10000 + random.nextInt(4000) - 2000
  ];
  while (true) {
    try {
      print('[fetchOSMTile] FETCH $z/$x/$y');
      attempt++;
      final resp = await http.get(Uri.parse(url));
      if (resp.statusCode == 200) {
        return resp.bodyBytes;
      } else {
        throw HttpException('Failed to fetch tile $z/$x/$y: status ${resp.statusCode}');
      }
    } catch (e) {
      if (attempt >= maxAttempts) {
        print("[fetchOSMTile] Failed for $z/$x/$y after $attempt attempts: $e");
        rethrow;
      }
      final delay = delays[attempt - 1].clamp(0, 60000);
      print("[fetchOSMTile] Attempt $attempt for $z/$x/$y failed: $e. Retrying in ${delay}ms.");
      await Future.delayed(Duration(milliseconds: delay));
    }
  }
}
