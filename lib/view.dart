import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DroneHUD(),
    );
  }
}

class DroneHUD extends StatefulWidget {
  const DroneHUD({super.key});

  @override
  State<DroneHUD> createState() => _DroneHUDState();
}

class _DroneHUDState extends State<DroneHUD> {
  static const String serverIp = "172.23.200.150"; // YOUR PC IP
  final String nodeServerUrl = "http://$serverIp:8080/control";
  final String socketUrl = "ws://$serverIp:8080";

  WebSocketChannel? _channel;

  Uint8List? _fpvFrame;
  Uint8List? _tpvFrame;
  bool _isFpvMain = true; // Toggle between FPV and TPV being main

  double _battery = 0.0;
  String _speed = "0 mb/s";
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToSocket();
  }

  void _connectToSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(socketUrl));
      _channel!.stream.listen((message) {
        final data = jsonDecode(message);
        final String type = data['type'] ?? 'UNKNOWN';

        setState(() {
          _isConnected = true;
          if (type == "FPV") {
            if (data['image'] != null) _fpvFrame = base64Decode(data['image']);
            _battery = (data['battery'] as num).toDouble();
            _speed = data['speed'];
          } else if (type == "TPV") {
            if (data['image'] != null) _tpvFrame = base64Decode(data['image']);
          }
        });
      }, onError: (err) {
        setState(() => _isConnected = false);
        Future.delayed(const Duration(seconds: 2), _connectToSocket);
      }, onDone: () {
        setState(() => _isConnected = false);
        Future.delayed(const Duration(seconds: 2), _connectToSocket);
      });
    } catch (e) {
      debugPrint("Socket error: $e");
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> sendCommandToNode(String axis, double x, double y) async {
    try {
      http.post(
        Uri.parse(nodeServerUrl),
        body: jsonEncode({"controller": axis, "x": x, "y": y}),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(milliseconds: 100));
    } catch (e) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. MAIN CAMERA VIEW
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: (_isFpvMain ? _fpvFrame : _tpvFrame) != null
                  ? Image.memory(
                _isFpvMain ? _fpvFrame! : _tpvFrame!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
                  : Center(
                child: Text(
                  _isFpvMain ? "WAITING FOR FPV..." : "WAITING FOR TPV...",
                  style: const TextStyle(color: Colors.white24, letterSpacing: 2),
                ),
              ),
            ),
          ),

          // 2. HUD TOP BAR
          Positioned(
            top: 15, left: 15,
            child: Row(
              children: [
                _StatusBadge(icon: Icons.battery_full, label: "${_battery.toStringAsFixed(0)}%", color: Colors.greenAccent.withOpacity(0.8)),
                const SizedBox(width: 8),
                _StatusBadge(icon: Icons.person_pin, label: _isFpvMain ? "MODE: FPV" : "MODE: TPV", color: Colors.blueAccent.withOpacity(0.5)),
              ],
            ),
          ),
          Positioned(top: 15, right: 15, child: _StatusBadge(icon: Icons.speed, label: _speed, color: Colors.black45, isPill: true)),

          // 3. PIP VIEW (Secondary Camera)
          Positioned(
            top: 65, left: 15,
            child: GestureDetector(
              onTap: () => setState(() => _isFpvMain = !_isFpvMain),
              child: Container(
                width: 160, height: 90,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white38, width: 2),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [BoxShadow(color: Colors.black54, blurRadius: 10)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: (_isFpvMain ? _tpvFrame : _fpvFrame) != null
                      ? Image.memory(_isFpvMain ? _tpvFrame! : _fpvFrame!, fit: BoxFit.cover, gaplessPlayback: true)
                      : Container(color: Colors.black87, child: const Icon(Icons.videocam_off, size: 20)),
                ),
              ),
            ),
          ),

          // 4. JOYSTICKS (Restored Style)
          Positioned(bottom: 40, left: 40, child: _JoystickInterface(label: "THR / YAW", onMove: (d) => sendCommandToNode("left", d.x, d.y))),
          Positioned(bottom: 40, right: 40, child: _JoystickInterface(label: "PIT / ROL", onMove: (d) => sendCommandToNode("right", d.x, d.y))),

          // 5. BLUR PANEL (Restored Style)
          Positioned(bottom: 20, left: 0, right: 0, child: Center(child: _BottomControlPanel())),

          // 6. ACTION BUTTONS
          Positioned(
            right: 15, top: 0, bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => setState(() => _isFpvMain = !_isFpvMain),
                  child: const _CircularAction(icon: Icons.swap_horiz, color: Colors.blueAccent, isActive: true),
                ),
                const SizedBox(height: 20),
                const _CircularAction(icon: Icons.camera_alt, color: Colors.blueAccent),
                const SizedBox(height: 100),
              ],
            ),
          ),

          const Center(child: _Crosshair()),
        ],
      ),
    );
  }
}

// --- COMPONENTS (UI RESTORED) ---

class _JoystickInterface extends StatelessWidget {
  final String label;
  final Function(StickDragDetails) onMove;
  const _JoystickInterface({required this.label, required this.onMove});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Joystick(mode: JoystickMode.all, listener: onMove,
        base: Container(width: 140, height: 140, decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [Colors.blueAccent.withOpacity(0.1), Colors.transparent]), border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 2))),
        stick: Container(width: 45, height: 45, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white.withOpacity(0.9), boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 10)]))),
    const SizedBox(height: 8), Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38))
  ]);
}

