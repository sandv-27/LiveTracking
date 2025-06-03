import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

const String openRouteServiceApiKey =
    '5b3ce3597851110001cf6248e9dccc78e1b348eda70807ab17839d08'; // Replace this!

class GoogleMapPage extends StatefulWidget {
  @override
  _GoogleMapPageState createState() => _GoogleMapPageState();
}

class _GoogleMapPageState extends State<GoogleMapPage> {
  Completer<GoogleMapController> _controller = Completer();
  GoogleMapController? _mapController;
  final Set<Marker> _markers = {};
  final Set<Polyline> _polylines = {};
  LatLng? _currentPosition;
  LatLng? _destinationPosition;

  @override
  void initState() {
    super.initState();
    _checkLocationPermission();
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
    Geolocator.getPositionStream(
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
    _markers.removeWhere((m) => m.markerId == MarkerId('user'));
    _markers.add(
      Marker(
        markerId: MarkerId('user'),
        position: _currentPosition!,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        infoWindow: InfoWindow(title: 'You'),
      ),
    );
  }

  void _addDestinationMarker(LatLng position) {
    _markers.removeWhere((m) => m.markerId == MarkerId('destination'));
    _markers.add(
      Marker(
        markerId: MarkerId('destination'),
        position: position,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        infoWindow: InfoWindow(title: 'Destination'),
      ),
    );
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
            polylineId: PolylineId('route'),
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
            title: Text("Enter Destination"),
            content: TextField(
              controller: controller,
              decoration: InputDecoration(hintText: "Type destination address"),
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
                child: Text("Search"),
              ),
            ],
          ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Search & Navigate'),
        actions: [
          IconButton(icon: Icon(Icons.search), onPressed: _handleSearch),
        ],
      ),
      body: GoogleMap(
        initialCameraPosition: CameraPosition(
          target: LatLng(10.0150, 76.2300),
          zoom: 14,
        ),
        myLocationEnabled: true,
        myLocationButtonEnabled: true,
        onMapCreated: (GoogleMapController controller) {
          _controller.complete(controller);
          _mapController = controller;
        },
        markers: _markers,
        polylines: _polylines,
      ),
    );
  }
}
