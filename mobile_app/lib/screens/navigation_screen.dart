import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'dart:async'; // Added for Timer
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import '../providers.dart';
import '../models/search_result.dart';
import '../models/speed_zone.dart';
import '../models/hazard.dart';
import '../models/route_data.dart';
import '../models/route_step.dart';

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
  int? _currentLimit; // Stores current speed limit
  bool _hasPermissions = false; // Permission status
  String _locationStatus = "Waiting for GPS..."; 
  bool _isManualLocation = false; // Prevents GPS override
  
  // Search State
  final TextEditingController _searchController = TextEditingController();
  bool _isSearching = false;
  List<SearchResult> _searchResults = [];
  
  // Navigation State
  RouteData? _currentRoute; 
  bool _isNavigating = false;
  bool _isPreviewing = false; // New state for Route Preview
  bool _showDirections = false;
  
  // Simulation State
  Timer? _simulationTimer;
  int _simulationIndex = 0;
  
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

  @override
  void dispose() {
    _searchController.dispose();
    _stopSimulation();
    super.dispose();
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
        if (_isManualLocation) return; // Ignore GPS if manual set

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
    
    int? detectedLimit;

    String? newAlert;
    for (var zone in _speedZones) {
      final distance = Geolocator.distanceBetween(
        pos.latitude, pos.longitude, 
        zone.lat, zone.lng
      );
      if (distance < zone.radius) {
         detectedLimit = zone.limit;
         if (speed > zone.limit) {
           newAlert = "Reduce speed to ${zone.limit} km/h";
         }
      }
    }
    
    // Update Limit State
    if (detectedLimit != _currentLimit) {
       setState(() => _currentLimit = detectedLimit);
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
    // Dismiss keyboard and close search results (if logic required)
    FocusScope.of(context).unfocus();
    
    if (_isAuthority) {
       _showReportHazardDialog(point, "authority_hazard");
    } else {
       // Driver Mode: Tap to navigate
        // Create a temporary SearchResult. address is map of string->dynamic
        final tempResult = SearchResult(
          displayName: "Selected Location", 
          lat: point.latitude, 
          lng: point.longitude,
        );
        _startNavigation(tempResult);
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
      final vehicleType = ref.read(vehicleTypeProvider);
      // Get Routes (potentially multiple)
      final routes = await ref.read(apiServiceProvider).getRoutes(
        _currentPosition, 
        LatLng(result.lat, result.lng),
        vehicleType: vehicleType,
      );
      
      print("Routes found: ${routes.length}");
      
      if (routes.isEmpty) return;

      // Smart Rerouting Logic:
      // If primary route (index 0) has a hazard, pick alternate (index 1) if available
      RouteData bestRoute = routes[0];
      final hazards = ref.read(hazardsProvider);
      
      bool primaryHasHazard = _routeIntersectsHazards(bestRoute.points, hazards);
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
        _currentRoute = bestRoute;
        _isNavigating = false; // Wait for "Start Trip"
        _isPreviewing = true;  // Show Preview UI
        _showDirections = false;
      });
      // Zoom out to show whole route? Or just user position?
      // Let's center on user first
      _mapController.move(_currentPosition, 16.0);
      // _startSimulation(); // Disabled per user request (Arrow should move with user)
      
    } catch (e) {
      print("Navigation error: $e");
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Routing failed: $e")));
    }
  }
  
  bool _routeIntersectsHazards(List<LatLng> route, List<Hazard> hazards) {
    // Check coverage every 10 points
    for (var hazard in hazards) {
      if (!hazard.verified && !_isAuthority) continue; // Skip unverified for routing check if not authority? 
      // Actually routing should probably avoid even unverified hazards for safety? 
      // Let's assume routing avoids verified hazards only for now to reduce noise.
      if (!hazard.verified) continue; 

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

  void _startSimulation() {
    _stopSimulation();
    if (_currentRoute == null || _currentRoute!.points.isEmpty) return;

    _simulationIndex = 0;
    // Find closest point on route to start? Or just start from beginning?
    // For demo, let's start from beginning or current index if close.
    // Let's just reset to 0 for simplicity of "Start Navigation"
    
    // Simulate movement
    _simulationTimer = Timer.periodic(const Duration(milliseconds: 1000), (timer) {
      if (!mounted) {
        _stopSimulation();
        return;
      }
      
      if (_currentRoute == null || _simulationIndex >= _currentRoute!.points.length - 1) {
        _stopSimulation();
        setState(() => _isNavigating = false); // End navigation
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Arrived at destination!")));
        return;
      }

      setState(() {
         // Move faster: skip points if dense
         int speedMultiplier = 3; 
         _simulationIndex = (_simulationIndex + speedMultiplier).clamp(0, _currentRoute!.points.length - 1);
         
         final nextPos = _currentRoute!.points[_simulationIndex];
         
         // Calculate heading
         if (_simulationIndex > 0) {
           final prevPos = _currentRoute!.points[_simulationIndex - speedMultiplier < 0 ? 0 : _simulationIndex - speedMultiplier];
           _currentHeading = Geolocator.bearingBetween(prevPos.latitude, prevPos.longitude, nextPos.latitude, nextPos.longitude);
         }
         
         _currentPosition = nextPos;
         _currentSpeed = 45.0; // Simulated speed km/h
      });
      
      _mapController.move(_currentPosition, 18.0);
      _checkSpeedLimit(_currentPosition, _currentSpeed);
    });
  }

  void _stopSimulation() {
    _simulationTimer?.cancel();
    _simulationTimer = null;
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
              Text("Status: ${hazard.verified ? 'Verified' : 'Unverified'}", style: TextStyle(color: hazard.verified ? Colors.green : Colors.orange, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              
              if (!hazard.verified)
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                    onPressed: () async {
                       try {
                         await ref.read(apiServiceProvider).verifyHazard(hazard.id);
                         Navigator.pop(ctx);
                         ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hazard Verified!")));
                         // State update will happen via WebSocket or Poll, but let's assume we might need manual refresh if WS not perfect?
                         // WS should handle it.
                       } catch (e) {
                         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Verification failed: $e")));
                       }
                    },
                    child: const Text("Verify Hazard", style: TextStyle(color: Colors.white)),
                  ),
                ),
                
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
      _isManualLocation = true; // Lock location
      _locationStatus = "Manual Location Set (GPS Paused)";
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
    final vehicleType = ref.watch(vehicleTypeProvider);
    
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
                      'Tiles © Esri',
                    ),
                  ],
                ),
              PolylineLayer(
                polylines: [
                  if (_currentRoute != null)
                    Polyline(
                      points: _currentRoute!.points,
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
                  
                  
                  // Route Start/End Markers
                  if ((_isNavigating || _isPreviewing) && _currentRoute != null) ...[
                     // Start (Green Flag)
                     Marker(
                       point: _currentRoute!.points.first,
                       width: 40,
                       height: 40,
                       child: Container(
                         decoration: const BoxDecoration(
                           color: Colors.white, 
                           shape: BoxShape.circle,
                           boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black26)]
                         ),
                         child: const Icon(Icons.flag, color: Colors.green, size: 25),
                       ),
                     ),
                     // End (Red Flag)
                     Marker(
                       point: _currentRoute!.points.last,
                       width: 40,
                       height: 40,
                       child: Container(
                         decoration: const BoxDecoration(
                           color: Colors.white, 
                           shape: BoxShape.circle,
                           boxShadow: [BoxShadow(blurRadius: 5, color: Colors.black26)]
                         ),
                         child: const Icon(Icons.flag, color: Colors.red, size: 25),
                       ),
                     ),
                  ],

                  // Hazards
                  ...hazards.where((h) => _isAuthority || h.verified).map((h) => Marker(
                    point: LatLng(h.lat, h.lng),
                    width: 30,
                    height: 30,
                    child: GestureDetector(
                      onTap: () => _handleHazardTap(h),
                      child: Tooltip(
                        message: "${h.tag}: ${h.description} ${!h.verified ? '(Unverified)' : ''}",
                        child: Icon(
                          Icons.warning, 
                          color: h.type == 'authority_hazard' 
                              ? Colors.purple 
                              : (h.verified ? Colors.red : Colors.orange), 
                          size: 30
                        ),
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
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 4,
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Builder(builder: (context) => IconButton(
                            icon: const Icon(Icons.menu),
                            onPressed: () => Scaffold.of(context).openDrawer(),
                          )),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(right: 16.0),
                              child: TextField(
                                controller: _searchController,
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
                            onPressed: () {
                               if (_searchController.text.isNotEmpty) {
                                  _performSearch(_searchController.text);
                                  FocusScope.of(context).unfocus();
                               }
                            }
                          ),
                        ],
                      ),
                      // Vehicle Type Selector
                      if (!_isNavigating)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                          children: [
                            _buildVehicleButton(context, ref, 'car', Icons.directions_car),
                            _buildVehicleButton(context, ref, 'bike', Icons.directions_bike),
                            _buildVehicleButton(context, ref, 'foot', Icons.directions_walk),
                          ],
                        ),
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

          // Directions List Overlay
          if (_isNavigating && _showDirections && _currentRoute != null)
             Positioned(
               top: 180, 
               left: 16,
               right: 16,
               bottom: 120, // Leave space for bottom panel
               child: Container(
                 decoration: BoxDecoration(
                   color: Colors.white.withOpacity(0.95),
                   borderRadius: BorderRadius.circular(16),
                   boxShadow: const [BoxShadow(blurRadius: 10, color: Colors.black26)],
                 ),
                 child: Column(
                   children: [
                     Padding(
                       padding: const EdgeInsets.all(16.0),
                       child: Row(
                         mainAxisAlignment: MainAxisAlignment.spaceBetween,
                         children: [
                           Text("Directions (${_currentRoute!.steps.length} steps)", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                           IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _showDirections = false)),
                         ],
                       ),
                     ),
                     Divider(height: 1),
                     Expanded(
                       child: ListView.builder(
                         itemCount: _currentRoute!.steps.length,
                         itemBuilder: (ctx, i) {
                           final step = _currentRoute!.steps[i];
                           return ListTile(
                             leading: const Icon(Icons.turn_right), // Simplified icon
                             title: Text(step.instruction),
                             subtitle: Text("${step.distance.toStringAsFixed(0)} m"),
                           );
                         },
                       ),
                     ),
                   ],
                 ),
               ),
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
                    if (_isNavigating && _currentRoute != null)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Column(
                            children: [
                              Text("${(_currentRoute!.distance / 1000).toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                              const Text("Distance"),
                            ],
                          ),
                          Column(
                            children: [
                              Text("${(_currentRoute!.duration / 60).toStringAsFixed(0)} min", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.blue)),
                              const Text("ETA"),
                            ],
                          ),
                          // Current Speed & Limit display during Navigation
                          Column(
                            children: [
                               Text("${_currentSpeed.toStringAsFixed(0)}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 24)),
                               const Text("km/h", style: TextStyle(fontSize: 12)),
                               if (_currentLimit != null)
                                 Container(
                                   margin: const EdgeInsets.only(top: 4),
                                   padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                   decoration: BoxDecoration(
                                     border: Border.all(color: Colors.red, width: 2),
                                     borderRadius: BorderRadius.circular(4),
                                     color: Colors.white,
                                   ),
                                   child: Text("${_currentLimit}", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black)),
                                 ),
                            ],
                          ),
                          
                          Column(
                            children: [
                               ElevatedButton(
                                onPressed: () {
                                  setState(() {
                                    _showDirections = !_showDirections;
                                  });
                                }, 
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8), minimumSize: Size(40, 36)),
                                child: Icon(_showDirections ? Icons.list_alt : Icons.list),
                               ),
                                const SizedBox(height: 4),
                                ElevatedButton(
                                 style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                                 onPressed: () {
                                   setState(() {
                                     _isNavigating = false;
                                     _isPreviewing = false;
                                     _currentRoute = null;
                                     _showDirections = false;
                                     _stopSimulation();
                                   });
                                   ref.read(activeRouteProvider.notifier).clearRoute();
                                 },
                                 child: const Text("End Trip", style: TextStyle(color: Colors.white)),
                                ),
                            ],
                          )
                        ],
                      )
                    // Preview Mode UI
                    else if (_isPreviewing && _currentRoute != null)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                           Row(
                             mainAxisAlignment: MainAxisAlignment.spaceAround,
                             children: [
                                Column(
                                  children: [
                                    Text("${(_currentRoute!.distance / 1000).toStringAsFixed(1)} km", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20)),
                                    const Text("Distance"),
                                  ],
                                ),
                                Column(
                                  children: [
                                    Text("${(_currentRoute!.duration / 60).toStringAsFixed(0)} min", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 20, color: Colors.blue)),
                                    const Text("ETA"),
                                  ],
                                ),
                             ],
                           ),
                           const SizedBox(height: 10),
                           SizedBox(
                             width: double.infinity,
                             child: ElevatedButton(
                               style: ElevatedButton.styleFrom(
                                 backgroundColor: Colors.green, 
                                 padding: const EdgeInsets.symmetric(vertical: 12)
                               ),
                               onPressed: () {
                                 setState(() {
                                   _isPreviewing = false;
                                   _isNavigating = true;
                                 });
                               },
                               child: const Text("Start Trip", style: TextStyle(fontSize: 18, color: Colors.white, fontWeight: FontWeight.bold)),
                             ),
                           ),
                           TextButton(
                                onPressed: () {
                                  setState(() {
                                    _isPreviewing = false;
                                    _currentRoute = null;
                                  });
                                  ref.read(activeRouteProvider.notifier).clearRoute();
                                },
                                child: const Text("Cancel"),
                           ),
                        ],
                      )
                    else 
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  "${_currentSpeed.toStringAsFixed(0)} km/h",
                                  style: const TextStyle(fontSize: 48, fontWeight: FontWeight.bold),
                                ),
                                if (_currentLimit != null)
                                   Padding(
                                     padding: const EdgeInsets.only(left: 10),
                                     child: Container(
                                       width: 50,
                                       height: 60,
                                       decoration: BoxDecoration(
                                         color: Colors.white,
                                         border: Border.all(color: Colors.red, width: 4),
                                         borderRadius: BorderRadius.circular(8),
                                       ),
                                       child: Column(
                                         mainAxisAlignment: MainAxisAlignment.center,
                                         children: [
                                           const Text("LIMIT", style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold)),
                                           Text("${_currentLimit}", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                         ],
                                       ),
                                     ),
                                   ),
                              ],
                            ),
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
              ),
            ),
          ),
          
          // Floating Map Controls (Right Side)
          Positioned(
            right: 16,
            bottom: 200, // Above the info panel (adjust as needed)
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FloatingActionButton(
                  heroTag: "mapType",
                  mini: true,
                  backgroundColor: Colors.white,
                  onPressed: () => setState(() => _isSatellite = !_isSatellite),
                  child: Icon(_isSatellite ? Icons.map : Icons.satellite_alt, color: Colors.blueGrey),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "alert",
                  mini: true,
                  backgroundColor: Colors.orange,
                  onPressed: () => _showReportHazardDialog(_currentPosition, "user_report"),
                  child: const Icon(Icons.add_alert, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  heroTag: "recenter",
                  backgroundColor: Colors.white,
                  onPressed: () {
                     _mapController.move(_currentPosition, 18.0);
                     setState(() => _isManualLocation = false);
                  },
                  child: const Icon(Icons.my_location, color: Colors.blue),
                ),
              ],
            ),
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

  Widget _buildVehicleButton(BuildContext context, WidgetRef ref, String type, IconData icon) {
    final selected = ref.watch(vehicleTypeProvider) == type;
    return IconButton(
      icon: Icon(icon, color: selected ? Colors.blue : Colors.grey),
      onPressed: () {
        ref.read(vehicleTypeProvider.notifier).setType(type);
      },
      tooltip: type.toUpperCase(),
    );
  }
}