class _BottomControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) => ClipRRect(borderRadius: BorderRadius.circular(30), child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12), decoration: BoxDecoration(color: Colors.black.withOpacity(0.4), borderRadius: BorderRadius.circular(30), border: Border.all(color: Colors.white10)), child: Column(mainAxisSize: MainAxisSize.min, children: [
    Row(mainAxisSize: MainAxisSize.min, children: [const _PanelIcon(icon: Icons.person, label: "AUTO", isActive: true), _divider(), const _PanelIcon(icon: Icons.directions_run, label: "FOLLOW"), _divider(), const _PanelIcon(icon: Icons.gesture, label: "ORBIT")]),
    const SizedBox(height: 12),
    Row(mainAxisSize: MainAxisSize.min, children: [const _PanelIcon(icon: Icons.apps, label: "MENU"), _divider(), const _PanelIcon(icon: Icons.anchor, label: "HOVER"), _divider(), const _PanelIcon(icon: Icons.arrow_upward, label: "TAKEOFF"), _divider(), const _PanelIcon(icon: Icons.waves, label: "LAND"), _divider(), const _PanelIcon(icon: Icons.lock, label: "LOCK")])
  ]))));
  Widget _divider() => Container(width: 1, height: 20, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 10));
}

class _PanelIcon extends StatelessWidget {
  final IconData icon; final String label; final bool isActive;
  const _PanelIcon({required this.icon, required this.label, this.isActive = false});
  @override
  Widget build(BuildContext context) => Column(children: [Icon(icon, size: 20, color: isActive ? Colors.blueAccent : Colors.white70), const SizedBox(height: 4), Text(label, style: TextStyle(fontSize: 8, color: isActive ? Colors.blueAccent : Colors.white38))]);
}

class _StatusBadge extends StatelessWidget {
  final IconData icon; final String label; final Color color; final bool isPill;
  const _StatusBadge({required this.icon, required this.label, required this.color, this.isPill = false});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(isPill ? 20 : 4)), child: Row(children: [Icon(icon, size: 14, color: Colors.white), const SizedBox(width: 6), Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white))]));
}

class _CircularAction extends StatelessWidget {
  final IconData icon; final Color color; final bool isActive;
  const _CircularAction({required this.icon, required this.color, this.isActive = false});
  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: isActive ? Colors.blueAccent : color.withOpacity(0.5), width: 2), color: Colors.black38), child: Icon(icon, color: Colors.white, size: 24));
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();
  @override
  Widget build(BuildContext context) => SizedBox(width: 40, height: 40, child: Stack(children: [Center(child: Container(width: 2, height: 10, color: Colors.redAccent.withOpacity(0.8))), Center(child: Container(width: 10, height: 2, color: Colors.redAccent.withOpacity(0.8)))]));
}

