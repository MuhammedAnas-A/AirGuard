import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'dart:async';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'db_helper.dart';
import 'graph_page.dart';

final FlutterLocalNotificationsPlugin _notificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
  const iosSettings = DarwinInitializationSettings();
  const initSettings = InitializationSettings(
    android: androidSettings,
    iOS: iosSettings,
  );
  await _notificationsPlugin.initialize(initSettings);
}

Future<void> _sendNotification(int id, String title, String body) async {
  const androidDetails = AndroidNotificationDetails(
    'airguard_channel',
    'AirGuard Alerts',
    channelDescription: 'Air quality threshold alerts',
    importance: Importance.high,
    priority: Priority.high,
  );
  const iosDetails = DarwinNotificationDetails();
  const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
  await _notificationsPlugin.show(id, title, body, details);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _initNotifications();
  runApp(const DashboardApp());
}

class DashboardApp extends StatelessWidget {
  const DashboardApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AirGuard Dashboard',
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0A0E14),
        cardColor: const Color(0xFF0F1419),
        useMaterial3: true,
        colorScheme: ColorScheme.dark(
          primary: const Color(0xFF00FFA3),
          secondary: const Color(0xFF00D4FF),
          surface: const Color(0xFF0F1419),
          background: const Color(0xFF0A0E14),
        ),
      ),
      home: const DashboardPage(),
    );
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  final _rand = math.Random();

  // Blynk Configuration
  static const String BLYNK_AUTH = "hqZiF8mq_Sqp_t9FANHIrbDdbmFdWNx_"; //key 2
  // static const String BLYNK_AUTH = "UK_poqP4o6pq98xxPgBJUkQtWk0YWblg";
  static const String BLYNK_URL = "https://blynk.cloud/external/api";

  double _progressFrom = 0.0;
  double _progressTo = 0.45;
  double _aqiFrom = 0.0;
  double _aqiTo = 85.0;

  // Blynk sensor data
  double _co2Level = 0.0;
  double _o2Level = 0.0;
  double _aqi = 85.0;
  Timer? _refreshTimer;
  bool _o2AlertSent = false;
  bool _co2AlertSent = false;
  final DbHelper _db = DbHelper();

  final List<Device> _devices = [
    Device(
      name: 'Buzzer Alert System',
      percent: 100,
      watt: 'Safety Alarm Control',
      isOn: false,
    ),
  ];

  final Set<int> _expanded = {};

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
      lowerBound: 0.0,
      upperBound: 1.0,
      value: 0.78,
    );
    // Load data immediately
    _loadBlynkData();
    // Then refresh every 3 seconds
    _refreshTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (mounted) {
        _loadBlynkData();
      }
    });
  }

  Future<void> _loadBlynkData() async {
    try {
      // Fetch CO2 reading from V1
      print('Fetching CO2 from V1...');
      final co2Response = await http
          .get(Uri.parse('$BLYNK_URL/get?token=$BLYNK_AUTH&V1'))
          .timeout(const Duration(seconds: 5));
      print(
        'CO2 Response Status: ${co2Response.statusCode}, Body: ${co2Response.body}',
      );
      if (co2Response.statusCode == 200 && co2Response.body.isNotEmpty) {
        final co2Value = double.tryParse(co2Response.body);
        if (co2Value != null && mounted) {
          setState(() {
            _co2Level = co2Value;
            print('Updated CO2: $_co2Level');
          });
        }
      }

      // Fetch Oxygen reading from V3 (ADC -> percentage conversion)
      print('Fetching O2 from V3...');
      final o2Response = await http
          .get(Uri.parse('$BLYNK_URL/get?token=$BLYNK_AUTH&V3'))
          .timeout(const Duration(seconds: 5));
      print(
        'O2 Response Status: ${o2Response.statusCode}, Body: ${o2Response.body}',
      );
      if (o2Response.statusCode == 200 && o2Response.body.isNotEmpty) {
        final parsed = double.tryParse(o2Response.body);
        if (parsed != null) {
          double o2Percent;
          // If the device returns an ADC reading (0..1023) it will be > 21
          if (parsed > 21.0) {
            o2Percent = (parsed / 678) * 20.9;
          } else {
            // Already a percentage-like value
            o2Percent = parsed;
          }
          o2Percent = o2Percent.clamp(0.0, 20.9);
          if (mounted) {
            setState(() {
              _o2Level = o2Percent;
              print('Updated O2%: $_o2Level');
            });
          }
        }
      }

      // Calculate AQI based on CO2 levels
      if (mounted) {
        setState(() {
          if (_co2Level <= 400) {
            _aqi = 25.0; // Good
          } else if (_co2Level <= 600) {
            _aqi = 50.0; // Moderate
          } else if (_co2Level <= 1000) {
            _aqi = 100.0; // Unhealthy for Sensitive Groups
          } else {
            _aqi = 150.0; // Unhealthy
          }
          print('Updated AQI: $_aqi');
        });
      }

      // Save reading to database
      await _db.insertReading(_co2Level, _o2Level);

      // Threshold notifications
      if (_o2Level < 15.0 && !_o2AlertSent) {
        _o2AlertSent = true;
        await _sendNotification(
          1,
          '⚠️ Oxygen Low',
          'Oxygen level is ${_o2Level.toStringAsFixed(1)}% — below safe threshold of 15%.',
        );
      } else if (_o2Level >= 15.0) {
        _o2AlertSent = false;
      }

      if (_co2Level > 500 && !_co2AlertSent) {
        _co2AlertSent = true;
        await _sendNotification(
          2,
          '⚠️ CO₂ Level High',
          'CO₂ level is ${_co2Level.toStringAsFixed(0)} ppm — above safe threshold of 600 ppm.',
        );
      } else if (_co2Level <= 600) {
        _co2AlertSent = false;
      }
    } catch (e) {
      print('Error loading Blynk data: $e');
    }
  }

  Future<void> _updateBuzzer(bool isOn) async {
    try {
      final url = Uri.parse(
        '$BLYNK_URL/update?token=$BLYNK_AUTH&V5=${isOn ? 1 : 0}',
      );
      final response = await http.get(url).timeout(const Duration(seconds: 5));
      if (response.statusCode != 200) {
        print('Failed to update buzzer: ${response.statusCode}');
      }
    } catch (e) {
      print('Error updating buzzer: $e');
    }
  }

  @override
  void dispose() {
    _anim.dispose();
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              const Color(0xFF0A0E14),
              const Color(0xFF0D1117),
              const Color(0xFF0A0E14),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 0),
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildTopBar(),
                  const SizedBox(height: 18),
                  _buildGauge(size),
                  const SizedBox(height: 18),
                  _buildSummaryRow(),
                  const SizedBox(height: 14),
                  _buildComparisonCard(),
                  const SizedBox(height: 16),
                  _buildDevicesArea(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  double _mix(double a, double b, double t) => a + (b - a) * t;

  void _randomizeGauge() {
    final newAqi = 50.0 + _rand.nextDouble() * 150.0;
    final newProg = (newAqi / 500.0).clamp(0.08, 0.98);
    setState(() {
      _aqiFrom = _aqiTo;
      _aqiTo = double.parse(newAqi.toStringAsFixed(1));
      _progressFrom = _progressTo;
      _progressTo = newProg;
    });
    HapticFeedback.selectionClick();
    _anim.forward(from: 0);
  }

  Widget _buildTopBar() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FFA3), Color(0xFF00D4FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FFA3).withOpacity(0.3),
                      blurRadius: 10,
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: const CircleAvatar(
                  radius: 18,
                  backgroundColor: Colors.transparent,
                  child: Icon(Icons.person, size: 18, color: Colors.black),
                ),
              ),
              const SizedBox(width: 12),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Text(
                      'AirGuard Monitor',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.5,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Real-time Monitoring',
                      style: TextStyle(fontSize: 12, color: Colors.white54),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Row(
          children: [
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1419),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              // child: const Padding(
              //   padding: EdgeInsets.all(8.0),
              //   child: Icon(Icons.notifications_none, color: Colors.white70),
              // ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: BoxDecoration(
                color: const Color(0xFF0F1419),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white10, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.3),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: IconButton(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InstructionsPage()),
                  );
                },
                icon: const Icon(
                  Icons.menu_book_rounded,
                  color: Colors.white70,
                ),
                tooltip: 'Instructions',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGauge(Size size) {
    // Responsive sizing: favor width, but clamp to sensible range
    final base = math.min(size.width * 0.88, 450.0);
    final gaugeHeight = (base * 0.62).clamp(200.0, 340.0);
    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(28),
          onTap: _randomizeGauge,
          child: Container(
            width: base,
            constraints: BoxConstraints(
              minHeight: gaugeHeight,
              maxHeight: gaugeHeight + 40,
            ),
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF111418).withOpacity(0.95),
                  const Color(0xFF0D1117).withOpacity(0.85),
                  const Color(0xFF0A0E14).withOpacity(0.90),
                ],
                stops: const [0.0, 0.5, 1.0],
              ),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF00FFA3).withOpacity(0.12),
                  blurRadius: 40,
                  spreadRadius: -8,
                  offset: const Offset(0, 12),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.6),
                  blurRadius: 30,
                  spreadRadius: -12,
                  offset: const Offset(0, 15),
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 60,
                  spreadRadius: -5,
                  offset: const Offset(0, 20),
                ),
              ],
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final innerHeight = box.maxHeight;
                final arcArea = innerHeight * 0.62; // arc paint area
                final textScale = (arcArea / 260).clamp(0.72, 1.05);
                return Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      height: arcArea,
                      width: box.maxWidth,
                      child: AnimatedBuilder(
                        animation: _anim,
                        builder: (context, child) {
                          final t = Curves.easeOut.transform(_anim.value);
                          final progress = _mix(_progressFrom, _progressTo, t);
                          final aqi = _aqi;

                          // Determine air quality status and color
                          String quality;
                          Color qualityColor;
                          if (aqi <= 50) {
                            quality = 'Good';
                            qualityColor = const Color(0xFF00FFA3);
                          } else if (aqi <= 100) {
                            quality = 'Moderate';
                            qualityColor = const Color(0xFFFFD700);
                          } else if (aqi <= 150) {
                            quality = 'Unhealthy for Sensitive';
                            qualityColor = const Color(0xFFFF9500);
                          } else {
                            quality = 'Unhealthy';
                            qualityColor = const Color(0xFFFF3B30);
                          }

                          return FittedBox(
                            alignment: Alignment.center,
                            child: SizedBox(
                              width: box.maxWidth,
                              height: arcArea,
                              child: CustomPaint(
                                painter: ArcPainter(
                                  progress: progress,
                                  aqi: aqi,
                                ),
                                child: Center(
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      ShaderMask(
                                        shaderCallback: (bounds) =>
                                            LinearGradient(
                                              colors: [
                                                qualityColor,
                                                qualityColor.withOpacity(0.7),
                                              ],
                                            ).createShader(bounds),
                                        child: Text(
                                          aqi.toStringAsFixed(0),
                                          style: TextStyle(
                                            fontSize: 55 * textScale,
                                            fontWeight: FontWeight.w900,
                                            color: Colors.white,
                                            letterSpacing: 1.2,
                                          ),
                                        ),
                                      ),
                                      SizedBox(height: 4 * textScale),
                                      Text(
                                        quality,
                                        style: TextStyle(
                                          color: qualityColor,
                                          fontSize: 16 * textScale,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                      SizedBox(height: 6 * textScale),
                                      Text(
                                        'Air Quality Index',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13 * textScale,
                                          letterSpacing: 0.5,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.03),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.06),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.calendar_today,
                                size: 15,
                                color: Color(0xFF00FFA3),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                // show current date in DD/MM/YYYY
                                'Today, ${DateTime.now().day.toString().padLeft(2, '0')}/${DateTime.now().month.toString().padLeft(2, '0')}/${DateTime.now().year}',
                                style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.3,
                                ),
                              ),
                            ],
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00FFA3), Color(0xFF00D4FF)],
                              ),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Live',
                              style: TextStyle(
                                color: Colors.black,
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSummaryRow() {
    return Row(
      children: [
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GraphPage(graphType: GraphType.co2),
                ),
              );
            },
            child: _StatCard(
              title: '${_co2Level.toStringAsFixed(0)} ppm',
              subtitle: 'CO₂ Level',
              accent: const Color(0xFFFFD700),
              change: _co2Level <= 500
                  ? 'Good'
                  : _co2Level <= 600
                  ? 'Moderate'
                  : 'High',
              icon: Icons.co2,
              showGraphHint: true,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => const GraphPage(graphType: GraphType.o2),
                ),
              );
            },
            child: _StatCard(
              title: '${_o2Level.toStringAsFixed(1)}%',
              subtitle: 'O₂ Level',
              accent: const Color(0xFF00FFA3),
              change: _o2Level >= 19.5 ? 'Good' : 'Low',
              icon: Icons.air,
              showGraphHint: true,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildComparisonCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F1419).withOpacity(0.8),
            const Color(0xFF0D1117).withOpacity(0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Row(
        children: [
          // vertical bars
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _VerticalStat(
                color: const Color(0xFF00FFA3),
                label: '${_o2Level.toStringAsFixed(1)}% O₂',
                value: (_o2Level / 20.9).clamp(0.0, 1.0),
                hint: 'Oxygen Level',
              ),
              const SizedBox(height: 8),
              _VerticalStat(
                color: const Color(0xFFFF6B6B),
                label: '${_co2Level.toStringAsFixed(0)} ppm',
                value: (_co2Level / 2000.0).clamp(0.0, 1.0),
                hint: 'CO₂ Emissions',
              ),
            ],
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                Text(
                  'Air Quality Status',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.5,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Oxygen vs Carbon emissions',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDevicesArea() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F1419).withOpacity(0.8),
            const Color(0xFF0D1117).withOpacity(0.6),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.05), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 15,
            spreadRadius: -5,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFF00FFA3), Color(0xFF00D4FF)],
                      ),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.devices_other_rounded,
                      color: Colors.black,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Control Systems',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 17,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
              // Row(
              //   children: [
              //     const Text(
              //       'Status',
              //       style: TextStyle(color: Colors.white54, fontSize: 12),
              //     ),
              //     const SizedBox(width: 8),
              //     ChoiceChip(
              //       selected: true,
              //       onSelected: (_) {},
              //       backgroundColor: Colors.white.withOpacity(0.05),
              //       selectedColor: const Color(0xFF00FFA3).withOpacity(0.2),
              //       labelStyle: const TextStyle(
              //         color: Color(0xFF00FFA3),
              //         fontSize: 11,
              //         fontWeight: FontWeight.w600,
              //       ),
              //       side: BorderSide(
              //         color: const Color(0xFF00FFA3).withOpacity(0.3),
              //       ),
              //       label: const Text('All'),
              //     ),
              //     const SizedBox(width: 6),
              //     ChoiceChip(
              //       selected: false,
              //       onSelected: (_) {},
              //       backgroundColor: Colors.white.withOpacity(0.05),
              //       labelStyle: const TextStyle(
              //         color: Colors.white54,
              //         fontSize: 11,
              //       ),
              //       side: const BorderSide(color: Colors.white10),
              //       label: const Text('Active'),
              //     ),
              //   ],
              // ),
            ],
          ),
          const SizedBox(height: 12),
          ...List.generate(_devices.length, (index) {
            final device = _devices[index];
            final isExpanded = _expanded.contains(index);
            return Column(
              children: [
                DeviceCard(
                  device: device,
                  isExpanded: isExpanded,
                  onTap: () {
                    setState(() {
                      if (isExpanded) {
                        _expanded.remove(index);
                      } else {
                        _expanded.add(index);
                      }
                    });
                  },
                  onToggle: (value) {
                    setState(() => device.isOn = value);
                    _updateBuzzer(value);
                    HapticFeedback.lightImpact();
                  },
                  onPercentChange: (value) {
                    setState(() => device.percent = value.round());
                  },
                ),
                if (index != _devices.length - 1) const SizedBox(height: 10),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class ArcPainter extends CustomPainter {
  final double progress; // 0..1
  final double aqi;
  ArcPainter({required this.progress, this.aqi = 0});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.9);
    final radius = math.min(size.width / 2, size.height);

    // Determine color based on AQI
    Color progressColor;
    if (aqi <= 50) {
      progressColor = const Color(0xFF00FFA3);
    } else if (aqi <= 100) {
      progressColor = const Color(0xFFFFD700);
    } else if (aqi <= 150) {
      progressColor = const Color(0xFFFF9500);
    } else {
      progressColor = const Color(0xFFFF3B30);
    }

    final background = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 16
      ..shader = RadialGradient(
        colors: [Colors.white12, Colors.white10],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeCap = StrokeCap.round;

    final prog = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 20
      ..shader = SweepGradient(
        startAngle: -math.pi,
        endAngle: 0,
        colors: [progressColor, progressColor.withOpacity(0.7), progressColor],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..strokeCap = StrokeCap.round;

    // glow paint (soft outer stroke)
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 32
      ..color = progressColor.withOpacity(0.3)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 16)
      ..strokeCap = StrokeCap.round;

    // draw background arc
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi,
      math.pi,
      false,
      background,
    );

    // draw progress arc (glow + core)
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi,
      math.pi * progress,
      false,
      glow,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi,
      math.pi * progress,
      false,
      prog,
    );
  }

  @override
  bool shouldRepaint(covariant ArcPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.aqi != aqi;
}

class _StatCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final String change;
  final IconData? icon;
  final bool showGraphHint;

  const _StatCard({
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.change,
    this.icon,
    this.showGraphHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: const Color(0xFF0B0D0E),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) Icon(icon, color: accent),
              if (icon != null) const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(subtitle, style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(change, style: const TextStyle(color: Colors.white54)),
              if (showGraphHint)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.show_chart,
                      size: 14,
                      color: accent.withOpacity(0.6),
                    ),
                    const SizedBox(width: 3),
                    Text(
                      'Graph',
                      style: TextStyle(
                        color: accent.withOpacity(0.6),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _VerticalStat extends StatelessWidget {
  final Color color;
  final String label;
  final double value; // 0..1 height
  final String hint;

  const _VerticalStat({
    required this.color,
    required this.label,
    required this.value,
    required this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 18,
          height: 70,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: value,
              child: Container(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 4),
            Text(
              hint,
              style: const TextStyle(color: Colors.white54, fontSize: 12),
            ),
          ],
        ),
      ],
    );
  }
}

class DeviceCard extends StatelessWidget {
  final Device device;
  final bool isExpanded;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;
  final ValueChanged<double> onPercentChange;

  const DeviceCard({
    required this.device,
    required this.isExpanded,
    required this.onTap,
    required this.onToggle,
    required this.onPercentChange,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFF0E1112),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Stack(
                  alignment: Alignment.center,
                  children: [
                    SizedBox(
                      width: 56,
                      height: 56,
                      child: CircularProgressIndicator(
                        value: device.percent / 100.0,
                        strokeWidth: 6,
                        backgroundColor: Colors.white10,
                        valueColor: AlwaysStoppedAnimation(
                          device.isOn
                              ? const Color(0xFF00FFA3)
                              : Colors.white30,
                        ),
                      ),
                    ),
                    CircleAvatar(
                      radius: 14,
                      child: Icon(_getDeviceIcon(device.name), size: 18),
                    ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        device.watt,
                        style: const TextStyle(color: Colors.white54),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(height: 2),
                    Switch(
                      value: device.isOn,
                      onChanged: onToggle,
                      activeColor: const Color(0xFF00FFA3),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  IconData _getDeviceIcon(String deviceName) {
    final lower = deviceName.toLowerCase();
    if (lower.contains('fan') || lower.contains('vent')) return Icons.air;
    if (lower.contains('buzzer') || lower.contains('alert')) {
      return Icons.notifications_active;
    }
    if (lower.contains('purifier')) return Icons.wind_power;
    return Icons.sensors;
  }
}

class Device {
  String name;
  int percent;
  String watt;
  bool isOn;

  Device({
    required this.name,
    required this.percent,
    required this.watt,
    this.isOn = true,
  });
}

class InstructionsPage extends StatelessWidget {
  const InstructionsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E14),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F1419),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(
            Icons.arrow_back_ios_new_rounded,
            color: Color(0xFF00FFA3),
          ),
          onPressed: () => Navigator.pop(context),
        ),
        title: ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Color(0xFF00FFA3), Color(0xFF00D4FF)],
          ).createShader(bounds),
          child: const Text(
            'Instructions',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 20,
              letterSpacing: 0.5,
            ),
          ),
        ),
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
        children: const [
          _InstructionStep(
            emoji: '🔧',
            stepNumber: 1,
            title: 'Power On the Device',
            bullets: [
              'Switch on the AirGuard monitoring device.',
              'Ensure the device is properly powered and initialized.',
            ],
          ),
          _InstructionStep(
            emoji: '📶',
            stepNumber: 2,
            title: 'Connect to Device Hotspot',
            bullets: [
              'Open Wi-Fi settings on your mobile or laptop.',
              'Search for the hotspot:',
              '  SSID (Network Name): One',
              '  Password: qwerty123',
              'Connect to the hotspot.',
            ],
          ),
          _InstructionStep(
            emoji: '🌐',
            stepNumber: 3,
            title: 'Access the System',
            bullets: [
              'Once connected, open the APP.',
              'The AirGuard dashboard will open.',
            ],
          ),
          _InstructionStep(
            emoji: '🌫️',
            stepNumber: 4,
            title: 'Start Monitoring',
            bullets: [
              'After connection, the device automatically begins monitoring air quality.',
              'Sensors collect real-time data such as:',
              '  • Air Quality Index (AQI)',
              '  • Gas levels (CO₂, O₂)',
            ],
          ),
          _InstructionStep(
            emoji: '📊',
            stepNumber: 5,
            title: 'View Data',
            bullets: [
              'The collected data is displayed on the dashboard.',
              'Users can:',
              '  • View live readings',
              '  • Analyze air quality levels',
              '  • Check alerts for unsafe conditions',
            ],
          ),
          _InstructionStep(
            emoji: '⚠️',
            stepNumber: 6,
            title: 'Alerts & Notifications',
            bullets: [
              'If air quality becomes poor, the system:',
              '  • Displays warning messages',
              '  • Notifies users for necessary action',
            ],
          ),
          _InstructionStep(
            emoji: '🔌',
            stepNumber: 7,
            title: 'Disconnect / Shutdown',
            bullets: [
              'After usage, disconnect from the hotspot.',
              'Turn off the device if not in use.',
            ],
          ),
          SizedBox(height: 20),
          _AlertInfoCard(),
        ],
      ),
    );
  }
}

