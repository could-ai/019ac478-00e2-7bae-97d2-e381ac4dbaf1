import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'dart:math';

// ===============================
// GAME CONSTANTS & CONFIG
// ===============================
const double kRoadWidth = 300.0;
const double kLaneWidth = 100.0;
const double kBusWidth = 40.0;
const double kBusHeight = 80.0;
const double kTrafficWidth = 35.0;
const double kTrafficHeight = 70.0;

// Unity values scaled for 2D top-down view
// 1 unit in Unity ~= 10 pixels in Flutter for visualization
const double kScale = 10.0; 

class BusGameScreen extends StatefulWidget {
  const BusGameScreen({super.key});

  @override
  State<BusGameScreen> createState() => _BusGameScreenState();
}

class _BusGameScreenState extends State<BusGameScreen> with TickerProviderStateMixin {
  // ===============================
  // GAME STATE
  // ===============================
  late Ticker _ticker;
  
  // Bus Physics State
  Offset _busPosition = const Offset(0, 0);
  double _busRotation = 0; // Radians, 0 is up (negative Y)
  double _busSpeed = 0; // Current speed in units/sec
  
  // Inputs
  bool _inputGas = false;
  bool _inputBrake = false;
  double _inputSteer = 0; // -1 to 1

  // Game Data (GameManager)
  double _money = 0;
  int _passengers = 0;
  final int _capacity = 30;
  
  // World Objects
  final List<TrafficCar> _traffic = [];
  final List<BusStop> _stops = [];
  double _distanceTraveled = 0;
  double _timeSinceLastSpawn = 0;
  
  // UI State
  bool _isNearStop = false;
  BusStop? _currentStop;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    
    // Initial Stop
    _stops.add(BusStop(const Offset(60, -500)));
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  // ===============================
  // GAME LOOP (Update)
  // ===============================
  void _onTick(Duration elapsed) {
    // Calculate delta time (dt) in seconds
    // Ticker gives total elapsed, we need delta. 
    // For simplicity in this basic loop, we'll assume ~60fps or calculate properly if needed.
    // But Ticker callback gives *total* time. 
    // Better to use a stored timestamp.
    
    // Simplified fixed timestep for stability
    const double dt = 1.0 / 60.0; 
    
    _updatePhysics(dt);
    _updateTraffic(dt);
    _updateGameLogic(dt);
    
    setState(() {}); // Trigger redraw
  }

  void _updatePhysics(double dt) {
    // BusController Parameters (from Unity script)
    const double maxSpeed = 18.0 * kScale; // Scaled
    const double acceleration = 6.0 * kScale;
    const double brakingForce = 12.0 * kScale;
    const double steerAngle = 2.0; // Radians per second approx

    // Acceleration / Braking
    if (_inputGas) {
      _busSpeed += acceleration * dt;
    } else {
      // Natural friction/drag
      _busSpeed *= 0.98; 
    }

    if (_inputBrake) {
      _busSpeed -= brakingForce * dt;
    }

    // Clamp Speed
    if (_busSpeed > maxSpeed) _busSpeed = maxSpeed;
    if (_busSpeed < -maxSpeed / 3) _busSpeed = -maxSpeed / 3; // Reverse is slower
    
    // Stop completely if very slow and no input
    if (!_inputGas && !_inputBrake && _busSpeed.abs() < 1.0) {
      _busSpeed = 0;
    }

    // Steering (only when moving)
    if (_busSpeed.abs() > 1.0) {
      // Reverse steering direction when reversing for natural feel
      double directionFactor = _busSpeed > 0 ? 1 : -1;
      _busRotation += _inputSteer * steerAngle * dt * directionFactor;
    }

    // Update Position
    // Rotation 0 means UP (Negative Y)
    double dx = sin(_busRotation) * _busSpeed * dt;
    double dy = -cos(_busRotation) * _busSpeed * dt;

    _busPosition += Offset(dx, dy);
    _distanceTraveled += _busSpeed.abs() * dt;
  }

  void _updateTraffic(double dt) {
    // Spawner Logic
    _timeSinceLastSpawn += dt;
    if (_timeSinceLastSpawn > 2.0) { // Spawn every 2 seconds approx
      if (Random().nextBool()) {
        _spawnTraffic();
      }
      _timeSinceLastSpawn = 0;
    }

    // Move Traffic
    for (var car in _traffic) {
      // SimpleTrafficAI: Moves forward
      double dx = sin(car.rotation) * car.speed * dt;
      double dy = -cos(car.rotation) * car.speed * dt;
      car.position += Offset(dx, dy);
    }

    // Cleanup distant traffic
    _traffic.removeWhere((car) => (car.position - _busPosition).distance > 2000);
  }

