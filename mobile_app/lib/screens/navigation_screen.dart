import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers.dart';
import '../models/search_result.dart';
import '../models/speed_zone.dart';
import '../models/hazard.dart';

class NavigationScreen extends ConsumerStatefulWidget {
  const NavigationScreen({super.key});

  @override
  ConsumerState<NavigationScreen> createState() => _NavigationScreenState();
}

class _NavigationScreenState extends ConsumerState<NavigationScreen> {
  final MapController _mapController = MapController();
  LatLng _currentPosition = LatLng(37.7749, -122.4194);
  double _currentHeading = 0.0;
  double _currentSpeed = 0.0; 
  bool _hasPermissions = false;
  String _locationStatus = "Waiting for GPS..."; // Debug status
  
  // Search State
  bool _isSearching = false;
  List<SearchResult> _searchResults = [];
  
  // Navigation State
  List<LatLng> _routePoints = [];
  bool _isNavigating = false;
  
  // Alerts
  List<SpeedZone> _speedZones = [];
  String? _activeAlert;

  // Authority Mode
  bool _isAuthority = false;
  
  // Map Type
  bool _isSatellite = false;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
    _loadSpeedZones();
  }

  Future<void> _loadSpeedZones() async {
    try {
      final zones = await ref.read(apiServiceProvider).getSpeedZones();
      setState(() {
        _speedZones = zones;
      });
    } catch (e) {
      print("Error loading speed zones: $e");
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _locationStatus = "Checking permissions...");
    
    if (kIsWeb) {
      try {
        // Check service enabled first
        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
        if (!serviceEnabled) {
          setState(() => _locationStatus = "GPS Service Disabled (Browser)");
          return;
        }

        LocationPermission permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.denied) {
          permission = await Geolocator.requestPermission();
          if (permission == LocationPermission.denied) {
             setState(() => _locationStatus = "Permission Denied");
             return;
          }
        }
        
        if (permission == LocationPermission.deniedForever) {
           setState(() => _locationStatus = "Permission Denied Forever (Blocked)");
           return;
        }
        
        setState(() {
           _hasPermissions = true;
           _locationStatus = "Permission Granted. Acquiring Fix...";
        });
        
        // Skip explicit initial fix on Web to avoid JS Interop crashes (TypeError)
        // We will rely on _startLocationStream to pick it up.
        setState(() {
           _locationStatus = "Waiting for Stream update...";
        });
        
        _startLocationStream();
      } catch (e) {
         setState(() => _locationStatus = "GPS Error: $e");
         print("GPS Error: $e");
      }
    } else {
      // Mobile logic (simplified for brevity context, but keeping existing structure if needed)
      // ... existing mobile logic stays mostly same but updates status ...
      // For now, let's just focus on verifying the Web part properly replaces the block.
      // But to be safe and clean, let's just replicate the key parts or assume existing else block is fine?
      // The tool requires exact match, so I must replace the WHOLE function if I touched the top.
      
      // ... (Re-implementing Mobile Logic for Replacement)
      Map<Permission, PermissionStatus> statuses = await [
        Permission.location,
        Permission.locationWhenInUse,
      ].request();

      if (statuses[Permission.location]!.isGranted || statuses[Permission.locationWhenInUse]!.isGranted) {
        setState(() {
          _hasPermissions = true;
          _locationStatus = "Mobile Permission Granted";
        });
        _startLocationStream();
      } else {
         setState(() => _locationStatus = "Mobile Permission Denied");
      }
    }
  }

  void _startLocationStream() {
    final LocationSettings locationSettings = kIsWeb 
        ? const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 0)
        : const LocationSettings(accuracy: LocationAccuracy.bestForNavigation, distanceFilter: 0);

    Geolocator.getPositionStream(locationSettings: locationSettings).listen(
      (Position position) {
        final pos = LatLng(position.latitude, position.longitude);
        setState(() {
          _currentPosition = pos;
          _currentHeading = position.heading;
          _currentSpeed = position.speed * 3.6; // m/s to km/h
          _checkSpeedLimit(pos, _currentSpeed);
        });
        
        if (_isNavigating && !_isAuthority) {
          _mapController.move(pos, 18.0);
        }
      });
  }

  void _checkSpeedLimit(LatLng pos, double speed) {
    if (_isAuthority) return; // No alerts for authority mode

    String? newAlert;
    for (var zone in _speedZones) {
      final distance = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, 
        zone.lat, zone.lng
      );
      if (distance < zone.radius) {
         if (speed > zone.limit) {
           newAlert = "Reduce speed to ${zone.limit} km/h";
         }
      }
    }
    
    final hazards = ref.read(hazardsProvider);
    for (var hazard in hazards) {
       final distance = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, 
        hazard.lat, hazard.lng
      );
      if (distance < 200) { 
        newAlert = "Road Hazard Ahead!";
      }
    }

    if (newAlert != _activeAlert) {
      setState(() {
        _activeAlert = newAlert;
      });
    }
  }

  void _handleMapTap(TapPosition tapPosition, LatLng point) {
    if (_isAuthority) {
       _showReportHazardDialog(point, "authority_hazard");
    }
  }

  Future<void> _performSearch(String query) async {
    setState(() => _isSearching = true);
    try {
      final results = await ref.read(apiServiceProvider).searchPlaces(
        query, 
        lat: _currentPosition.latitude, 
        lng: _currentPosition.longitude
      );
      setState(() {
         _searchResults = results;
         _isSearching = false; // Stop spinner
      });
    } catch (e) {
      setState(() => _isSearching = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Search failed: $e")));
    }
  }

  // ... inside _startNavigation
  Future<void> _startNavigation(SearchResult result) async {
    setState(() {
      _isSearching = false;
      _searchResults = [];
    });
    
    try {
      // Get Routes (potentially multiple)
      final routes = await ref.read(apiServiceProvider).getRoutes(
        _currentPosition, 
        LatLng(result.lat, result.lng)
      );
      
      print("Routes found: ${routes.length}");
      
      if (routes.isEmpty) return;

      // Smart Rerouting Logic:
      // If primary route (index 0) has a hazard, pick alternate (index 1) if available
      List<LatLng> bestRoute = routes[0];
      final hazards = ref.read(hazardsProvider);
      
      bool primaryHasHazard = _routeIntersectsHazards(bestRoute, hazards);
      print("Primary route has hazard: $primaryHasHazard");
      
      if (primaryHasHazard && routes.length > 1) {
         bestRoute = routes[1]; // Pick alternate
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hazard on route! Switching to alternate.")));
      } else if (primaryHasHazard) {
         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Caution: Hazard on route. No alternate available.")));
      } else {
         print("No hazards on primary route.");
      }

      setState(() {
        _routePoints = bestRoute;
        _isNavigating = true;
      });
      _mapController.move(_currentPosition, 18.0);
      
    } catch (e) {
      print("Navigation error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Routing failed: $e")));
    }
  }
  
  bool _routeIntersectsHazards(List<LatLng> route, List<Hazard> hazards) {
    // Check coverage every 10 points
    for (var hazard in hazards) {
      for (int i = 0; i < route.length; i += 10) {
        final dist = Geolocator.distanceBetween(
          hazard.lat, hazard.lng, 
          route[i].latitude, route[i].longitude
        );
        // Increased radius to 150m for demo visibility
        if (dist < 150) {
           print("Hazard intersects route! Dist: $dist");
           return true;
        }
      }
    }
    return false;
  }

  void _handleHazardTap(Hazard hazard) {
    if (_isAuthority) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Remove Hazard?"),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text("Tag: ${hazard.tag}"),
              Text("Description: ${hazard.description}"),
              const SizedBox(height: 10),
              const Text("Do you want to delete this hazard?"),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
            TextButton(
              onPressed: () {
                ref.read(hazardsProvider.notifier).removeHazard(hazard.id);
                Navigator.pop(ctx);
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    } else {
      // For normal users, show details
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(hazard.tag),
          content: Text(hazard.description),
          actions: [
             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Close")),
          ],
        ),
      );
    }
  }

  void _handleMapLongPress(TapPosition tapPosition, LatLng point) {
    // Hidden feature: Manual Teleport (useful for Demo/Web if GPS is bad)
    setState(() {
      _currentPosition = point;
      _locationStatus = "Manual Location Set";
      // Check hazards/speed limits at new location
      _checkSpeedLimit(_currentPosition, _currentSpeed);
    });
    _mapController.move(_currentPosition, 18.0);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Location Updated (Manual)")));
  }

  Future<void> _showReportHazardDialog(LatLng pos, String type) async {
     String selectedTag = "Pothole";
     final descController = TextEditingController();
     
     await showDialog(
       context: context,
       builder: (ctx) => StatefulBuilder(
         builder: (context, setState) => AlertDialog(
           title: const Text("Report Hazard"),
           content: Column(
             mainAxisSize: MainAxisSize.min,
             children: [
               DropdownButtonFormField<String>(
                 value: selectedTag,
                 items: ["Pothole", "Accident", "Road Closure", "Construction", "Other"]
                     .map((t) => DropdownMenuItem(value: t, child: Text(t))).toList(),
                 onChanged: (val) => setState(() => selectedTag = val!),
                 decoration: const InputDecoration(labelText: "Tag"),
               ),
               TextField(
                 controller: descController,
                 decoration: const InputDecoration(labelText: "Description"),
               ),
             ],
           ),
           actions: [
             TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
             ElevatedButton(
               onPressed: () {
                 ref.read(hazardsProvider.notifier).addHazard(
                   pos.latitude, 
                   pos.longitude, 
                   type,
                   selectedTag,
                   descController.text
                 );
                 Navigator.pop(ctx);
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hazard Reported!")));
               },
               child: const Text("Submit"),
             ),
           ],
         ),
       ),
     );
  }

  Future<void> _showLoginDialog() async {
    final usernameController = TextEditingController();
    final passwordController = TextEditingController();

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Authority Login"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: usernameController, decoration: const InputDecoration(labelText: "Username")),
            TextField(controller: passwordController, decoration: const InputDecoration(labelText: "Password"), obscureText: true),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              if (usernameController.text == "admin" && passwordController.text == "admin123") {
                setState(() => _isAuthority = true);
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Logged in as Authority")));
              } else {
                 ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid Credentials")));
              }
            },
            child: const Text("Login"),
          ),
        ],
      ),
    );
  }

  // ... build method changes for UI
  @override
  Widget build(BuildContext context) {
    final hazards = ref.watch(hazardsProvider);
    
    return Scaffold(
      // ... AppBar / Drawer same as before ... 
      appBar: _isAuthority ? AppBar(title: const Text("Authority Mode"), backgroundColor: Colors.orange) : null,
      drawer: Drawer(
        child: ListView(
          children: [
            const DrawerHeader(child: Text("SafeRoute MVP")),
            ListTile(
              title: const Text("Driver Mode"),
              onTap: () {
                setState(() => _isAuthority = false);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text("Authority Mode"),
              onTap: () {
                Navigator.pop(context);
                if (!_isAuthority) _showLoginDialog();
              },
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _currentPosition,
              initialZoom: 15.0,
              initialRotation: 0.0,
              onTap: _handleMapTap,
              onLongPress: _handleMapLongPress, // Manual Teleport for Debug/Demo
            ),
            children: [
               TileLayer(
                urlTemplate: _isSatellite 
                    ? 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}'
                    : 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.saferoute',
              ),
              // Attribution for Satellite
              if (_isSatellite)
                const RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution(
                      'Tiles © Esri — Source: Esri, i-cubed, USDA, USGS, AEX, GeoEye, Getmapping, Aerogrid, IGN, IGP, UPR-EGP, and the GIS User Community',
                    ),
                  ],
                ),
              PolylineLayer(
                polylines: [
                  if (_routePoints.isNotEmpty)
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 5.0,
                      color: Colors.blue,
                    ),
                ],
              ),
              MarkerLayer(
                markers: [
                  // User
                  Marker(
                    point: _currentPosition,
                    width: 40,
                    height: 40,
                    child: Transform.rotate(
                      angle: _currentHeading * (3.14159 / 180),
                      child: const Icon(Icons.navigation, color: Colors.blue, size: 40),
                    ),
                  ),
                  // Hazards
                  ...hazards.map((h) => Marker(
                    point: LatLng(h.lat, h.lng),
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => _handleHazardTap(h),
                      child: Tooltip(
                        message: "${h.tag}: ${h.description}",
                        child: Icon(Icons.warning, color: h.type == 'authority_hazard' ? Colors.purple : Colors.red, size: 30),
                      ),
                    ),
                  )),
                ],
              ),
            ],
          ),
          
          // ... Alerts UI ...
          if (_activeAlert != null)
             Positioned(
              top: 100,
              left: 20,
              right: 20,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _activeAlert!,
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  textAlign: TextAlign.center,
                ),
              ),
            ),

          // ... Search Box ...
          if (!_isAuthority)
          Positioned(
            top: 50,
            left: 16,
            right: 16,
            child: Column(
              children: [
                Card(
                  elevation: 4,
                  child: Row(
                    children: [
                      Builder(builder: (context) => IconButton(
                        icon: const Icon(Icons.menu),
                        onPressed: () => Scaffold.of(context).openDrawer(),
                      )),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 16.0),
                          child: TextField(
                            decoration: const InputDecoration(
                              hintText: "Search Place...",
                              border: InputBorder.none,
                            ),
                            onSubmitted: _performSearch,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: _isSearching 
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.search), 
                        onPressed: () {}
                      ),
                    ],
                  ),
                ),
                if (_searchResults.isNotEmpty)
                  Container(
                    color: Colors.white,
                    constraints: const BoxConstraints(maxHeight: 200),
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _searchResults.length,
                      itemBuilder: (ctx, i) {
                        final r = _searchResults[i];
                        return ListTile(
                          title: Text(r.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _startNavigation(r),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          
           // Authority Menu Button
           if (_isAuthority)
             Positioned(
               top: 50,
               left: 16,
               child: Builder(builder: (context) => CircleAvatar(
                 backgroundColor: Colors.white,
                 child: IconButton(
                    icon: const Icon(Icons.menu),
                    onPressed: () => Scaffold.of(context).openDrawer(),
                 ),
               )),
             ),

          // Info Panel with Safe Area
          if (!_isAuthority)
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [BoxShadow(blurRadius: 10, color: Colors.black12)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${_currentSpeed.toStringAsFixed(0)} km/h",
                              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                            ),
                            const Text("Current Speed"),
                            Text(
                              "${_currentPosition.latitude.toStringAsFixed(4)}, ${_currentPosition.longitude.toStringAsFixed(4)}",
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            Container(
                              padding: const EdgeInsets.all(4),
                              color: Colors.black12,
                              child: Text(
                                "GPS: $_locationStatus",
                                style: const TextStyle(fontSize: 10, color: Colors.red),
                                textAlign: TextAlign.center,
                              ),
                            ),
                            if (_locationStatus.contains("Error") || _locationStatus.contains("Denied"))
                              ElevatedButton(
                                onPressed: _checkPermissions, 
                                child: const Text("Retry GPS")
                              ),
                          ],
                        ),
                        FloatingActionButton(
                          onPressed: () {
                             _showReportHazardDialog(_currentPosition, "user_report");
                          },
                          backgroundColor: Colors.orange,
                          child: const Icon(Icons.add_alert),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Map Type Toggle
                        FloatingActionButton(
                          heroTag: "mapType",
                          mini: true,
                          backgroundColor: Colors.white,
                          onPressed: () => setState(() => _isSatellite = !_isSatellite),
                          child: Icon(_isSatellite ? Icons.map : Icons.satellite_alt, color: Colors.blueGrey),
                        ),
                        const SizedBox(width: 8),
                        Expanded(child: SizedBox(
                          child: ElevatedButton(
                            onPressed: () {
                               _mapController.move(_currentPosition, 18.0);
                            },
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                            child: const Text("Re-center Camera"),
                          ),
                        )),
                      ]
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
