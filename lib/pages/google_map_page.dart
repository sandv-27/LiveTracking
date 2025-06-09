import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String openRouteServiceApiKey = 'YOUR_ORS_API_KEY_HERE';

class GoogleMapPage extends StatefulWidget {
  const GoogleMapPage({super.key});

  @override
  _GoogleMapPageState createState() => _GoogleMapPageState();
}

class _GoogleMapPageState extends State<GoogleMapPage> {
  late final String _deviceId;
  bool _isLoading = true;

  final Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _currentPosition;
  LatLng? _destinationPosition;

  final DatabaseReference _historyRef = FirebaseDatabase.instance.ref("tracks");
  final DatabaseReference _lastRef = FirebaseDatabase.instance.ref(
    "lastLocations",
  );

  StreamSubscription<Position>? _positionSubscription;
  StreamSubscription<DatabaseEvent>? _lastRefSubscription;

  @override
  void initState() {
    super.initState();
    _initDeviceIdAndSetup();
  }

  Future<void> _initDeviceIdAndSetup() async {
    _deviceId = await _getDeviceId();
    // Now _deviceId is ready — start permission check and Firebase listeners
    await _checkLocationPermission();
    _startListeningToOtherUsers();

    setState(() {
      _isLoading = false;
    });
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('deviceId');
    if (id == null) {
      id = const Uuid().v4();
      await prefs.setString('deviceId', id);
    }
    return id;
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      await Geolocator.openLocationSettings();
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) return;
    }

    if (permission == LocationPermission.deniedForever) return;

    _startLocationUpdates();
  }

  void _startLocationUpdates() {
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: 10,
      ),
    ).listen((Position position) async {
      LatLng newPosition = LatLng(position.latitude, position.longitude);
      setState(() {
        _currentPosition = newPosition;
        _updateUserMarker();
      });

      final pointData = {
        'lat': newPosition.latitude,
        'lng': newPosition.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      };

      _historyRef.child(_deviceId).push().set(pointData);
      _lastRef.child(_deviceId).set(pointData);

      if (_destinationPosition != null) {
        await _fetchRouteFromOpenRouteService(
          newPosition,
          _destinationPosition!,
        );
      }

      _moveCameraToPosition(newPosition);
    });
  }

  void _updateUserMarker() {
    if (_currentPosition == null) return;
    _markers.removeWhere((m) => m.markerId.value == 'user');
    _markers.add(
      Marker(
        markerId: MarkerId('user'),
        position: _currentPosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: const InfoWindow(title: 'You'),
      ),
    );
  }

  void _startListeningToOtherUsers() {
    _lastRefSubscription = _lastRef.onValue.listen((event) {
      final data = event.snapshot.value as Map<dynamic, dynamic>?;

      if (data != null) {
        setState(() {
          _markers.removeWhere(
            (m) =>
                m.markerId.value != 'user' && m.markerId.value != 'destination',
          );

          data.forEach((deviceId, value) {
            if (deviceId == _deviceId) return; // skip self
            if (value is Map) {
              final lat = value['lat'];
              final lng = value['lng'];
              if (lat != null && lng != null) {
                _markers.add(
                  Marker(
                    markerId: MarkerId(deviceId),
                    position: LatLng(lat, lng),
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueGreen,
                    ),
                    infoWindow: InfoWindow(title: 'User $deviceId'),
                  ),
                );
              }
            }
          });
        });
      }
    });
  }

  Future<void> _fetchRouteFromOpenRouteService(
    LatLng origin,
    LatLng destination,
  ) async {
    final url =
        'https://api.openrouteservice.org/v2/directions/driving-car/geojson';
    final headers = {
      'Authorization': openRouteServiceApiKey,
      'Content-Type': 'application/json',
    };
    final body = jsonEncode({
      'coordinates': [
        [origin.longitude, origin.latitude],
        [destination.longitude, destination.latitude],
      ],
    });

    final response = await http.post(
      Uri.parse(url),
      headers: headers,
      body: body,
    );

    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      final List<dynamic> coords =
          data['features'][0]['geometry']['coordinates'];

      final List<LatLng> polylineCoords =
          coords.map<LatLng>((coord) => LatLng(coord[1], coord[0])).toList();

      setState(() {
        _polylines.clear();
        _polylines.add(
          Polyline(
            polylineId: const PolylineId('route'),
            points: polylineCoords,
            color: Colors.blue,
            width: 5,
          ),
        );
      });
    } else {
      print("ORS error: ${response.statusCode} ${response.body}");
    }
  }

  void _moveCameraToPosition(LatLng position) {
    _mapController?.animateCamera(CameraUpdate.newLatLng(position));
  }

  Future<void> _handleSearch() async {
    final TextEditingController controller = TextEditingController();

    await showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text("Enter Destination"),
            content: TextField(
              controller: controller,
              decoration: const InputDecoration(
                hintText: "Type destination address",
              ),
            ),
            actions: [
              TextButton(
                onPressed: () async {
                  final query = controller.text;
                  Navigator.of(context).pop();
                  if (query.isEmpty) return;

                  final encodedQuery = Uri.encodeComponent(query);
                  final url =
                      'https://nominatim.openstreetmap.org/search?q=$encodedQuery&format=json&limit=1';

                  final response = await http.get(
                    Uri.parse(url),
                    headers: {
                      'User-Agent': 'MyFlutterApp/1.0 (myemail@example.com)',
                    },
                  );

                  if (response.statusCode == 200) {
                    final results = json.decode(response.body);
                    if (results.isNotEmpty) {
                      final lat = double.parse(results[0]['lat']);
                      final lon = double.parse(results[0]['lon']);
                      final destination = LatLng(lat, lon);

                      setState(() {
                        _destinationPosition = destination;
                        _addDestinationMarker(destination);
                      });

                      if (_currentPosition != null) {
                        await _fetchRouteFromOpenRouteService(
                          _currentPosition!,
                          destination,
                        );
                        _moveCameraToPosition(destination);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text("No location found for '$query'"),
                        ),
                      );
                    }
                  }
                },
                child: const Text("Search"),
              ),
            ],
          ),
    );
  }

  void _addDestinationMarker(LatLng position) {
    _markers.removeWhere((m) => m.markerId == MarkerId('destination'));
    _markers.add(
      Marker(
        markerId: const MarkerId('destination'),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: const InfoWindow(title: 'Destination'),
      ),
    );
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _lastRefSubscription?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Search & Navigate'),
        actions: [
          IconButton(icon: const Icon(Icons.search), onPressed: _handleSearch),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: const CameraPosition(
          target: LatLng(10.0150, 76.2300),
          zoom: 14,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (controller) {
          _controller.complete(controller);
          _mapController = controller;
        },
        markers: _markers,
        polylines: _polylines,
      ),
    );
  }
}