/*
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DroneHUD(),
    );
  }
}

class DroneHUD extends StatefulWidget {
  const DroneHUD({super.key});

  @override
  State<DroneHUD> createState() => _DroneHUDState();
}

class _DroneHUDState extends State<DroneHUD> {
  // --- CONNECTION CONFIGURATION ---
  static const String serverIp = "172.23.200.150";
  final String nodeServerUrl = "http://$serverIp:8080/control";
  final String socketUrl = "ws://$serverIp:8080";

  WebSocketChannel? _channel;
  Uint8List? _latestFrame;
  double _battery = 0.0;
  String _speed = "0 mb/s";
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToSocket();
  }

  void _connectToSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(socketUrl));
      _channel!.stream.listen((message) {
        final data = jsonDecode(message);
        if (data['type'] == 'DATA') {
          setState(() {
            _battery = (data['battery'] as num).toDouble();
            _speed = data['speed'];
            _latestFrame = base64Decode(data['image']);
            _isConnected = true;
          });
        }
      }, onError: (err) {
        setState(() => _isConnected = false);
        Future.delayed(const Duration(seconds: 2), _connectToSocket);
      }, onDone: () {
        setState(() => _isConnected = false);
        Future.delayed(const Duration(seconds: 2), _connectToSocket);
      });
    } catch (e) {
      debugPrint("Socket connection failed: $e");
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  Future<void> sendCommandToNode(String axis, double x, double y) async {
    try {
      http.post(
        Uri.parse(nodeServerUrl),
        body: jsonEncode({
          "controller": axis,
          "x": x.toStringAsFixed(2),
          "y": y.toStringAsFixed(2),
          "timestamp": DateTime.now().millisecondsSinceEpoch,
        }),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(milliseconds: 100));
    } catch (e) {
      // Passive catch for flight data
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background Layer: LIVE Video Stream from Python
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _latestFrame != null
                  ? Image.memory(
                _latestFrame!,
                fit: BoxFit.cover,
                gaplessPlayback: true,
              )
                  : Container(
                decoration: const BoxDecoration(
                  image: DecorationImage(
                    image: NetworkImage('https://images.unsplash.com/photo-1506905925346-21bda4d32df4?q=80&w=2070'),
                    fit: BoxFit.cover,
                    opacity: 0.3,
                  ),
                ),
                child: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const CircularProgressIndicator(color: Colors.blueAccent),
                      const SizedBox(height: 15),
                      Text(
                        _isConnected ? "AWAITING VIDEO STREAM..." : "CONNECTING TO HUB...",
                        style: const TextStyle(color: Colors.white38, letterSpacing: 2, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          // 2. Top Left Indicators (First Build Style)
          Positioned(
            top: 15,
            left: 15,
            child: Row(
              children: [
                _StatusBadge(
                  icon: Icons.battery_charging_full,
                  label: "${_battery.toStringAsFixed(0)}%",
                  color: _battery > 20 ? Colors.greenAccent.withOpacity(0.8) : Colors.redAccent.withOpacity(0.8),
                ),
                const SizedBox(width: 8),
                _StatusBadge(
                  icon: Icons.gps_fixed,
                  label: "GPS",
                  color: Colors.white24,
                ),
              ],
            ),
          ),

          // 3. Top Right Data (Speed Pill)
          Positioned(
            top: 15,
            right: 15,
            child: _StatusBadge(
              icon: Icons.speed,
              label: _speed,
              color: Colors.black45,
              isPill: true,
            ),
          ),

          // 4. PIP (Picture in Picture) View - From First Build
          Positioned(
            top: 60,
            left: 15,
            child: Container(
              width: 140,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white38, width: 1),
                borderRadius: BorderRadius.circular(4),
                image: const DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?q=80&w=1948'),
                  fit: BoxFit.cover,
                ),
              ),
              child: const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4.0),
                  child: CircleAvatar(radius: 6, backgroundColor: Colors.blue),
                ),
              ),
            ),
          ),

          // 5. Left Joystick (High-Tech Style)
          Positioned(
            bottom: 40,
            left: 40,
            child: _JoystickInterface(
              label: "THR / YAW",
              onMove: (details) => sendCommandToNode("left_stick", details.x, details.y),
            ),
          ),

          // 6. Right Joystick (High-Tech Style)
          Positioned(
            bottom: 40,
            right: 40,
            child: _JoystickInterface(
              label: "PIT / ROL",
              onMove: (details) => sendCommandToNode("right_stick", details.x, details.y),
            ),
          ),

          // 7. Bottom Control Center (Blur Effect Panel)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: _BottomControlPanel(),
            ),
          ),

          // 8. Right Vertical Action Bar
          Positioned(
            right: 15,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const _CircularAction(icon: Icons.camera_alt, color: Colors.blueAccent),
                const SizedBox(height: 20),
                const _CircularAction(icon: Icons.videocam, color: Colors.blueAccent, isActive: true),
                const SizedBox(height: 100),
              ],
            ),
          ),

          // 9. Recording Indicator
          if (_isConnected)
            Positioned(
              top: 60,
              right: 15,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.8),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text("REC 00:00", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ),

          // 10. Center Crosshair
          const Center(child: _Crosshair()),
        ],
      ),
    );
  }
}

// --- HUD Components Restored From First Build Style ---

class _JoystickInterface extends StatelessWidget {
  final String label;
  final Function(StickDragDetails) onMove;
  const _JoystickInterface({required this.label, required this.onMove});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Joystick(
          mode: JoystickMode.all,
          listener: onMove,
          base: Container(
            width: 140,
            height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [
                  Colors.blueAccent.withOpacity(0.1),
                  Colors.blueAccent.withOpacity(0.05),
                  Colors.transparent,
                ],
              ),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 2),
            ),
            child: Stack(
              children: [
                Center(child: Container(width: 1, height: 140, color: Colors.blueAccent.withOpacity(0.1))),
                Center(child: Container(width: 140, height: 1, color: Colors.blueAccent.withOpacity(0.1))),
              ],
            ),
          ),
          stick: Container(
            width: 45,
            height: 45,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.9),
              boxShadow: [
                BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 10)
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }
}

class _BottomControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PanelIcon(icon: Icons.person, label: "AUTO", isActive: true),
                  _divider(),
                  const _PanelIcon(icon: Icons.directions_run, label: "FOLLOW"),
                  _divider(),
                  const _PanelIcon(icon: Icons.gesture, label: "ORBIT"),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const _PanelIcon(icon: Icons.apps, label: "MENU"),
                  _divider(),
                  const _PanelIcon(icon: Icons.anchor, label: "HOVER"),
                  _divider(),
                  const _PanelIcon(icon: Icons.arrow_upward, label: "TAKEOFF"),
                  _divider(),
                  const _PanelIcon(icon: Icons.waves, label: "LAND"),
                  _divider(),
                  const _PanelIcon(icon: Icons.lock, label: "LOCK"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 20, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 10));
}

class _PanelIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  const _PanelIcon({required this.icon, required this.label, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: isActive ? Colors.blueAccent : Colors.white70),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 8, color: isActive ? Colors.blueAccent : Colors.white38)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isPill;
  const _StatusBadge({required this.icon, required this.label, required this.color, this.isPill = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(isPill ? 20 : 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

class _CircularAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;
  const _CircularAction({required this.icon, required this.color, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: isActive ? Colors.blueAccent : color.withOpacity(0.5), width: 2),
        color: Colors.black38,
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40, height: 40,
    child: Stack(children: [
      Center(child: Container(width: 2, height: 10, color: Colors.redAccent.withOpacity(0.8))),
      Center(child: Container(width: 10, height: 2, color: Colors.redAccent.withOpacity(0.8))),
    ]),
  );
}
*/


