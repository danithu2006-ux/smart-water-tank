import 'dart:async';
import 'dart:convert';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;

// FirebaseService uses ChangeNotifier to notify UI screens to redraw when data changes.
class FirebaseService extends ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  late final DatabaseReference _db;

  // Firebase REST API base URL (uses HTTPS, not WebSocket)
  static const _dbUrl = 'https://iot-76f71-default-rtdb.firebaseio.com';

  // Key used to store/retrieve our cached user list from the phone's storage
  static const _cacheKey = 'cached_family_members';

  // In-memory list to store family members retrieved from database
  List<Map<String, dynamic>> _cachedUsers = [];

  FirebaseService() {
    _initializeConnection();
    _loadCachedUsers();
  }

  void _initializeConnection() {
    try {
      // Explicitly set the database URL to ensure correct project connection
      final dbInstance = FirebaseDatabase.instanceFor(
        app: Firebase.app(),
        databaseURL: 'https://iot-76f71-default-rtdb.firebaseio.com',
      );
      _db = dbInstance.ref();

      // Enable logging to see technical details in console
      dbInstance.setLoggingEnabled(true);

      // Monitor and log connection state
      dbInstance.ref('.info/connected').onValue.listen((event) {
        final connected = event.snapshot.value == true;
        if (connected) {
          debugPrint('>>> SUCCESS: Realtime Database connected!');
        } else {
          debugPrint('>>> WARNING: Realtime Database is currently offline.');
        }
      });
    } catch (e) {
      debugPrint('Database Initialization Error: $e');
      _db = FirebaseDatabase.instance.ref();
    }
  }

  DatabaseReference get _deviceControlRef => _db.child('device_control');

  /// Loads cached users from persistent storage (SharedPreferences) on startup.
  /// This runs asynchronously because reading from disk takes time.
  Future<void> _loadCachedUsers() async {
    try {
      // Get reference to the phone's SharedPreferences storage
      final prefs = await SharedPreferences.getInstance();

      // Retrieve the JSON string representation of the users
      final jsonStr = prefs.getString(_cacheKey);

      if (jsonStr != null) {
        // Decode the JSON string back into a list of dynamic Dart objects
        final List<dynamic> decoded = jsonDecode(jsonStr);

        // Convert the dynamic list into structured Map objects
        _cachedUsers = decoded
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        debugPrint('Loaded ${_cachedUsers.length} cached users from disk');

        // Notify any active UI listeners to rebuild with this cached data
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Failed to load cached users: $e');
    }
  }

  /// Saves the current user list cache locally to the phone's storage.
  Future<void> _persistCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // Serialize the list of Maps into a single JSON string and save it
      await prefs.setString(_cacheKey, jsonEncode(_cachedUsers));
    } catch (e) {
      debugPrint('Failed to persist user cache: $e');
    }
  }

  // A Stream that emits true if a user is logged in, and false if logged out.
  // Streams are continuous data pipes that push updates whenever auth state changes.
  Stream<bool> get authStateChanges =>
      _auth.authStateChanges().map((user) => user != null);

  // Helper getters to check authentication status instantly
  bool get isSignedIn => _auth.currentUser != null;
  String? get currentUserId => _auth.currentUser?.uid;

  /// Helper method to validate if an email format is correct
  bool _isValidEmail(String email) {
    // Remove invisible control characters that might be pasted by accident
    final cleaned = email
        .replaceAll(
          RegExp(r'[\u0000-\u001f\u007f\u200B\u200C\u200D\uFEFF]'),
          '',
        )
        .trim()
        .toLowerCase();

    // Regular expression matching standard email formats (e.g., user@domain.com)
    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');
    return cleaned.isNotEmpty && emailRegex.hasMatch(cleaned);
  }

  // In-memory baseline storage (not persisted in DB, as per developer prompt)
  double _lastOpenedFilling = 0.0;
  double _lastOpenedUsage = 0.0;

  /// A Stream that polls the Firebase REST API every 2 seconds for tank status.
  /// Uses HTTP GET instead of WebSocket (which is blocked on some networks).
  Stream<Map<String, dynamic>> get tankStatusStream {
    return Stream.periodic(const Duration(seconds: 2)).asyncMap((_) async {
      try {
        final responses = await Future.wait([
          http.get(Uri.parse('$_dbUrl/device_control.json')),
          http.get(Uri.parse('$_dbUrl/sensorData.json')),
        ]).timeout(const Duration(seconds: 10));

        final deviceResponse = responses[0];
        final sensorResponse = responses[1];

        final deviceData =
            deviceResponse.statusCode == 200 && deviceResponse.body != 'null'
            ? json.decode(deviceResponse.body)
            : {};
        final sensorData =
            sensorResponse.statusCode == 200 && sensorResponse.body != 'null'
            ? json.decode(sensorResponse.body)
            : {};

        final double currentIntake =
            (sensorData['intakeFlow'] ?? 0.0).toDouble();
        final double currentOutput =
            (sensorData['dailyUsage'] ?? 0.0).toDouble();
        final bool isFilling = deviceData['is_filling'] == true;
        final bool isWasting = deviceData['is_wasting'] == true;

        final double baseLevel =
            (deviceData['base_tank_level'] ?? deviceData['current_level_liters'] ?? 0.0)
                .toDouble();

        double liveLevel = baseLevel;

        if (isFilling) {
          final double sessionIntake = currentIntake - _lastOpenedFilling;
          liveLevel = baseLevel + (sessionIntake > 0 ? sessionIntake : 0.0);
        } else if (isWasting) {
          final double sessionOutput = currentOutput - _lastOpenedUsage;
          liveLevel = baseLevel - (sessionOutput > 0 ? sessionOutput : 0.0);
        } else {
          liveLevel = baseLevel;
        }

        if (liveLevel < 0) liveLevel = 0.0;

        return {
          'current_level_liters': liveLevel,
          'intakeFlow': currentIntake,
          'dailyUsage': currentOutput,
          'is_filling': isFilling,
          'is_wasting': isWasting,
          'filling_valve': deviceData['filling_valve'] == true,
          'outgoing_valve': deviceData['outgoing_valve'] == true,
        };
      } catch (e) {
        debugPrint('REST poll error: $e');
      }
      return {
        'current_level_liters': 0.0,
        'intakeFlow': 0.0,
        'dailyUsage': 0.0,
        'is_filling': false,
        'is_wasting': false,
        'filling_valve': false,
        'outgoing_valve': false,
      };
    });
  }

  /// A Stream that fetches and monitors the history of tank fillings via REST.
  Stream<List<Map<String, dynamic>>> get fillingHistoryStream {
    return Stream.periodic(const Duration(seconds: 2)).asyncMap((_) async {
      try {
        final response = await http.get(
          Uri.parse('$_dbUrl/history/filling.json'),
        );
        if (response.statusCode == 200 && response.body != 'null') {
          final raw = json.decode(response.body);
          if (raw is Map) {
            return raw.entries.map((entry) {
                final item = Map<String, dynamic>.from(entry.value);
                return {
                  'timestamp': DateTime.fromMillisecondsSinceEpoch(
                    item['timestamp'] ?? 0,
                  ),
                  'liters_filled': (item['liters_filled'] ?? 0.0).toDouble(),
                };
              }).toList()
              ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
          }
        }
      } catch (e) {
        debugPrint('REST filling history stream error: $e');
      }
      return <Map<String, dynamic>>[];
    });
  }

  /// A Stream that fetches and monitors the history of water usage (wastage) via REST.
  Stream<List<Map<String, dynamic>>> get wastageHistoryStream {
    return Stream.periodic(const Duration(seconds: 2)).asyncMap((_) async {
      try {
        final response = await http.get(
          Uri.parse('$_dbUrl/history/wastage.json'),
        );
        if (response.statusCode == 200 && response.body != 'null') {
          final raw = json.decode(response.body);
          if (raw is Map) {
            return raw.entries.map((entry) {
                final item = Map<String, dynamic>.from(entry.value);
                return {
                  'timestamp': DateTime.fromMillisecondsSinceEpoch(
                    item['timestamp'] ?? 0,
                  ),
                  'liters_wasted': (item['liters_wasted'] ?? 0.0).toDouble(),
                };
              }).toList()
              ..sort((a, b) => b['timestamp'].compareTo(a['timestamp']));
          }
        }
      } catch (e) {
        debugPrint('REST wastage history stream error: $e');
      }
      return <Map<String, dynamic>>[];
    });
  }

  // Local auth state to bypass blocked Firebase Auth network calls
  bool _isSignedInLocal = false;
  bool get isSignedInLocal => _isSignedInLocal;

  /// Logs the user in locally (bypassing Firebase SDK network calls which are blocked)
  /// and proceeds to the dashboard.
  Future<void> loginAsMember(String role) async {
    try {
      _isSignedInLocal = true;

      // Initialize control values on successful sign in if needed
      await _ensureDeviceControlNode();

      // Notify any listeners (like AuthWrapper) to trigger transitions to the dashboard
      notifyListeners();
    } catch (e) {
      debugPrint('Login error: $e');
      throw Exception('Failed to log in as $role. Check network connection.');
    }
  }

  /// Signs the user out of the app locally.
  Future<void> signOut() async {
    _isSignedInLocal = false;
    notifyListeners();
  }

  /// Fetches the latest list of registered users from Firebase and updates local cache.
  Future<void> _refreshCachedUsers() async {
    try {
      final response = await http
          .get(Uri.parse('$_dbUrl/users.json'))
          .timeout(const Duration(seconds: 10));
      final users = <Map<String, dynamic>>[];

      if (response.statusCode == 200 && response.body != 'null') {
        final raw = json.decode(response.body);
        if (raw is Map) {
          raw.forEach((key, value) {
            if (value is Map) {
              users.add({
                'uid': key.toString(),
                'email': value['user_email'] ?? '',
                'role': value['role'] ?? '',
              });
            }
          });
        }
      }

      // Overwrite local memory cache and save it to SharedPreferences disk cache
      _cachedUsers = users;
      await _persistCache();
      debugPrint('Cached users updated: ${users.length}');
    } catch (e) {
      debugPrint('Failed to refresh cached users: $e');
    }
  }

  /// Returns a list of all registered users. First attempts to fetch from the DB.
  /// If database fetch fails (offline or permission error), returns the local disk cached copy.
  Future<List<Map<String, dynamic>>> getAllUsers() async {
    // If the in-memory cache is empty, load cache from SharedPreferences disk first
    if (_cachedUsers.isEmpty) {
      await _loadCachedUsers();
    }

    try {
      // Query Firebase /users node via REST API
      final response = await http
          .get(Uri.parse('$_dbUrl/users.json'))
          .timeout(const Duration(seconds: 10));

      final users = <Map<String, dynamic>>[];
      if (response.statusCode == 200 && response.body != 'null') {
        final raw = json.decode(response.body);
        if (raw is Map) {
          raw.forEach((key, value) {
            if (value is Map) {
              users.add({
                'uid': key.toString(),
                'email': value['user_email'] ?? '',
                'role': value['role'] ?? '',
              });
            }
          });
        }
      } else {
        // If snapshot is null, there are no users in DB. Clear local caches.
        debugPrint('getAllUsers: /users is empty, clearing cache');
      }

      // Update both in-memory list and storage cache with the fresh results
      _cachedUsers = users;
      await _persistCache();
      debugPrint('Fetched users: ${users.length}');
      return users;
    } catch (e) {
      // If we get an error (e.g. offline, permission error), fallback to cached data
      debugPrint(
        'getAllUsers failed ($e), returning cache (${_cachedUsers.length})',
      );
      return List.from(_cachedUsers);
    }
  }

  /// Active stream of users database node via REST API.
  Stream<List<Map<String, dynamic>>> get usersStream {
    return Stream.periodic(const Duration(seconds: 10)).asyncMap((_) async {
      try {
        final response = await http
            .get(Uri.parse('$_dbUrl/users.json'))
            .timeout(const Duration(seconds: 10));
        final list = <Map<String, dynamic>>[];

        if (response.statusCode == 200 && response.body != 'null') {
          final raw = json.decode(response.body);
          if (raw is Map) {
            raw.forEach((k, v) {
              if (v is Map) {
                list.add({
                  'uid': k.toString(),
                  'email': (v['user_email'] ?? '').toString(),
                  'role': (v['role'] ?? '').toString(),
                });
              }
            });
          }
        }
        return list;
      } catch (e) {
        debugPrint('REST usersStream error: $e');
        return <Map<String, dynamic>>[];
      }
    });
  }

  /// Updates the valve state in Firebase using HTTP REST API (bypasses blocked WebSocket).
  /// - Flutter UI reads from: /device_control/filling_valve, /device_control/outgoing_valve
  /// - Arduino reads from:    /valveControl/input, /valveControl/output
  Future<void> toggleValve(String key, bool value) async {
    debugPrint('Attempting to toggle valve via REST: $key to $value');
    try {
      final uiUpdates = <String, dynamic>{};
      final arduinoUpdates = <String, dynamic>{};

      if (key == 'filling_valve') {
        if (value) {
          // Turning Inlet Valve ON:
          // PATCH device_control: { filling_valve: true, is_filling: true, outgoing_valve: false, is_wasting: false }
          // PATCH valveControl: { input: true, output: false }
          uiUpdates['filling_valve'] = true;
          uiUpdates['is_filling'] = true;
          uiUpdates['outgoing_valve'] = false;
          uiUpdates['is_wasting'] = false;
          arduinoUpdates['input'] = true;
          arduinoUpdates['output'] = false;

          // Store baseline in app memory (Section 4 & Section 2)
          try {
            final sensorResp = await http
                .get(Uri.parse('$_dbUrl/sensorData.json'))
                .timeout(const Duration(seconds: 5));
            if (sensorResp.statusCode == 200 && sensorResp.body != 'null') {
              final sensorData = json.decode(sensorResp.body);
              _lastOpenedFilling =
                  (sensorData['intakeFlow'] ?? 0.0).toDouble();
            }
          } catch (e) {
            debugPrint('Failed to save _lastOpenedFilling: $e');
          }
        } else {
          // Turning Inlet Valve OFF:
          // PATCH device_control: { filling_valve: false, is_filling: false }
          // PATCH valveControl: { input: false }
          uiUpdates['filling_valve'] = false;
          uiUpdates['is_filling'] = false;
          arduinoUpdates['input'] = false;

          try {
            final responses = await Future.wait([
              http.get(Uri.parse('$_dbUrl/sensorData.json')),
              http.get(Uri.parse('$_dbUrl/device_control.json')),
            ]).timeout(const Duration(seconds: 5));

            final sensorResp = responses[0];
            final deviceResp = responses[1];

            if (sensorResp.statusCode == 200 && sensorResp.body != 'null') {
              final sensorData = json.decode(sensorResp.body);
              final deviceData =
                  deviceResp.statusCode == 200 && deviceResp.body != 'null'
                  ? json.decode(deviceResp.body)
                  : {};

              final double currentIntake =
                  (sensorData['intakeFlow'] ?? 0.0).toDouble();
              double sessionFilled = currentIntake - _lastOpenedFilling;

              // Fallback if app restarted while valve was open
              if (sessionFilled < 0 || _lastOpenedFilling == 0.0) {
                sessionFilled = currentIntake;
              }

              final double baseLevel =
                  (deviceData['base_tank_level'] ?? deviceData['current_level_liters'] ?? 0.0)
                      .toDouble();
              final double newBase = baseLevel + sessionFilled;

              uiUpdates['base_tank_level'] = newBase;
              uiUpdates['current_level_liters'] = newBase;

              // POST to history/filling.json
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              await http.post(
                Uri.parse('$_dbUrl/history/filling.json'),
                body: json.encode({
                  'timestamp': timestamp,
                  'liters_filled': sessionFilled,
                }),
              ).timeout(const Duration(seconds: 5));
            }
          } catch (e) {
            debugPrint('Failed to record filling history: $e');
          }
        }
      } else if (key == 'outgoing_valve') {
        if (value) {
          // Turning Outlet Valve ON:
          // PATCH device_control: { outgoing_valve: true, is_wasting: true, filling_valve: false, is_filling: false }
          // PATCH valveControl: { output: true, input: false }
          uiUpdates['outgoing_valve'] = true;
          uiUpdates['is_wasting'] = true;
          uiUpdates['filling_valve'] = false;
          uiUpdates['is_filling'] = false;
          arduinoUpdates['output'] = true;
          arduinoUpdates['input'] = false;

          // Store baseline in app memory (Section 4 & Section 3)
          try {
            final sensorResp = await http
                .get(Uri.parse('$_dbUrl/sensorData.json'))
                .timeout(const Duration(seconds: 5));
            if (sensorResp.statusCode == 200 && sensorResp.body != 'null') {
              final sensorData = json.decode(sensorResp.body);
              _lastOpenedUsage =
                  (sensorData['dailyUsage'] ?? 0.0).toDouble();
            }
          } catch (e) {
            debugPrint('Failed to save _lastOpenedUsage: $e');
          }
        } else {
          // Turning Outlet Valve OFF:
          // PATCH device_control: { outgoing_valve: false, is_wasting: false }
          // PATCH valveControl: { output: false }
          uiUpdates['outgoing_valve'] = false;
          uiUpdates['is_wasting'] = false;
          arduinoUpdates['output'] = false;

          try {
            final responses = await Future.wait([
              http.get(Uri.parse('$_dbUrl/sensorData.json')),
              http.get(Uri.parse('$_dbUrl/device_control.json')),
            ]).timeout(const Duration(seconds: 5));

            final sensorResp = responses[0];
            final deviceResp = responses[1];

            if (sensorResp.statusCode == 200 && sensorResp.body != 'null') {
              final sensorData = json.decode(sensorResp.body);
              final deviceData =
                  deviceResp.statusCode == 200 && deviceResp.body != 'null'
                  ? json.decode(deviceResp.body)
                  : {};

              final double currentOutput =
                  (sensorData['dailyUsage'] ?? 0.0).toDouble();
              double sessionUsage = currentOutput - _lastOpenedUsage;

              // Fallback if app restarted while valve was open
              if (sessionUsage < 0 || _lastOpenedUsage == 0.0) {
                sessionUsage = currentOutput;
              }

              final double baseLevel =
                  (deviceData['base_tank_level'] ?? deviceData['current_level_liters'] ?? 0.0)
                      .toDouble();
              double newBase = baseLevel - sessionUsage;
              if (newBase < 0) newBase = 0.0;

              uiUpdates['base_tank_level'] = newBase;
              uiUpdates['current_level_liters'] = newBase;

              // POST to history/wastage.json
              final timestamp = DateTime.now().millisecondsSinceEpoch;
              await http.post(
                Uri.parse('$_dbUrl/history/wastage.json'),
                body: json.encode({
                  'timestamp': timestamp,
                  'liters_wasted': sessionUsage,
                }),
              ).timeout(const Duration(seconds: 5));
            }
          } catch (e) {
            debugPrint('Failed to record usage history: $e');
          }
        }
      }

      if (uiUpdates.isNotEmpty) {
        final futures = <Future>[
          http.patch(
            Uri.parse('$_dbUrl/device_control.json'),
            body: json.encode(uiUpdates),
          ),
          http.patch(
            Uri.parse('$_dbUrl/valveControl.json'),
            body: json.encode(arduinoUpdates),
          ),
        ];

        await Future.wait(futures).timeout(const Duration(seconds: 10));
        debugPrint('REST: Updated device_control: $uiUpdates');
        debugPrint('REST: Updated valveControl: $arduinoUpdates');
      }
    } catch (e) {
      debugPrint('REST toggle error: $e');
    }
  }

  /// Helper to ensure the base device control variables exist in the database upon user login.
  /// Only sets default values if the node doesn't already exist - preserves existing sensor data.
  Future<void> _ensureDeviceControlNode() async {
    try {
      // Check if the device_control node already has data via REST API
      final response = await http
          .get(Uri.parse('$_dbUrl/device_control.json'))
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.body == 'null') {
        // Only create with default values if the node is completely missing
        await http
            .put(
              Uri.parse('$_dbUrl/device_control.json'),
              body: json.encode({
                'current_level_liters': 0.0,
                'base_tank_level': 0.0,
                'is_filling': false,
                'is_wasting': false,
                'filling_valve': false,
                'outgoing_valve': false,
              }),
            )
            .timeout(const Duration(seconds: 5));
        debugPrint(
          'device_control node initialized with default values via REST',
        );
      } else {
        debugPrint(
          'device_control node already exists, preserving existing data',
        );
      }
    } catch (e) {
      debugPrint('Failed to initialize device_control via REST: $e');
    }
  }
}
