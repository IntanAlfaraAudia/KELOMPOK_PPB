import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

enum ThemeOption { light, dark, autoTime }


final ValueNotifier<ThemeOption> themeNotifier = ValueNotifier(ThemeOption.autoTime);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initializeDateFormatting('id_ID', null);
  runApp(const CuacaKampusApp());
}

class CuacaKampusApp extends StatelessWidget {
  const CuacaKampusApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeOption>(
      valueListenable: themeNotifier,
      builder: (context, theme, _) {

        ThemeMode currentThemeMode;
        if (theme == ThemeOption.light) {
          currentThemeMode = ThemeMode.light;
        } else if (theme == ThemeOption.dark) {
          currentThemeMode = ThemeMode.dark;
        } else {
          int hour = DateTime.now().hour;
          currentThemeMode = (hour >= 6 && hour < 18) ? ThemeMode.light : ThemeMode.dark;
        }

        return MaterialApp(
          debugShowCheckedModeBanner: false,
          title: 'Cuaca Kampus',
          theme: ThemeData.light(useMaterial3: true),
          darkTheme: ThemeData.dark(useMaterial3: true),
          themeMode: currentThemeMode, // Terapkan tema ke aplikasi
          home: const BerandaCuaca(),
        );
      },
    );
  }
}

class BerandaCuaca extends StatefulWidget {
  const BerandaCuaca({super.key});

  @override
  State<BerandaCuaca> createState() => _BerandaCuacaState();
}

class _BerandaCuacaState extends State<BerandaCuaca> {
  final List<Map<String, dynamic>> listKota = [
    {'nama': 'Jakarta', 'lat': -6.2088, 'lon': 106.8456},
    {'nama': 'Bandung', 'lat': -6.9175, 'lon': 107.6191},
    {'nama': 'Yogyakarta', 'lat': -7.7956, 'lon': 110.3695},
    {'nama': 'Semarang', 'lat': -6.9932, 'lon': 110.4203},
    {'nama': 'Surabaya', 'lat': -7.2504, 'lon': 112.7688},
    {'nama': 'Denpasar', 'lat': -8.6500, 'lon': 115.2167},
    {'nama': 'Balikpapan', 'lat': -1.2379, 'lon': 116.8529},
    {'nama': 'Samarinda', 'lat': -0.5022, 'lon': 117.1536},
    {'nama': 'Makassar', 'lat': -5.1476, 'lon': 119.4327},
    {'nama': 'Manado', 'lat': 1.4931, 'lon': 124.8413},
    {'nama': 'Medan', 'lat': 3.5952, 'lon': 98.6722},
    {'nama': 'Palembang', 'lat': -2.9909, 'lon': 104.7566},
    {'nama': 'Padang', 'lat': -0.9471, 'lon': 100.4172},
    {'nama': 'Jayapura', 'lat': -2.5337, 'lon': 140.7181},
  ];

  Map<String, dynamic> currentCity = {'nama': 'Mencari Lokasi...', 'lat': 0.0, 'lon': 0.0};
  bool isLoading = true;
  bool isError = false;
  String errorMessage = '';
  Map<String, dynamic>? weatherData;
  DateTime lastUpdated = DateTime.now();

  @override
  void initState() {
    super.initState();
    _initLocationAndWeather();
  }