  void _spawnTraffic() {
    // Spawn ahead of the bus
    double spawnDist = 800;
    // Random lane
    double laneOffset = (Random().nextInt(3) - 1) * kLaneWidth; // -100, 0, 100
    
    // Calculate spawn position based on bus rotation to spawn "ahead" on the road
    // For simplicity in this top-down view, we'll assume the road is generally "North" (Negative Y)
    // but let's make it relative to the bus for an "infinite runner" feel or absolute for a map.
    // Let's go with Absolute World Coordinates where the road is vertical along Y axis.
    
    Offset spawnPos = Offset(laneOffset, _busPosition.dy - spawnDist);
    
    _traffic.add(TrafficCar(
      position: spawnPos,
      rotation: 0, // Facing Up
      speed: (Random().nextDouble() * 8.0 + 7.0) * kScale, // 7-15 speed
      color: Colors.primaries[Random().nextInt(Colors.primaries.length)],
    ));
  }

  void _updateGameLogic(double dt) {
    // Check for Bus Stops
    _isNearStop = false;
    _currentStop = null;

    // Generate new stops if we traveled far
    if (_stops.isEmpty || (_stops.last.position.dy - _busPosition.dy).abs() > 1000) {
       // Add a stop every 2000 units roughly
       double nextStopY = _busPosition.dy - 2000;
       _stops.add(BusStop(Offset(80, nextStopY))); // Stop on the right side
    }
    
    // Cleanup old stops
    _stops.removeWhere((s) => s.position.dy > _busPosition.dy + 500);

    // Check proximity
    for (var stop in _stops) {
      if ((stop.position - _busPosition).distance < 100) {
        _isNearStop = true;
        _currentStop = stop;
        break;
      }
    }
  }

