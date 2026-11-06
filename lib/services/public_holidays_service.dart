import 'dart:convert';
import 'dart:io';

class PublicHoliday {
  const PublicHoliday({required this.date, required this.name});

  final DateTime date;
  final String name;

  factory PublicHoliday.fromJson(Map<String, dynamic> json) => PublicHoliday(
    date: DateTime.parse(json['date'] as String),
    name: (json['localName'] as String?)?.trim().isNotEmpty == true
        ? json['localName'] as String
        : json['name'] as String? ?? 'Jour férié',
  );
}

class PublicHolidaysService {
  static final Map<int, List<PublicHoliday>> _cache = {};
  static String? _cachedCountry;

  Future<List<PublicHoliday>> forRange(
    DateTime start,
    DateTime end,
    String countryCode,
  ) async {
    if (_cachedCountry != countryCode) {
      _cache.clear();
      _cachedCountry = countryCode;
    }
    final years = <int>{for (var y = start.year; y <= end.year; y++) y};
    final results = await Future.wait(
      years.map((year) => _forYear(year, countryCode)),
    );
    return results.expand((items) => items).where((holiday) {
      final date = DateTime(
        holiday.date.year,
        holiday.date.month,
        holiday.date.day,
      );
      return !date.isBefore(DateTime(start.year, start.month, start.day)) &&
          !date.isAfter(DateTime(end.year, end.month, end.day));
    }).toList()..sort((a, b) => a.date.compareTo(b.date));
  }

  Future<List<PublicHoliday>> _forYear(int year, String countryCode) async {
    final cached = _cache[year];
    if (cached != null) return cached;
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final uri = Uri.https(
        'date.nager.at',
        '/api/v3/PublicHolidays/$year/$countryCode',
      );
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != 200) {
        throw HttpException(
          'Jours fériés indisponibles (${response.statusCode}).',
        );
      }
      final decoded = jsonDecode(body);
      if (decoded is! List) {
        throw const FormatException('Liste de jours fériés invalide.');
      }
      final holidays = decoded
          .map(
            (item) =>
                PublicHoliday.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList();
      _cache[year] = holidays;
      return holidays;
    } finally {
      client.close(force: true);
    }
  }
}
