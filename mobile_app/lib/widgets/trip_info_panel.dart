import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/route_data.dart';
import 'speedometer_gadget.dart';

class TripInfoPanel extends StatelessWidget {
  final bool isNavigating;
  final bool isPreviewing;
  final RouteData? currentRoute;
  final double currentSpeed;
  final int? currentLimit;
  final double distanceRemaining; // in meters
  final double durationRemaining; // in seconds
  final VoidCallback onStartTrip;
  final VoidCallback onEndTrip;
  final VoidCallback onCancelPreview;
  final VoidCallback onToggleDirections;
  final bool showDirections;
  final bool hasHazardOnRoute;
  final String selectedVehicleType;
  final Function(String) onVehicleTypeChanged;
  final Function(String) onCategorySelected;

  const TripInfoPanel({
    super.key,
    required this.isNavigating,
    required this.isPreviewing,
    required this.currentRoute,
    required this.currentSpeed,
    this.currentLimit,
    required this.distanceRemaining,
    required this.durationRemaining,
    required this.onStartTrip,
    required this.onEndTrip,
    required this.onCancelPreview,
    required this.onToggleDirections,
    required this.showDirections,
    required this.hasHazardOnRoute,
    required this.selectedVehicleType,
    required this.onVehicleTypeChanged,
    required this.onCategorySelected,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(16),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 20,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag Handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              if (isNavigating && currentRoute != null)
                _buildActiveNavigationUI()
              else if (isPreviewing && currentRoute != null)
                _buildPreviewUI()
              else
                _buildIdleUI(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActiveNavigationUI() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Time & Distance
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${(durationRemaining / 60).toStringAsFixed(0)} min",
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: Colors.lightBlueAccent, // Premium accent
              ),
            ),
            Row(
              children: [
                Text(
                  "${(distanceRemaining / 1000).toStringAsFixed(1)} km",
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
                const SizedBox(width: 8),
                const Icon(Icons.circle, size: 6, color: Colors.grey),
                const SizedBox(width: 8),
                Text(
                  _calculateETA(durationRemaining),
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
          ],
        ),
        
        // Speedometer Gadget
        SpeedometerGadget(
          currentSpeed: currentSpeed, 
          speedLimit: currentLimit,
          size: 90,
        ),

        // Controls
        Column(
          children: [
             IconButton(
               onPressed: onToggleDirections,
               icon: Icon(showDirections ? Icons.map : Icons.list_alt_rounded),
               style: IconButton.styleFrom(backgroundColor: Colors.grey[100]),
             ),
             const SizedBox(height: 8),
             IconButton(
               onPressed: onEndTrip,
               icon: const Icon(Icons.close_rounded, color: Colors.white),
               style: IconButton.styleFrom(backgroundColor: Colors.redAccent),
             ),
          ],
        )
      ],
    );
  }

  Widget _buildPreviewUI() {
    return Column(
      children: [
        // Vehicle Type Selector in Preview
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
               _buildVehicleOption("car", Icons.directions_car),
               _buildVehicleOption("bike", Icons.directions_bike),
               _buildVehicleOption("foot", Icons.directions_walk),
            ],
          ),
        ),

        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
             Column(
               crossAxisAlignment: CrossAxisAlignment.start,
               children: [
                  const Text("Trip Preview", style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
                  Text(
                    "${(distanceRemaining / 1000).toStringAsFixed(1)} km",
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
               ],
             ),
             Container(
               padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
               decoration: BoxDecoration(
                 color: Colors.blue.withOpacity(0.1),
                 borderRadius: BorderRadius.circular(20),
               ),
               child: Text(
                 "${(durationRemaining / 60).toStringAsFixed(0)} min",
                 style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
               ),
             ),
          ],
        ),
        const SizedBox(height: 16),
        
        // Hazard Warning
        if (hasHazardOnRoute)
           Container(
             margin: const EdgeInsets.only(bottom: 16),
             padding: const EdgeInsets.all(12),
             decoration: BoxDecoration(
               color: Colors.orange.withOpacity(0.1),
               borderRadius: BorderRadius.circular(12),
               border: Border.all(color: Colors.orange.withOpacity(0.3)),
             ),
             child: Row(
               children: const [
                  Icon(Icons.warning_amber_rounded, color: Colors.orange),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      "Hazard reported on this route. Drive with caution.",
                      style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w600),
                    ),
                  ),
               ],
             ),
           ),

        Row(
          children: [
            Expanded(
              child: ElevatedButton(
                onPressed: onCancelPreview,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.grey[100],
                  foregroundColor: Colors.black,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Cancel", style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: onStartTrip,
                icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                label: const Text("Start Trip", style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  elevation: 4,
                  shadowColor: Colors.green.withOpacity(0.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildIdleUI() {
    // "Explore" Mode with Categories
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
         const Text("Explore Nearby", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
         const SizedBox(height: 16),
         SingleChildScrollView(
           scrollDirection: Axis.horizontal,
           child: Row(
             children: [
               _buildCategoryChip("Restaurants", Icons.restaurant, Colors.orange),
               _buildCategoryChip("Petrol", Icons.local_gas_station, Colors.red),
               _buildCategoryChip("Hotels", Icons.hotel, Colors.blue),
               _buildCategoryChip("Hospitals", Icons.local_hospital, Colors.green),
               _buildCategoryChip("Parking", Icons.local_parking, Colors.grey),
             ],
           ),
         ),
         const SizedBox(height: 20),
         // Vehicle type selector can also be here for setting preference
         const Text("Travel Mode", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey)),
         const SizedBox(height: 8),
         Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
               _buildVehicleOption("car", Icons.directions_car),
               _buildVehicleOption("bike", Icons.directions_bike),
               _buildVehicleOption("foot", Icons.directions_walk),
            ],
          ),
      ],
    );
  }

  Widget _buildCategoryChip(String label, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(right: 12),
      child: InkWell(
        onTap: () => onCategorySelected(label),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _buildVehicleOption(String type, IconData icon) {
    final isSelected = selectedVehicleType == type;
    return GestureDetector(
      onTap: () => onVehicleTypeChanged(type),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(icon, color: isSelected ? Colors.white : Colors.grey, size: 20),
            if (isSelected) ...[
              const SizedBox(width: 8),
              Text(
                type.toUpperCase(),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ]
          ],
        ),
      ),
    );
  }

  String _calculateETA(double seconds) {
    // Add seconds to current time
    final now = DateTime.now();
    final arrival = now.add(Duration(seconds: seconds.toInt()));
    return "${arrival.hour}:${arrival.minute.toString().padLeft(2, '0')}";
  }
}
