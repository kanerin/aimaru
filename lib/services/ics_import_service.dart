import 'package:http/http.dart' as http;

// URLで公開されているiCalendar(.ics)を取得する。パース自体はutils/ics_parser.dartが担う。
class IcsImportService {
  Future<String> fetchIcsText(String url) async {
    final uri = Uri.parse(_normalize(url.trim()));
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      throw Exception('カレンダーの取得に失敗しました (HTTP ${response.statusCode})');
    }
    return response.body;
  }

  // webcal:// はカレンダーアプリ専用のスキームで、http.getでは扱えないためhttpsに読み替える
  String _normalize(String url) {
    if (url.startsWith('webcal://')) return 'https://${url.substring('webcal://'.length)}';
    return url;
  }
}