  // ===============================
  // ACTIONS
  // ===============================
  void _handlePassengerAction() {
    if (!_isNearStop || _busSpeed.abs() > 5.0) return; // Must be stopped or very slow

    // PassengerSystem Logic
    // ArriveAtStop
    int want = Random().nextInt(6) + 1; // 1 to 6
    int space = _capacity - _passengers;
    int board = min(want, space);

    // ExitStop
    int off = Random().nextInt(min(_passengers, 5) + 1);
    
    setState(() {
      _passengers -= off;
      _passengers += board;
      
      // Fare calculation
      double baseFare = 5.0;
      _money += board * baseFare;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Passengers: -$off / +$board. Fare collected: ₹${board * 5}'),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // 1. Game World (Custom Painter)
          Positioned.fill(
            child: GestureDetector(
              onPanUpdate: (details) {
                // Optional: Touch steering
              },
              child: CustomPaint(
                painter: GamePainter(
                  busPosition: _busPosition,
                  busRotation: _busRotation,
                  traffic: _traffic,
                  stops: _stops,
                ),
              ),
            ),
          ),

          // 2. HUD (Top)
          Positioned(
            top: 40,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildHudItem(Icons.attach_money, "₹ ${_money.floor()}"),
                _buildHudItem(Icons.speed, "${(_busSpeed / kScale * 3.6).round()} km/h"),
                _buildHudItem(Icons.people, "$_passengers / $_capacity"),
              ],
            ),
          ),

          // 3. Action Button (Bus Stop)
          if (_isNearStop)
            Positioned(
              bottom: 180,
              right: 20,
              child: FloatingActionButton.extended(
                onPressed: _busSpeed.abs() < 5.0 ? _handlePassengerAction : null,
                backgroundColor: _busSpeed.abs() < 5.0 ? Colors.green : Colors.grey,
                icon: const Icon(Icons.door_front_door),
                label: Text(_busSpeed.abs() < 5.0 ? "OPEN DOORS" : "STOP TO OPEN"),
              ),
            ),

          // 4. Controls (Bottom)
          Positioned(
            bottom: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Steering
                Row(
                  children: [
                    _buildControlBtn(Icons.arrow_back, (down) => _inputSteer = down ? -1 : 0),
                    const SizedBox(width: 20),
                    _buildControlBtn(Icons.arrow_forward, (down) => _inputSteer = down ? 1 : 0),
                  ],
                ),
                // Pedals
                Row(
                  children: [
                    _buildControlBtn(Icons.stop, (down) => _inputBrake = down, color: Colors.red),
                    const SizedBox(width: 20),
                    _buildControlBtn(Icons.arrow_upward, (down) => _inputGas = down, color: Colors.green),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHudItem(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildControlBtn(IconData icon, Function(bool) onStateChange, {Color color = Colors.blue}) {
    return GestureDetector(
      onTapDown: (_) => onStateChange(true),
      onTapUp: (_) => onStateChange(false),
      onTapCancel: () => onStateChange(false),
      child: Container(
        width: 70,
        height: 70,
        decoration: BoxDecoration(
          color: color.withOpacity(0.8),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(color: Colors.black26, blurRadius: 5, offset: const Offset(0, 2)),
          ],
        ),
        child: Icon(icon, color: Colors.white, size: 32),
      ),
    );
  }
}

// ===============================
// MODELS
// ===============================
class TrafficCar {
  Offset position;
  double rotation;
  double speed;
  Color color;

  TrafficCar({
    required this.position,
    required this.rotation,
    required this.speed,
    required this.color,
  });
}

class BusStop {
  Offset position;
  BusStop(this.position);
}

// ===============================
// PAINTER
// ===============================
class GamePainter extends CustomPainter {
  final Offset busPosition;
  final double busRotation;
  final List<TrafficCar> traffic;
  final List<BusStop> stops;

  GamePainter({
    required this.busPosition,
    required this.busRotation,
    required this.traffic,
    required this.stops,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Center the camera on the bus
    canvas.save();
    canvas.translate(size.width / 2, size.height / 2);
    
    // Rotate world opposite to bus rotation for "Follow Camera" effect?
    // Or just keep North up? 
    // Let's keep North up (Fixed Camera Angle) but centered on bus position.
    // This is easier to control.
    canvas.translate(-busPosition.dx, -busPosition.dy);

    // Draw Background (Grass)
    final Rect worldRect = Rect.fromCenter(
      center: busPosition, 
      width: size.width * 2, 
      height: size.height * 2
    );
    canvas.drawRect(worldRect, Paint()..color = Colors.green[800]!);

    // Draw Road (Infinite vertical strip)
    // We draw a long strip around the bus position
    double roadTop = busPosition.dy - size.height;
    double roadBottom = busPosition.dy + size.height;
    
    Paint roadPaint = Paint()..color = Colors.grey[800]!;
    canvas.drawRect(
      Rect.fromLTRB(-kRoadWidth / 2, roadTop, kRoadWidth / 2, roadBottom),
      roadPaint,
    );

    // Draw Lane Markings
    Paint lanePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
      
    // Dashed line logic simplified: just draw a line for now
    canvas.drawLine(
      Offset(0, roadTop),
      Offset(0, roadBottom),
      lanePaint,
    );
    
    // Draw Stops
    Paint stopPaint = Paint()..color = Colors.yellow.withOpacity(0.5);
    for (var stop in stops) {
      canvas.drawRect(
        Rect.fromCenter(center: stop.position, width: 60, height: 120),
        stopPaint,
      );
      // Draw "BUS STOP" text
      TextPainter tp = TextPainter(
        text: const TextSpan(text: "BUS\nSTOP", style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      tp.paint(canvas, stop.position - Offset(tp.width/2, tp.height/2));
    }

    // Draw Traffic
    for (var car in traffic) {
      canvas.save();
      canvas.translate(car.position.dx, car.position.dy);
      canvas.rotate(-car.rotation); // Canvas rotation is clockwise
      
      Paint carPaint = Paint()..color = car.color;
      canvas.drawRect(
        Rect.fromCenter(center: Offset.zero, width: kTrafficWidth, height: kTrafficHeight),
        carPaint,
      );
      canvas.restore();
    }

    // Draw Player Bus
    canvas.save();
    canvas.translate(busPosition.dx, busPosition.dy);
    canvas.rotate(-busRotation);
    
    Paint busPaint = Paint()..color = Colors.amber;
    canvas.drawRect(
      Rect.fromCenter(center: Offset.zero, width: kBusWidth, height: kBusHeight),
      busPaint,
    );
    
    // Bus Windows/Details
    Paint windowPaint = Paint()..color = Colors.blue[300]!;
    canvas.drawRect(
      Rect.fromCenter(center: const Offset(0, -20), width: kBusWidth - 4, height: 20),
      windowPaint,
    );
    
    canvas.restore();

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
