import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  runApp(const WeatherApp());
}

// ============================================================================
// 1. MODELS & DATA
// ============================================================================
class City {
  const City(this.name, this.latitude, this.longitude);

  final String name;
  final double latitude;
  final double longitude;
}

const List<City> cities = [
  City('Kigali', -1.9441, 30.0619),
  City('Huye', -2.5967, 29.7394),
  City('Musanze', -1.4998, 29.6344),
  City('Rubavu', -1.6792, 29.2585),
];

class Weather {
  Weather({
    required this.temperature,
    required this.humidity,
    required this.wind,
    required this.code,
    required this.time,
  });

  final double temperature;
  final int humidity;
  final double wind;
  final int code;
  final String time;

  factory Weather.fromJson(Map<String, dynamic> json) {
    return Weather(
      temperature: (json['temperature_2m'] as num).toDouble(),
      humidity: (json['relative_humidity_2m'] as num).toInt(),
      wind: (json['wind_speed_10m'] as num).toDouble(),
      code: (json['weather_code'] as num).toInt(),
      time: (json['time'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'temperature_2m': temperature,
      'relative_humidity_2m': humidity,
      'wind_speed_10m': wind,
      'weather_code': code,
      'time': time,
    };
  }
}

// ============================================================================
// 2. HELPER FUNCTIONS
// ============================================================================
String describe(int code) {
  if (code == 0) return 'Clear sky';
  if (code <= 2) return 'Partly cloudy';
  if (code == 3) return 'Cloudy';
  if (code == 45 || code == 48) return 'Fog';
  if (code >= 51 && code <= 57) return 'Drizzle';
  if (code >= 61 && code <= 67) return 'Rain';
  if (code >= 80 && code <= 82) return 'Rain showers';
  if (code >= 95) return 'Thunderstorm';
  return 'Unknown';
}

IconData iconFor(int code) {
  if (code == 0) return Icons.wb_sunny;
  if (code <= 3) return Icons.cloud;
  if (code == 45 || code == 48) return Icons.foggy;
  if (code >= 95) return Icons.thunderstorm;
  if (code >= 51) return Icons.water_drop;
  return Icons.help_outline;
}

Future<Weather> fetchWeather(City city) async {
  final url = Uri.parse(
    'https://api.open-meteo.com/v1/forecast'
    '?latitude=${city.latitude}&longitude=${city.longitude}'
    '&current=temperature_2m,relative_humidity_2m,wind_speed_10m,weather_code'
    '&timezone=Africa%2FKigali',
  );

  final response = await http.get(url);
  if (response.statusCode != 200) {
    throw Exception('The weather server answered ${response.statusCode}');
  }

  final data = jsonDecode(response.body) as Map<String, dynamic>;
  return Weather.fromJson(data['current'] as Map<String, dynamic>);
}

// ============================================================================
// 3. MAIN APP WIDGET
// ============================================================================
class WeatherApp extends StatelessWidget {
  const WeatherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Kigali Weather',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0468D7), // Kigali blue
          primary: const Color(0xFF0468D7),
          surface: Colors.grey[50],
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFF0468D7),
          foregroundColor: Colors.white,
          elevation: 0,
        ),
      ),
      home: const WeatherScreen(),
    );
  }
}

// ============================================================================
// 4. WEATHER SCREEN (STATEFUL)
// ============================================================================
class WeatherScreen extends StatefulWidget {
  const WeatherScreen({super.key});

  @override
  State<WeatherScreen> createState() => _WeatherScreenState();
}

class _WeatherScreenState extends State<WeatherScreen> {
  City city = cities.first;
  Weather? weather;
  bool loading = true;
  String? error;
  bool offline = false;

  // Toggle button in AppBar to easily simulate and capture offline screenshots in DartPad
  bool simulateOffline = false;

  @override
  void initState() {
    super.initState();
    start();
  }

  /// Startup: loads the saved city name first, then fetches weather
  Future<void> start() async {
    final prefs = await SharedPreferences.getInstance();
    final savedCityName = prefs.getString('city');
    if (savedCityName != null) {
      final matching = cities.where((c) => c.name == savedCityName);
      if (matching.isNotEmpty) {
        city = matching.first;
      }
    }
    await load();
  }