class _InstructionStep extends StatelessWidget {
  final String emoji;
  final int stepNumber;
  final String title;
  final List<String> bullets;

  const _InstructionStep({
    required this.emoji,
    required this.stepNumber,
    required this.title,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF0F1419).withOpacity(0.9),
            const Color(0xFF0D1117).withOpacity(0.7),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.07), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 10,
            spreadRadius: -4,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF00FFA3), Color(0xFF00D4FF)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Step $stepNumber',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(emoji, style: const TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    color: Colors.white,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...bullets.map(
            (b) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Text(
                b,
                style: const TextStyle(
                  color: Colors.white70,
                  fontSize: 13.5,
                  height: 1.5,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AlertInfoCard extends StatelessWidget {
  const _AlertInfoCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            const Color(0xFFFF6B35).withOpacity(0.15),
            const Color(0xFFFF3B30).withOpacity(0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF6B35).withOpacity(0.35),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          Row(
            children: [
              Icon(
                Icons.notifications_active_rounded,
                color: Color(0xFFFF9500),
                size: 20,
              ),
              SizedBox(width: 8),
              Text(
                'Automatic Alert Thresholds',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: Color(0xFFFF9500),
                ),
              ),
            ],
          ),
          SizedBox(height: 12),
          Text(
            '🔴  O₂ below 15% → "Oxygen level is low" notification',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
          ),
          Text(
            '🔴  CO₂ above 600 ppm → "CO₂ level is high" notification',
            style: TextStyle(color: Colors.white70, fontSize: 13, height: 1.6),
          ),
        ],
      ),
    );
  }
}