/*import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to landscape for the flight interface experience
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DroneHUD(),
    );
  }
}

class DroneHUD extends StatefulWidget {
  const DroneHUD({super.key});

  @override
  State<DroneHUD> createState() => _DroneHUDState();
}

class _DroneHUDState extends State<DroneHUD> {
  // --- CONNECTION CONFIGURATION ---
  // IMPORTANT: Replace this with your computer's local IP address
  static const String serverIp = "172.23.200.150";
  final String nodeServerUrl = "http://$serverIp:8080/control";
  final String socketUrl = "ws://$serverIp:8080";

  WebSocketChannel? _channel;
  Uint8List? _latestFrame;
  double _battery = 0.0;
  String _speed = "0 mb/s";
  bool _isConnected = false;

  @override
  void initState() {
    super.initState();
    _connectToSocket();
  }

  void _connectToSocket() {
    try {
      _channel = WebSocketChannel.connect(Uri.parse(socketUrl));
      _channel!.stream.listen((message) {
        final data = jsonDecode(message);
        // Matching the structure sent by the Python streamer
        if (data['type'] == 'DATA') {
          setState(() {
            _battery = (data['battery'] as num).toDouble();
            _speed = data['speed'];
            _latestFrame = base64Decode(data['image']);
            _isConnected = true;
          });
        }
      }, onError: (err) {
        setState(() => _isConnected = false);
        Future.delayed(const Duration(seconds: 2), _connectToSocket);
      }, onDone: () {
        setState(() => _isConnected = false);
        Future.delayed(const Duration(seconds: 2), _connectToSocket);
      });
    } catch (e) {
      debugPrint("Socket connection failed: $e");
    }
  }

  @override
  void dispose() {
    _channel?.sink.close();
    super.dispose();
  }

  // Sends joystick coordinates to the Node.js server
  Future<void> sendCommandToNode(String axis, double x, double y) async {
    try {
      http.post(
        Uri.parse(nodeServerUrl),
        body: jsonEncode({
          "controller": axis,
          "x": x.toStringAsFixed(2),
          "y": y.toStringAsFixed(2),
          "timestamp": DateTime.now().millisecondsSinceEpoch,
        }),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(milliseconds: 100));
    } catch (e) {
      // Ignore network errors to prevent UI freezing
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background Layer: Video Stream from Python
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _latestFrame != null
                  ? Image.memory(
                _latestFrame!,
                fit: BoxFit.cover,
                gaplessPlayback: true, // Prevents flickering
              )
                  : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.blueAccent),
                    const SizedBox(height: 15),
                    Text(
                      _isConnected
                          ? "CONNECTED. WAITING FOR PYTHON VIDEO..."
                          : "CONNECTING TO $serverIp:8080...",
                      style: const TextStyle(color: Colors.white38, letterSpacing: 2, fontSize: 10),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Top Bar Telemetry
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _StatusBadge(
                      icon: Icons.battery_charging_full,
                      label: "${_battery.toStringAsFixed(1)}%",
                      color: _battery > 20 ? Colors.greenAccent.withOpacity(0.8) : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    _StatusBadge(
                      icon: Icons.link,
                      label: _isConnected ? "LINK ACTIVE" : "DISCONNECTED",
                      color: _isConnected ? Colors.blueAccent.withOpacity(0.5) : Colors.redAccent.withOpacity(0.5),
                    ),
                  ],
                ),
                _StatusBadge(
                  icon: Icons.wifi,
                  label: _speed,
                  color: Colors.black87,
                  isPill: true,
                ),
              ],
            ),
          ),

          // 3. Left Joystick (Throttle / Yaw)
          Positioned(
            bottom: 40,
            left: 40,
            child: _JoystickInterface(
              label: "THR / YAW",
              onMove: (details) => sendCommandToNode("left_stick", details.x, details.y),
            ),
          ),

          // 4. Right Joystick (Pitch / Roll)
          Positioned(
            bottom: 40,
            right: 40,
            child: _JoystickInterface(
              label: "PIT / ROL",
              onMove: (details) => sendCommandToNode("right_stick", details.x, details.y),
            ),
          ),

          // 5. Center Visuals (Crosshair)
          const Center(child: _Crosshair()),

          // 6. Bottom Control Panel (Translucent)
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(child: _BottomControlPanel()),
          ),

          // 7. Right Vertical Actions
          Positioned(
            right: 25,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircularAction(icon: Icons.camera_alt, color: Colors.white),
                const SizedBox(height: 20),
                _CircularAction(icon: Icons.videocam, color: Colors.white, isActive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- HUD Components ---

class _JoystickInterface extends StatelessWidget {
  final String label;
  final Function(StickDragDetails) onMove;
  const _JoystickInterface({required this.label, required this.onMove});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Joystick(
          mode: JoystickMode.all,
          listener: onMove,
          base: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueAccent.withOpacity(0.4), width: 2),
              gradient: RadialGradient(colors: [Colors.blueAccent.withOpacity(0.1), Colors.transparent]),
            ),
          ),
          stick: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.9),
              boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 15)],
            ),
            child: const Icon(Icons.drag_handle, color: Colors.black26),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.2)),
      ],
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40, height: 40,
    child: Stack(children: [
      Center(child: Container(width: 2, height: 10, color: Colors.redAccent.withOpacity(0.8))),
      Center(child: Container(width: 10, height: 2, color: Colors.redAccent.withOpacity(0.8))),
    ]),
  );
}

class _BottomControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _PanelItem(icon: Icons.accessibility_new, label: "AUTO", isActive: true),
                _vDiv(),
                _PanelItem(icon: Icons.directions_run, label: "FOLLOW"),
                _vDiv(),
                _PanelItem(icon: Icons.gesture, label: "WAYPOINT"),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: Colors.white10, height: 1)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _PanelItem(icon: Icons.grid_view_rounded, label: "MODES"),
                _vDiv(),
                _PanelItem(icon: Icons.anchor, label: "HOVER"),
                _vDiv(),
                _PanelItem(icon: Icons.arrow_upward, label: "TAKEOFF"),
                _vDiv(),
                _PanelItem(icon: Icons.waves, label: "LAND"),
              ]),
            ],
          ),
        ),
      ),
    );
  }
  Widget _vDiv() => Container(width: 1, height: 20, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 12));
}

class _PanelItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  const _PanelItem({required this.icon, required this.label, this.isActive = false});
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, size: 20, color: isActive ? Colors.blueAccent : Colors.white),
    const SizedBox(height: 4),
    Text(label, style: TextStyle(fontSize: 8, color: isActive ? Colors.blueAccent : Colors.white38)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isPill;
  const _StatusBadge({required this.icon, required this.label, required this.color, this.isPill = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(isPill ? 30 : 6)),
    child: Row(children: [
      Icon(icon, size: 14, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
    ]),
  );
}

class _CircularAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;
  const _CircularAction({required this.icon, required this.color, this.isActive = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: isActive ? Colors.blueAccent : Colors.white38, width: 2),
      color: Colors.black45,
    ),
    child: Icon(icon, color: color, size: 28),
  );
}*/
//3rd build
/*
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:flutter_joystick/flutter_joystick.dart';
import 'package:http/http.dart' as http;

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DroneHUD(),
    );
  }
}

class DroneHUD extends StatefulWidget {
  const DroneHUD({super.key});

  @override
  State<DroneHUD> createState() => _DroneHUDState();
}

class _DroneHUDState extends State<DroneHUD> {
  // --- CONNECTION CONFIGURATION ---
  // CHANGE THIS to your Computer's Local IP (e.g., 192.168.1.15)
  // You can find this by typing 'ipconfig' (Windows) or 'ifconfig' (Mac/Linux) in terminal
  static const String serverIp = "192.168.1.100";

  final String nodeServerUrl = "http://$serverIp:3000/control";
  final String pythonTelemetryUrl = "ws://$serverIp:8000/telemetry"; // Example for WebSocket

  // WebRTC & Telemetry State
  final _localRenderer = RTCVideoRenderer();
  double _battery = 100.0;
  String _speed = "0 mb/s";
  Timer? _telemetryRetryTimer;

  @override
  void initState() {
    super.initState();
    initWebRTC();
    connectToTelemetry();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _telemetryRetryTimer?.cancel();
    super.dispose();
  }

  Future<void> initWebRTC() async {
    await _localRenderer.initialize();
    // In a real setup, you'd signal your Computer's IP here to start the WebRTC handshake
  }

  // Connect to your Python server (Mocking the stream logic)
  void connectToTelemetry() {
    // This simulates receiving data from your Python script running in Android Studio
    _telemetryRetryTimer = Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (mounted) {
        setState(() {
          // In production: replace with actual websocket data parsing
          _battery = (_battery - 0.05).clamp(0, 100);
          _speed = "${(450 + (timer.tick % 20))} mb/s";
        });
      }
    });
  }

  // Send Joystick data to your Node.js server running in Android Studio
  Future<void> sendCommandToNode(String axis, double x, double y) async {
    try {
      // POSTing to your computer's IP
      http.post(
        Uri.parse(nodeServerUrl),
        body: jsonEncode({
          "controller": axis,
          "x": x.toStringAsFixed(2),
          "y": y.toStringAsFixed(2),
        }),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(milliseconds: 100));
    } catch (e) {
      // Ignore network lag during flight
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. WebRTC Video Feed Layer
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _localRenderer.srcObject != null
                  ? RTCVideoView(_localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(color: Colors.blueAccent),
                    const SizedBox(height: 15),
                    Text(
                      "CONNECTED TO $serverIp",
                      style: const TextStyle(color: Colors.white24, fontSize: 10),
                    ),
                    const Text(
                      "WAITING FOR STREAM...",
                      style: TextStyle(color: Colors.white38, letterSpacing: 2),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // 2. Dynamic Top Bar
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _StatusBadge(
                      icon: Icons.battery_charging_full,
                      label: "${_battery.toStringAsFixed(1)}%",
                      color: _battery > 20 ? Colors.greenAccent.withOpacity(0.8) : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    const _StatusBadge(
                      icon: Icons.gps_fixed,
                      label: "GPS: OK",
                      color: Colors.white12,
                    ),
                  ],
                ),
                _StatusBadge(
                  icon: Icons.wifi,
                  label: _speed,
                  color: Colors.black87,
                  isPill: true,
                ),
              ],
            ),
          ),

          // 3. Joysticks (Now Interactive)
          Positioned(
            bottom: 40,
            left: 40,
            child: _JoystickInterface(
              label: "THR / YAW",
              onMove: (details) => sendCommandToNode("left_stick", details.x, details.y),
            ),
          ),
          Positioned(
            bottom: 40,
            right: 40,
            child: _JoystickInterface(
              label: "PIT / ROL",
              onMove: (details) => sendCommandToNode("right_stick", details.x, details.y),
            ),
          ),

          // 4. Center Crosshair
          const Center(child: _Crosshair()),

          // 5. Bottom Control Panel
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(child: _BottomControlPanel()),
          ),

          // 6. Camera Actions
          Positioned(
            right: 25,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircularAction(icon: Icons.camera_alt, color: Colors.white),
                const SizedBox(height: 20),
                _CircularAction(icon: Icons.videocam, color: Colors.white, isActive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- HELPER COMPONENTS ---

class _JoystickInterface extends StatelessWidget {
  final String label;
  final Function(StickDragDetails) onMove;
  const _JoystickInterface({required this.label, required this.onMove});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Joystick(
          mode: JoystickMode.all,
          listener: onMove,
          base: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueAccent.withOpacity(0.4), width: 2),
              gradient: RadialGradient(colors: [Colors.blueAccent.withOpacity(0.1), Colors.transparent]),
            ),
          ),
          stick: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.9),
              boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 15)],
            ),
            child: const Icon(Icons.drag_handle, color: Colors.black26),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.2)),
      ],
    );
  }
}

class _Crosshair extends StatelessWidget {
  const _Crosshair();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40, height: 40,
    child: Stack(children: [
      Center(child: Container(width: 2, height: 10, color: Colors.redAccent.withOpacity(0.8))),
      Center(child: Container(width: 10, height: 2, color: Colors.redAccent.withOpacity(0.8))),
    ]),
  );
}

class _BottomControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _PanelItem(icon: Icons.accessibility_new, label: "AUTO", isActive: true),
                _vDiv(),
                _PanelItem(icon: Icons.directions_run, label: "FOLLOW"),
                _vDiv(),
                _PanelItem(icon: Icons.gesture, label: "WAYPOINT"),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: Colors.white10, height: 1)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _PanelItem(icon: Icons.grid_view_rounded, label: "MODES"),
                _vDiv(),
                _PanelItem(icon: Icons.anchor, label: "HOVER"),
                _vDiv(),
                _PanelItem(icon: Icons.arrow_upward, label: "TAKEOFF"),
                _vDiv(),
                _PanelItem(icon: Icons.waves, label: "LAND"),
              ]),
            ],
          ),
        ),
      ),
    );
  }
  Widget _vDiv() => Container(width: 1, height: 20, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 12));
}

class _PanelItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  const _PanelItem({required this.icon, required this.label, this.isActive = false});
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, size: 20, color: isActive ? Colors.blueAccent : Colors.white),
    Text(label, style: TextStyle(fontSize: 8, color: isActive ? Colors.blueAccent : Colors.white38)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isPill;
  const _StatusBadge({required this.icon, required this.label, required this.color, this.isPill = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(isPill ? 30 : 6)),
    child: Row(children: [
      Icon(icon, size: 14, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
    ]),
  );
}

class _CircularAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;
  const _CircularAction({required this.icon, required this.color, this.isActive = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: isActive ? Colors.blueAccent : Colors.white38, width: 2),
      color: Colors.black45,
    ),
    child: Icon(icon, color: color, size: 28),
  );
}
*/





