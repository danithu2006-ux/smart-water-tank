import 'package:flutter/material.dart';
import 'package:percent_indicator/circular_percent_indicator.dart';
import 'package:provider/provider.dart';
import 'services/firebase_service.dart';
import 'widgets/app_colors.dart';
import 'widgets/ui_components.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

// HomePage uses Statefulness to handle animations.
// SingleTickerProviderStateMixin gives this class access to a Ticker, which triggers
// animation frames (essential for smooth animations).
class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // Controller to drive the speed, duration, and behavior of the water wave animation
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    // Initialize the AnimationController to repeat every 2 seconds
    _waveController = AnimationController(
      vsync: this, // TickerProvider to sync animation with screen refresh rates
      duration: const Duration(seconds: 2),
    )..repeat(); // Keep the wave animation repeating indefinitely
  }

  // Dispose the controller when the screen is destroyed to prevent memory leaks
  @override
  void dispose() {
    _waveController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Obtain the instance of FirebaseService to get the status streams
    final firebase = Provider.of<FirebaseService>(context);

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        // CustomScrollView allows mixing scrollable elements like lists, grids, and boxes in a single view
        slivers: [
          SliverToBoxAdapter(
            child: Container(
              height: 450,
              decoration: const BoxDecoration(
                gradient: AppColors.deepWaterGradient,
                borderRadius: BorderRadius.vertical(
                  bottom: Radius.circular(50),
                ),
              ),
              child: SafeArea(
                child: StreamBuilder<Map<String, dynamic>>(
                  stream: firebase.tankStatusStream,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const CircularProgressIndicator(
                              color: Colors.white,
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              'Connecting to Tank...',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (snapshot.hasError) {
                      debugPrint('STREAM ERROR: ${snapshot.error}');
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.red,
                                size: 48,
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'Connection Error\n${snapshot.error}',
                                style: const TextStyle(color: Colors.white70),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    }

                    final data = snapshot.data ?? {};
                    final double level =
                        (data['current_level_liters'] ?? 0.0).toDouble();
                    // Tank Capacity = 10 Liters (10,000 ml)
                    // Percentage = (liveLevel / 10) * 100 clamped 0-100%
                    final double percent = (level / 10.0).clamp(0.0, 1.0);
                    // Display Value (ml) = liveLevel * 1000 / 10
                    final double displayMl = level * 1000.0 / 10.0;

                    return SingleChildScrollView(
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 10,
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: const [
                                    Text(
                                      'Smart Tank',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 24,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'Live Monitoring',
                                      style: TextStyle(
                                        color: Colors.white70,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                                IconButton(
                                  onPressed: () => firebase.signOut(),
                                  icon: const Icon(
                                    Icons.logout,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 30),

                          // Circular indicator widget representing the water tank status
                          CircularPercentIndicator(
                            radius: 120,
                            lineWidth: 15,
                            percent: percent,
                            animation: true,
                            animateFromLastPercent: true,
                            circularStrokeCap: CircularStrokeCap.round,
                            progressColor: AppColors.cyan,
                            backgroundColor: Colors.white12,
                            center: Stack(
                              alignment: Alignment.center,
                              children: [
                                // AnimatedBuilder rebuilds only the wave widget on every animation tick
                                AnimatedBuilder(
                                  animation: _waveController,
                                  builder: (context, child) {
                                    return ClipOval(
                                      child: CustomPaint(
                                        size: const Size(200, 200),
                                        // WaterWavePainter paints a custom sin-wave on the canvas to represent water level
                                        painter: WaterWavePainter(
                                          animationValue: _waveController.value,
                                          color: AppColors.cyan.withOpacity(
                                            0.4,
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      '${(percent * 100).toInt()}%',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 42,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      '${displayMl.toStringAsFixed(1)} ml',
                                      style: const TextStyle(
                                        color: Colors.white70,
                                        fontSize: 18,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 40),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              _StatusIndicator(
                                label: 'Filling',
                                isActive: data['is_filling'] ?? false,
                                activeColor: Colors.greenAccent,
                              ),
                              const SizedBox(width: 40),
                              _StatusIndicator(
                                label: 'Usage',
                                isActive: data['is_wasting'] ?? false,
                                activeColor: Colors.orangeAccent,
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ),

          // SliverPadding adds padding around sliver widgets inside CustomScrollView
          SliverPadding(
            padding: const EdgeInsets.all(24),
            sliver: SliverToBoxAdapter(
              child: StreamBuilder<Map<String, dynamic>>(
                stream: firebase.tankStatusStream,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: const Text(
                        'Unable to load controls. Check Firebase rules and authentication.',
                        style: TextStyle(color: AppColors.deepBlue),
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final data =
                      snapshot.data ??
                      {'filling_valve': false, 'outgoing_valve': false};

                  return SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Sensor Readings',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.deepBlue,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _InfoCard(
                          title: 'Intake Flow',
                          value:
                              '${(data['intakeFlow'] ?? 0.0).toStringAsFixed(1)} L/min',
                          icon: Icons.speed,
                        ),

                        const SizedBox(height: 32),

                        const Text(
                          'Quick Controls',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.deepBlue,
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Switch control card for the Inlet Valve (water pump)
                        _ControlCard(
                          title: 'Inlet Valve',
                          subtitle: 'Pumping water to tank',
                          icon: Icons.water_drop,
                          value: data['filling_valve'] ?? false,
                          onChanged: (val) async {
                            try {
                              await firebase.toggleValve('filling_valve', val);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          },
                        ),

                        const SizedBox(height: 16),

                        // Switch control card for the Outlet Valve (water distribution)
                        _ControlCard(
                          title: 'Outlet Valve',
                          subtitle: 'Water usage control',
                          icon: Icons.outbox,
                          value: data['outgoing_valve'] ?? false,
                          onChanged: (val) async {
                            try {
                              await firebase.toggleValve('outgoing_valve', val);
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(content: Text(e.toString())),
                                );
                              }
                            }
                          },
                        ),

                        const SizedBox(
                          height: 100,
                        ), // bottom spacing so items aren't cut off by the navigation bar
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Helper widget to display a small circular status light (e.g. indicating active filling/wasting)
class _StatusIndicator extends StatelessWidget {
  final String label;
  final bool isActive;
  final Color activeColor;

  const _StatusIndicator({
    required this.label,
    required this.isActive,
    required this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // Glowing color if active, gray if inactive
            color: isActive ? activeColor : Colors.white24,
            boxShadow: isActive
                ? [
                    BoxShadow(
                      color: activeColor.withOpacity(0.4),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }
}

/// Custom card widget with a title, icon, and switch toggling values in the database
class _ControlCard extends StatefulWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ControlCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.value,
    required this.onChanged,
  });

  @override
  State<_ControlCard> createState() => _ControlCardState();
}

class _ControlCardState extends State<_ControlCard> {
  late bool _localValue;

  @override
  void initState() {
    super.initState();
    _localValue = widget.value;
  }

  @override
  void didUpdateWidget(_ControlCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Sync local state with external data when stream updates
    if (oldWidget.value != widget.value) {
      _localValue = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: AppColors.background,
            child: Icon(widget.icon, color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                Text(
                  widget.subtitle,
                  style: const TextStyle(color: Colors.grey, fontSize: 12),
                ),
              ],
            ),
          ),
          Switch(
            value: _localValue,
            onChanged: (val) {
              setState(() => _localValue = val);
              widget.onChanged(val);
            },
            activeColor: AppColors.primaryBlue,
            inactiveTrackColor: Colors.grey.shade200,
          ),
        ],
      ),
    );
  }
}

/// A simple card to display a piece of information (e.g., sensor reading)
class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primaryBlue),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 16,
              color: AppColors.deepBlue,
            ),
          ),
        ],
      ),
    );
  }
}
