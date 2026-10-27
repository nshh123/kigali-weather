import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'weather.dart';

void main() {
  runApp(const WeatherApp());
}

// ============================================================================
// BULLETPROOF STORAGE SERVICE (SharedPreferences + In-Memory Fallback)
// ============================================================================
class StorageService {
  static final Map<String, String> _memory = {};

  static Future<void> setString(String key, String value) async {
    _memory[key] = value;
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(milliseconds: 1200));
      await prefs.setString(key, value);
    } catch (_) {}
  }

  static Future<String?> getString(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance()
          .timeout(const Duration(milliseconds: 1200));
      final val = prefs.getString(key);
      if (val != null) return val;
    } catch (_) {}
    return _memory[key];
  }
}

// ============================================================================
// MAIN APP WIDGET
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
          seedColor: const Color(0xFF0468D7),
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
// WEATHER SCREEN (STATEFUL)
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

  // Toggle button in AppBar to easily simulate and capture offline screenshots
  bool simulateOffline = false;

  @override
  void initState() {
    super.initState();
    initAndLoad();
  }

  Future<void> initAndLoad() async {
    try {
      final savedCityName = await StorageService.getString('city');
      if (savedCityName != null) {
        final matching = cities.where((c) => c.name == savedCityName);
        if (matching.isNotEmpty) {
          city = matching.first;
        }
      }
    } catch (_) {}
    await load();
  }

  Future<void> load() async {
    if (!mounted) return;
    setState(() {
      loading = true;
      error = null;
    });

    try {
      if (simulateOffline) {
        throw Exception('Simulated offline mode: Network disconnected');
      }

      final result = await fetchWeather(city);

      await StorageService.setString(
        'weather_${city.name}',
        jsonEncode(result.toJson()),
      );

      if (!mounted) return;
      setState(() {
        weather = result;
        loading = false;
        error = null;
        offline = false;
      });
    } catch (e) {
      Weather? cachedWeather;
      try {
        final cachedJson = await StorageService.getString('weather_${city.name}');
        if (cachedJson != null) {
          final cachedMap = jsonDecode(cachedJson) as Map<String, dynamic>;
          cachedWeather = Weather.fromJson(cachedMap);
        }
      } catch (_) {}

      if (!mounted) return;

      if (cachedWeather != null) {
        setState(() {
          weather = cachedWeather;
          loading = false;
          error = null;
          offline = true;
        });
      } else {
        setState(() {
          weather = null;
          loading = false;
          offline = false;
          error = 'Could not load the weather. Check your internet connection.';
        });
      }
    }
  }

  Future<void> changeCity(City newCity) async {
    setState(() {
      city = newCity;
      loading = true;
      error = null;
      offline = false;
    });

    await StorageService.setString('city', newCity.name);
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
// WEATHER CARD WIDGET
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0x2EFFFFFF),
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
