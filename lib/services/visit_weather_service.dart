import 'dart:convert';
import 'dart:io';

class VisitWeather {
  const VisitWeather({
    required this.description,
    required this.temperatureMax,
    required this.rainProbability,
  });

  final String description;
  final num temperatureMax;
  final num rainProbability;

  factory VisitWeather.fromJson(Map<String, dynamic> json) {
    final daily = Map<String, dynamic>.from(json['daily'] as Map);
    final codes = (daily['weather_code'] ?? daily['weathercode']) as List;
    final temps = daily['temperature_2m_max'] as List;
    final rain = daily['precipitation_probability_max'] as List;
    return VisitWeather(
      description: _description((codes.first as num).toInt()),
      temperatureMax: temps.first as num,
      rainProbability: rain.first as num,
    );
  }

  static String _description(int code) => switch (code) {
    0 => 'Ciel dégagé',
    1 => 'Peu nuageux',
    2 => 'Partiellement nuageux',
    3 => 'Couvert',
    45 || 48 => 'Brouillard',
    51 || 53 || 55 => 'Bruine',
    56 || 57 => 'Bruine verglaçante',
    61 || 63 || 65 => 'Pluie',
    66 || 67 => 'Pluie verglaçante',
    71 || 73 || 75 || 77 => 'Neige',
    80 || 81 || 82 => 'Averses',
    85 || 86 => 'Averses de neige',
    95 => 'Orage',
    96 || 99 => 'Orage avec grêle',
    97 => 'Orage violent',
    _ => 'Conditions météo variables',
  };
}

class VisitWeatherService {
  static const Map<String, (double, double)> _coordinates = {
    'tunis': (36.8065, 10.1815),
    'la marsa': (36.8782, 10.3247),
    'sousse': (35.8256, 10.6369),
    'sfax': (34.7406, 10.7603),
    'monastir': (35.7643, 10.8113),
    'bizerte': (37.2744, 9.8739),
    'nabeul': (36.4513, 10.7357),
    'hammamet': (36.4000, 10.6167),
    'kairouan': (35.6781, 10.0963),
    'gabes': (33.8815, 10.0982),
  };

  Future<VisitWeather?> forecast(String city, DateTime date) async {
    final key = city.trim().toLowerCase();
    final place = _coordinates.entries
        .firstWhere(
          (entry) => key.contains(entry.key),
          orElse: () => _coordinates.entries.first,
        )
        .value;
    final day =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    final uri = Uri.https('api.open-meteo.com', '/v1/forecast', {
      'latitude': '${place.$1}',
      'longitude': '${place.$2}',
      'daily': 'temperature_2m_max,precipitation_probability_max,weather_code',
      'timezone': 'Africa/Tunis',
      'start_date': day,
      'end_date': day,
    });
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client
          .getUrl(uri)
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 12),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode == 400) return null;
      if (response.statusCode != 200) {
        throw HttpException('Météo indisponible (${response.statusCode}).');
      }
      return VisitWeather.fromJson(
        Map<String, dynamic>.from(jsonDecode(body) as Map),
      );
    } finally {
      client.close(force: true);
    }
  }
}