//2nd build
/*
import 'dart:ui';
import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart'; // Required for Video
import 'package:flutter_joystick/flutter_joystick.dart'; // Required for Control
import 'package:http/http.dart' as http; // Required for Node.js API

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DroneHUD(),
    );
  }
}

class DroneHUD extends StatefulWidget {
  const DroneHUD({super.key});

  @override
  State<DroneHUD> createState() => _DroneHUDState();
}

class _DroneHUDState extends State<DroneHUD> {
  // WebRTC & Telemetry State
  final _localRenderer = RTCVideoRenderer();
  double _battery = 100.0;
  String _speed = "0 mb/s";
  Timer? _mockTelemetryTimer;

  // Connection Configs
  final String nodeServerUrl = "http://192.168.1.100:3000/control";

  @override
  void initState() {
    super.initState();
    initWebRTC();
    startMockTelemetry();
  }

  @override
  void dispose() {
    _localRenderer.dispose();
    _mockTelemetryTimer?.cancel();
    super.dispose();
  }

  Future<void> initWebRTC() async {
    await _localRenderer.initialize();
    // Logic for connecting to your WebRTC signaling server would go here
    // For now, it stays initialized awaiting a stream
  }

  void startMockTelemetry() {
    // Simulating data from your Python server
    _mockTelemetryTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _battery = (_battery - 0.1).clamp(0, 100);
        _speed = "${(500 + timer.tick % 50)} mb/s";
      });
    });
  }

  Future<void> sendCommandToNode(String axis, double x, double y) async {
    try {
      // Non-blocking call to Node.js server
      await http.post(
        Uri.parse(nodeServerUrl),
        body: jsonEncode({
          "controller": axis,
          "x": x.toStringAsFixed(2),
          "y": y.toStringAsFixed(2),
          "timestamp": DateTime.now().toIso8601String(),
        }),
        headers: {"Content-Type": "application/json"},
      ).timeout(const Duration(milliseconds: 200));
    } catch (e) {
      // Silently handle timeout/errors to prevent UI stutter
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. WebRTC Video Feed Layer
          Positioned.fill(
            child: Container(
              color: Colors.black,
              child: _localRenderer.srcObject != null
                  ? RTCVideoView(_localRenderer, objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover)
                  : Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    CircularProgressIndicator(color: Colors.blueAccent),
                    SizedBox(height: 10),
                    Text("AWAITING WEBRTC FEED...", style: TextStyle(color: Colors.white38, letterSpacing: 2)),
                  ],
                ),
              ),
            ),
          ),

          // 2. Dynamic Top Bar
          Positioned(
            top: 20,
            left: 20,
            right: 20,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    _StatusBadge(
                      icon: Icons.battery_charging_full,
                      label: "${_battery.toStringAsFixed(1)}%",
                      color: _battery > 20 ? Colors.greenAccent.withOpacity(0.8) : Colors.redAccent,
                    ),
                    const SizedBox(width: 8),
                    const _StatusBadge(
                      icon: Icons.gps_fixed,
                      label: "GPS: ACTIVE",
                      color: Colors.white12,
                    ),
                  ],
                ),
                _StatusBadge(
                  icon: Icons.wifi,
                  label: _speed,
                  color: Colors.black87,
                  isPill: true,
                ),
              ],
            ),
          ),

          // 3. Left Interactive Joystick (Throttle / Yaw)
          Positioned(
            bottom: 40,
            left: 40,
            child: _JoystickInterface(
              label: "THR / YAW",
              onMove: (details) => sendCommandToNode("left_stick", details.x, details.y),
            ),
          ),

          // 4. Right Interactive Joystick (Pitch / Roll)
          Positioned(
            bottom: 40,
            right: 40,
            child: _JoystickInterface(
              label: "PIT / ROL",
              onMove: (details) => sendCommandToNode("right_stick", details.x, details.y),
            ),
          ),

          // 5. HUD Overlay Components
          const Center(child: _Crosshair()),

          // 6. Bottom Control Panel
          Positioned(
            bottom: 30,
            left: 0,
            right: 0,
            child: Center(child: _BottomControlPanel()),
          ),

          // 7. Right Vertical Actions
          Positioned(
            right: 25,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircularAction(icon: Icons.camera_alt, color: Colors.white),
                const SizedBox(height: 20),
                _CircularAction(icon: Icons.videocam, color: Colors.white, isActive: true),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _JoystickInterface extends StatelessWidget {
  final String label;
  final Function(StickDragDetails) onMove;

  const _JoystickInterface({required this.label, required this.onMove});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Joystick(
          mode: JoystickMode.all,
          listener: onMove,
          base: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: Colors.blueAccent.withOpacity(0.4), width: 2),
              gradient: RadialGradient(colors: [Colors.blueAccent.withOpacity(0.1), Colors.transparent]),
            ),
          ),
          stick: Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(0.9),
              boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 15)],
            ),
            child: const Icon(Icons.drag_handle, color: Colors.black26),
          ),
        ),
        const SizedBox(height: 10),
        Text(label, style: const TextStyle(fontSize: 9, color: Colors.white54, letterSpacing: 1.2)),
      ],
    );
  }
}

// ... UI Presentation components remain the same for high-fidelity look ...

class _Crosshair extends StatelessWidget {
  const _Crosshair();
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 40, height: 40,
    child: Stack(children: [
      Center(child: Container(width: 2, height: 10, color: Colors.redAccent)),
      Center(child: Container(width: 10, height: 2, color: Colors.redAccent)),
    ]),
  );
}

class _BottomControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(40),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                _PanelItem(icon: Icons.accessibility_new, label: "AUTO", isActive: true),
                _vDiv(),
                _PanelItem(icon: Icons.directions_run, label: "FOLLOW"),
                _vDiv(),
                _PanelItem(icon: Icons.gesture, label: "WAYPOINT"),
              ]),
              const Padding(padding: EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: Colors.white10, height: 1)),
              Row(mainAxisSize: MainAxisSize.min, children: [
                _PanelItem(icon: Icons.grid_view_rounded, label: "MODES"),
                _vDiv(),
                _PanelItem(icon: Icons.anchor, label: "HOVER"),
                _vDiv(),
                _PanelItem(icon: Icons.arrow_upward, label: "TAKEOFF"),
                _vDiv(),
                _PanelItem(icon: Icons.waves, label: "LAND"),
              ]),
            ],
          ),
        ),
      ),
    );
  }
  Widget _vDiv() => Container(width: 1, height: 20, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 12));
}

class _PanelItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  const _PanelItem({required this.icon, required this.label, this.isActive = false});
  @override
  Widget build(BuildContext context) => Column(children: [
    Icon(icon, size: 20, color: isActive ? Colors.blueAccent : Colors.white),
    Text(label, style: TextStyle(fontSize: 8, color: isActive ? Colors.blueAccent : Colors.white38)),
  ]);
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isPill;
  const _StatusBadge({required this.icon, required this.label, required this.color, this.isPill = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(isPill ? 30 : 6)),
    child: Row(children: [
      Icon(icon, size: 14, color: Colors.white),
      const SizedBox(width: 8),
      Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: Colors.white)),
    ]),
  );
}

class _CircularAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final bool isActive;
  const _CircularAction({required this.icon, required this.color, this.isActive = false});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: isActive ? Colors.blueAccent : Colors.white38, width: 2),
      color: Colors.black45,
    ),
    child: Icon(icon, color: color, size: 28),
  );
}
*/