  /// Loads weather: fetches from API, saves to cache, or falls back to cache on failure
  Future<void> load() async {
    setState(() {
      loading = true;
      error = null;
    });

    try {
      if (simulateOffline) {
        throw Exception('Simulated offline mode: Network disconnected');
      }

      final result = await fetchWeather(city);

      // Save fresh weather into cache
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('weather_${city.name}', jsonEncode(result.toJson()));

      if (!mounted) return;
      setState(() {
        weather = result;
        loading = false;
        error = null;
        offline = false;
      });
    } catch (e) {
      // Offline fallback: check if we have cached weather for this city
      final prefs = await SharedPreferences.getInstance();
      final cachedJson = prefs.getString('weather_${city.name}');

      if (!mounted) return;

      if (cachedJson != null) {
        try {
          final cachedMap = jsonDecode(cachedJson) as Map<String, dynamic>;
          final cachedWeather = Weather.fromJson(cachedMap);
          setState(() {
            weather = cachedWeather;
            loading = false;
            error = null;
            offline = true;
          });
          return;
        } catch (_) {}
      }

      // No cached data available for this city: show error screen
      setState(() {
        weather = null;
        loading = false;
        offline = false;
        error = 'Could not load the weather. Check your internet connection.';
      });
    }
  }

  Future<void> changeCity(City newCity) async {
    setState(() {
      city = newCity;
      loading = true;
      error = null;
      offline = false;
    });

    // Save selected city name
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('city', newCity.name);

    await load();
  }

  void retry() {
    load();
  }

  String formatTime(String rawTime) {
    if (rawTime.length >= 16) {
      return rawTime.substring(11, 16);
    }
    return rawTime.isNotEmpty ? rawTime : '--:--';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          '${city.name} Weather',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          // Quick toggle for testing and capturing offline screenshots in DartPad
          IconButton(
            tooltip: simulateOffline ? 'Simulate Online' : 'Simulate Offline',
            icon: Icon(simulateOffline ? Icons.wifi_off : Icons.wifi),
            onPressed: () {
              setState(() {
                simulateOffline = !simulateOffline;
              });
              load();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // City ChoiceChips Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: cities.map((c) {
                  final isSelected = c.name == city.name;
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(c.name),
                      selected: isSelected,
                      selectedColor: const Color(0xFF0468D7),
                      labelStyle: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                      onSelected: (selected) {
                        if (selected && c.name != city.name) {
                          changeCity(c);
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),

          // Offline cached warning banner
          if (offline && weather != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF9EC),
                border: Border.all(color: const Color(0xFFF5E3B8)),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: Color(0xFFB07D1A), size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Offline: showing the weather saved at ${formatTime(weather!.time)}',
                      style: const TextStyle(
                        color: Color(0xFFB07D1A),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const Divider(height: 1),

          // Main Content: Loading, Error, or Weather Card
          Expanded(
            child: loading
                ? const Center(child: CircularProgressIndicator())
                : error != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.wifi_off, size: 56, color: Colors.grey),
                              const SizedBox(height: 16),
                              Text(
                                error!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontSize: 15, color: Colors.black87),
                              ),
                              const SizedBox(height: 16),
                              FilledButton(
                                onPressed: retry,
                                child: const Text('Retry'),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: load,
                        child: ListView(
                          padding: const EdgeInsets.all(16),
                          children: [
                            WeatherCard(
                              weather: weather!,
                              cityName: city.name,
                              formattedTime: formatTime(weather!.time),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// 5. WEATHER CARD WIDGET
// ============================================================================
class WeatherCard extends StatelessWidget {
  const WeatherCard({
    super.key,
    required this.weather,
    required this.cityName,
    required this.formattedTime,
  });

  final Weather weather;
  final String cityName;
  final String formattedTime;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: const LinearGradient(
            colors: [Color(0xFF0468D7), Color(0xFF54C5F8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            // Top Row: City & Sky Condition Icon
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cityName,
                      style: const TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      describe(weather.code),
                      style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white70,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                Icon(
                  iconFor(weather.code),
                  size: 54,
                  color: Colors.white,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Big Temperature Text
            Text(
              '${weather.temperature.round()}°C',
              style: const TextStyle(
                fontSize: 64,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 20),

            // Details Container: Humidity & Wind
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.water_drop, color: Colors.white, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Humidity: ${weather.humidity}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 20, color: Colors.white30),
                  Row(
                    children: [
                      const Icon(Icons.air, color: Colors.white, size: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Wind: ${weather.wind} km/h',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Timestamp
            Text(
              'Updated at $formattedTime',
              style: const TextStyle(fontSize: 12, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