  Future<void> _initLocationAndWeather() async {
    setState(() {
      isLoading = true;
      isError = false;
      currentCity = {'nama': 'Mencari Lokasi...', 'lat': 0.0, 'lon': 0.0};
    });

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) throw Exception('GPS tidak aktif');

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          throw Exception('Izin lokasi ditolak');
        }
      }
      if (permission == LocationPermission.deniedForever) {
        throw Exception('Izin lokasi ditolak permanen');
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      String namaKota = 'Lokasi Anda';
      try {
        final placemarks =
            await placemarkFromCoordinates(position.latitude, position.longitude);
        if (placemarks.isNotEmpty) {
          final p = placemarks.first;
          final locality = p.locality;
          final subArea = p.subAdministrativeArea;
          if (locality != null && locality.isNotEmpty) {
            namaKota = locality;
          } else if (subArea != null && subArea.isNotEmpty) {
            namaKota = subArea;
          }
        }
      } catch (_) {
        // Reverse geocoding gagal -> tetap pakai nama default.
      }

      if (!mounted) return;
      setState(() {
        currentCity = {
          'nama': namaKota,
          'lat': position.latitude,
          'lon': position.longitude,
        };
      });
    } catch (e) {
      // Lokasi tidak tersedia -> pakai kota default (salinan, jangan ubah listKota).
      if (!mounted) return;
      setState(() {
        currentCity = Map<String, dynamic>.from(listKota[0]);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lokasi tidak tersedia, menampilkan cuaca Jakarta.'),
        ),
      );
    }

    await fetchWeatherData();
  }

  Future<void> fetchWeatherData() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      isError = false;
    });

    final lat = currentCity['lat'];
    final lon = currentCity['lon'];

    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$lat&longitude=$lon'
        '&current=temperature_2m,apparent_temperature,is_day,relative_humidity_2m,wind_speed_10m,weather_code'
        '&daily=weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max'
        '&timezone=auto');

    try {
      final response = await http.get(url).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        throw Exception('Gagal mengambil data (${response.statusCode})');
      }
      final data = json.decode(response.body) as Map<String, dynamic>;
      if (data['current'] == null || data['daily'] == null) {
        throw Exception('Format data tidak valid');
      }
      if (!mounted) return;
      setState(() {
        weatherData = data;
        lastUpdated = DateTime.now();
        isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        isError = true;
        isLoading = false;
        errorMessage = 'Tidak dapat terhubung.\nPeriksa koneksi internet Anda.';
      });
    }
  }

  void _showCityMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('Pilih Lokasi', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            ListTile(
              leading: Icon(Icons.my_location, color: Theme.of(context).colorScheme.primary),
              title: Text('Gunakan Lokasi Saat Ini (GPS)', style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.bold)),
              onTap: () {
                Navigator.pop(context);
                _initLocationAndWeather();
              },
            ),
            const Divider(),
            Expanded(
              child: ListView.builder(
                itemCount: listKota.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    leading: const Icon(Icons.location_city),
                    title: Text(listKota[index]['nama'].toString()),
                    onTap: () {
                      setState(() {
                        currentCity = Map<String, dynamic>.from(listKota[index]);
                      });
                      Navigator.pop(context);
                      fetchWeatherData();
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Map<String, dynamic> getWeatherDesc(int code) {
    if (code == 0) return {'text': 'Cerah', 'icon': Icons.wb_sunny};
    if (code == 1 || code == 2) return {'text': 'Cerah Berawan', 'icon': Icons.wb_cloudy};
    if (code == 3) return {'text': 'Berawan', 'icon': Icons.cloud};
    if (code == 45 || code == 48) return {'text': 'Berkabut', 'icon': Icons.foggy};
    if (code >= 51 && code <= 57) return {'text': 'Gerimis', 'icon': Icons.grain};
    if (code >= 61 && code <= 67) return {'text': 'Hujan', 'icon': Icons.water_drop};
    if (code >= 71 && code <= 77) return {'text': 'Salju', 'icon': Icons.ac_unit};
    if (code >= 80 && code <= 82) return {'text': 'Hujan Lebat', 'icon': Icons.umbrella};
    if (code == 85 || code == 86) return {'text': 'Hujan Salju', 'icon': Icons.ac_unit};
    if (code >= 95 && code <= 99) return {'text': 'Badai Petir', 'icon': Icons.thunderstorm};
    return {'text': 'Tidak diketahui', 'icon': Icons.help_outline};
  }

  LinearGradient getBackgroundGradient(ThemeOption theme) {
    bool isDayTheme;

    if (theme == ThemeOption.light) {
      isDayTheme = true;
    } else if (theme == ThemeOption.dark) {
      isDayTheme = false;
    } else {
      int hour = DateTime.now().hour;
      isDayTheme = (hour >= 6 && hour < 18);
    }

    if (!isDayTheme) {
      return const LinearGradient(colors: [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)], begin: Alignment.topCenter, end: Alignment.bottomCenter);
    } else {
      if (weatherData != null && ((weatherData!['current']['weather_code'] ?? 0) as num) > 3) {
        return const LinearGradient(colors: [Color(0xFF606c88), Color(0xFF3f4c6b)], begin: Alignment.topCenter, end: Alignment.bottomCenter);
      }
      return const LinearGradient(colors: [Color(0xFF2980B9), Color(0xFF6DD5FA)], begin: Alignment.topCenter, end: Alignment.bottomCenter);
    }
  }

  Widget glassCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: padding ?? const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
          ),
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeOption>(
        valueListenable: themeNotifier,
        builder: (context, theme, _) {
          return Scaffold(
            extendBodyBehindAppBar: true,
            appBar: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              title: const Text('Cuaca Kampus', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
              centerTitle: true,
              actions: [
                // TOMBOL TEMA BARU
                PopupMenuButton<ThemeOption>(
                  icon: const Icon(Icons.brightness_6, color: Colors.white),
                  tooltip: 'Pilih Tema',
                  onSelected: (ThemeOption result) {
                    themeNotifier.value = result;
                  },
                  itemBuilder: (BuildContext context) => <PopupMenuEntry<ThemeOption>>[
                    const PopupMenuItem<ThemeOption>(
                      value: ThemeOption.light,
                      child: ListTile(leading: Icon(Icons.light_mode), title: Text('Terang'), contentPadding: EdgeInsets.zero),
                    ),
                    const PopupMenuItem<ThemeOption>(
                      value: ThemeOption.dark,
                      child: ListTile(leading: Icon(Icons.dark_mode), title: Text('Gelap'), contentPadding: EdgeInsets.zero),
                    ),
                    const PopupMenuItem<ThemeOption>(
                      value: ThemeOption.autoTime,
                      child: ListTile(leading: Icon(Icons.access_time), title: Text('Otomatis (Jam)'), contentPadding: EdgeInsets.zero),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.menu, color: Colors.white),
                  tooltip: 'Pilih Kota',
                  onPressed: () => _showCityMenu(context),
                )
              ],
            ),
            body: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 800),
                  decoration: BoxDecoration(gradient: getBackgroundGradient(theme)),
                ),
                SafeArea(
                  child: isError
                      ? buildErrorState()
                      : isLoading
                      ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text('Mencari Lokasi & Cuaca...', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  )
                      : RefreshIndicator(
                    color: Colors.blue,
                    onRefresh: fetchWeatherData,
                    child: ListView(
                      padding: const EdgeInsets.all(16),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        buildCurrentWeatherCard(),
                        const SizedBox(height: 24),
                        const Text('Prakiraan 7 Hari', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                        const SizedBox(height: 16),
                        glassCard(padding: const EdgeInsets.symmetric(vertical: 8), child: buildForecastList()),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }
    );
  }

  Widget buildCurrentWeatherCard() {
    final current = weatherData!['current'];
    final weatherInfo = getWeatherDesc((current['weather_code'] ?? -1) as int);

    return glassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _showCityMenu(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.location_on, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    currentCity['nama'].toString(),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w400, color: Colors.white),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 4),
                const Icon(Icons.keyboard_arrow_down, color: Colors.white, size: 24),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Text(
            '${current['temperature_2m'].round()}°',
            style: const TextStyle(fontSize: 80, fontWeight: FontWeight.w200, color: Colors.white, height: 1.0),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(weatherInfo['icon'], color: Colors.white, size: 28),
              const SizedBox(width: 8),
              Text(weatherInfo['text'].toString(), style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w500, color: Colors.white)),
            ],
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildExtraInfo(Icons.thermostat, 'Terasa\n${current['apparent_temperature'].round()}°C'),
              _buildExtraInfo(Icons.water_drop_outlined, 'Lembap\n${current['relative_humidity_2m']}%'),
              _buildExtraInfo(Icons.air, 'Angin\n${current['wind_speed_10m']} km/j'),
            ],
          ),
          const SizedBox(height: 16),
          Text('Diperbarui pukul ${DateFormat('HH:mm').format(lastUpdated)}', style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildExtraInfo(IconData icon, String text) {
    return Column(
      children: [
        Icon(icon, color: Colors.white70, size: 24),
        const SizedBox(height: 8),
        Text(text, textAlign: TextAlign.center, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ],
    );
  }

  Widget buildForecastList() {
    final daily = weatherData!['daily'];
    return Column(
      children: List.generate((daily['time'] as List).length.clamp(0, 7), (index) {
        final weatherInfo = getWeatherDesc((daily['weather_code'][index] ?? -1) as int);
        final maxTemp = daily['temperature_2m_max'][index].round();
        final minTemp = daily['temperature_2m_min'][index].round();
        final rainProb = ((daily['precipitation_probability_max'][index]) ?? 0) as num;

        String dayName;
        if (index == 0) {
          dayName = 'Hari ini';
        } else if (index == 1) {
          dayName = 'Besok';
        } else {
          DateTime date = DateTime.parse(daily['time'][index].toString());
          dayName = DateFormat('EEEE', 'id_ID').format(date);
        }

        return ListTile(
          leading: Icon(weatherInfo['icon'], color: Colors.white),
          title: Text(dayName, style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white)),
          subtitle: Text(rainProb > 0 ? 'Peluang hujan ${rainProb.round()}%' : weatherInfo['text'].toString(), style: const TextStyle(color: Colors.white70)),
          trailing: Text('$maxTemp° / $minTemp°', style: const TextStyle(fontSize: 16, color: Colors.white, fontWeight: FontWeight.bold)),
        );
      }),
    );
  }

  Widget buildErrorState() {
    return Center(
      child: glassCard(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off, size: 80, color: Colors.white),
            const SizedBox(height: 16),
            Text(errorMessage, textAlign: TextAlign.center, style: const TextStyle(fontSize: 16, color: Colors.white)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _initLocationAndWeather,
              icon: const Icon(Icons.refresh),
              label: const Text('Coba lagi'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.blue.shade900,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}