//First Build
/*
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Lock to landscape for the flight interface experience
  SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  runApp(const DroneControlApp());
}

class DroneControlApp extends StatelessWidget {
  const DroneControlApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const DroneHUD(),
    );
  }
}

class DroneHUD extends StatelessWidget {
  const DroneHUD({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Background Placeholder (Simulating Camera Feed)
          Positioned.fill(
            child: Image.network(
              'https://images.unsplash.com/photo-1506905925346-21bda4d32df4?q=80&w=2070&auto=format&fit=crop',
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[900]),
            ),
          ),

          // 2. Top Left Indicators (Battery/GPS)
          Positioned(
            top: 15,
            left: 15,
            child: Row(
              children: [
                _StatusBadge(
                  icon: Icons.battery_charging_full,
                  label: "80%",
                  color: Colors.greenAccent.withOpacity(0.8),
                ),
                const SizedBox(width: 8),
                _StatusBadge(
                  icon: Icons.gps_fixed,
                  label: "GPS",
                  color: Colors.white24,
                ),
              ],
            ),
          ),

          // 3. Top Right Data (Speed/Connection)
          Positioned(
            top: 15,
            right: 15,
            child: _StatusBadge(
              icon: Icons.speed,
              label: "545mb/s",
              color: Colors.black45,
              isPill: true,
            ),
          ),

          // 4. PIP (Picture in Picture) View - Left Side
          Positioned(
            top: 60,
            left: 15,
            child: Container(
              width: 140,
              height: 80,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white38, width: 1),
                borderRadius: BorderRadius.circular(4),
                image: const DecorationImage(
                  image: NetworkImage('https://images.unsplash.com/photo-1470071459604-3b5ec3a7fe05?q=80&w=1948&auto=format&fit=crop'),
                  fit: BoxFit.cover,
                ),
              ),
              child: const Align(
                alignment: Alignment.topRight,
                child: Padding(
                  padding: EdgeInsets.all(4.0),
                  child: CircleAvatar(radius: 6, backgroundColor: Colors.blue),
                ),
              ),
            ),
          ),

          // 5. Left Joystick
          Positioned(
            bottom: 40,
            left: 40,
            child: const VirtualJoystick(label: "THR / YAW"),
          ),

          // 6. Right Joystick
          Positioned(
            bottom: 40,
            right: 40,
            child: const VirtualJoystick(label: "PIT / ROL"),
          ),

          // 7. Bottom Control Center (The complex pill shape)
          Positioned(
            bottom: 20,
            left: 0,
            right: 0,
            child: Center(
              child: _BottomControlPanel(),
            ),
          ),

          // 8. Right Vertical Action Bar (Camera/Record)
          Positioned(
            right: 15,
            top: 0,
            bottom: 0,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircularAction(icon: Icons.camera_alt, color: Colors.blueAccent),
                const SizedBox(height: 20),
                _CircularAction(icon: Icons.videocam, color: Colors.blueAccent),
                const SizedBox(height: 100), // Spacing for orientation
              ],
            ),
          ),

          // 9. Recording Indicator
          Positioned(
            top: 60,
            right: 15,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.8),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text("REC 03:12", style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}

/// A custom painted widget for the Joysticks to match the glowing blue UI
class VirtualJoystick extends StatelessWidget {
  final String label;
  const VirtualJoystick({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 140,
          height: 140,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(
              colors: [
                Colors.blueAccent.withOpacity(0.1),
                Colors.blueAccent.withOpacity(0.05),
                Colors.transparent,
              ],
            ),
            border: Border.all(color: Colors.blueAccent.withOpacity(0.3), width: 2),
          ),
          child: Stack(
            children: [
              // Axis lines
              Center(child: Container(width: 1, height: 140, color: Colors.blueAccent.withOpacity(0.1))),
              Center(child: Container(width: 140, height: 1, color: Colors.blueAccent.withOpacity(0.1))),
              // Thumbstick
              Center(
                child: Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.8),
                    boxShadow: [
                      BoxShadow(color: Colors.blueAccent.withOpacity(0.5), blurRadius: 10)
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 10, color: Colors.white38)),
      ],
    );
  }
}

class _BottomControlPanel extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.4),
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PanelIcon(icon: Icons.person, label: "AUTO", isActive: true),
                  _divider(),
                  _PanelIcon(icon: Icons.directions_run, label: "FOLLOW"),
                  _divider(),
                  _PanelIcon(icon: Icons.gesture, label: "ORBIT"),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _PanelIcon(icon: Icons.apps, label: "MENU"),
                  _divider(),
                  _PanelIcon(icon: Icons.anchor, label: "HOVER"),
                  _divider(),
                  _PanelIcon(icon: Icons.arrow_upward, label: "TAKEOFF"),
                  _divider(),
                  _PanelIcon(icon: Icons.waves, label: "LAND"),
                  _divider(),
                  _PanelIcon(icon: Icons.lock, label: "LOCK"),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _divider() => Container(width: 1, height: 20, color: Colors.white10, margin: const EdgeInsets.symmetric(horizontal: 10));
}

class _PanelIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  const _PanelIcon({required this.icon, required this.label, this.isActive = false});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 20, color: isActive ? Colors.blueAccent : Colors.white70),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(fontSize: 8, color: isActive ? Colors.blueAccent : Colors.white38)),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final bool isPill;
  const _StatusBadge({required this.icon, required this.label, required this.color, this.isPill = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(isPill ? 20 : 4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white)),
        ],
      ),
    );
  }
}

class _CircularAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  const _CircularAction({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color.withOpacity(0.5), width: 2),
        color: Colors.black38,
      ),
      child: Icon(icon, color: Colors.white, size: 24),
    );
  }
}*/
