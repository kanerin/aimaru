import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

// ── ネットワーク上の画像を端末のギャラリーに保存する ────
class ImageSaveService {
  Future<bool> saveFromUrl(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return false;
      await Gal.putImageBytes(response.bodyBytes);
      return true;
    } catch (_) {
      return false;
    }
  }
}
