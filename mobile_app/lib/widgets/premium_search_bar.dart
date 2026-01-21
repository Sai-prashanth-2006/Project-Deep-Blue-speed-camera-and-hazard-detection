import 'dart:ui';
import 'package:flutter/material.dart';

class PremiumSearchBar extends StatefulWidget {
  final TextEditingController searchController;
  final Function(String) onSearchChanged;
  final Function(String) onSearchSubmitted;
  final VoidCallback onClear;
  final bool isSearching;

  const PremiumSearchBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.onSearchSubmitted,
    required this.onClear,
    required this.isSearching,
  });

  @override
  State<PremiumSearchBar> createState() => _PremiumSearchBarState();
}

class _PremiumSearchBarState extends State<PremiumSearchBar> {
  bool _isExpanded = false;
  final TextEditingController _fromController = TextEditingController(text: "Current Location");

  @override
  Widget build(BuildContext context) {
    // Premium Glassmorphic Look
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: _isExpanded ? MediaQuery.of(context).size.width * 0.9 : MediaQuery.of(context).size.width * 0.85,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.8), // Semi-transparent white
            borderRadius: BorderRadius.circular(30),
            border: Border.all(color: Colors.white.withOpacity(0.5)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 15,
                spreadRadius: 2,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Expand Toggle / From Field
              if (_isExpanded)
                _buildFromField(),
                
              // Main Destination Field
              Row(
                children: [
                   Icon(
                     _isExpanded ? Icons.location_on : Icons.search_rounded, 
                     color: _isExpanded ? Colors.red : Colors.grey[700]
                   ),
                   const SizedBox(width: 10),
                   Expanded(
                     child: TextField(
                       controller: widget.searchController,
                       style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                       decoration: InputDecoration(
                         hintText: "Where to?",
                         hintStyle: TextStyle(color: Colors.grey[600]),
                         border: InputBorder.none,
                         isDense: true,
                         contentPadding: EdgeInsets.zero,
                       ),
                       onChanged: widget.onSearchChanged,
                       onSubmitted: widget.onSearchSubmitted,
                       onTap: () {
                         // Auto-expand on tap if desired, or simplified
                         setState(() => _isExpanded = true);
                       },
                     ),
                   ),
                   
                   // Actions
                   if (widget.searchController.text.isNotEmpty)
                     IconButton(
                       icon: const Icon(Icons.close, size: 20, color: Colors.grey),
                       onPressed: () {
                         widget.onClear();
                         // Optional: Collapse on clear?
                         // setState(() => _isExpanded = false);
                       },
                       constraints: const BoxConstraints(),
                       padding: EdgeInsets.zero,
                     )
                   else if (widget.isSearching)
                     const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                   else
                     // Expand Button (Arrow)
                     GestureDetector(
                       onTap: () => setState(() => _isExpanded = !_isExpanded),
                       child: Container(
                         padding: const EdgeInsets.all(6),
                         decoration: BoxDecoration(
                           color: Colors.grey[200],
                           shape: BoxShape.circle,
                         ),
                         child: Icon(
                           _isExpanded ? Icons.keyboard_arrow_up : Icons.directions, 
                           size: 20, 
                           color: Colors.blueAccent
                         ),
                       ),
                     ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFromField() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
           const Icon(Icons.my_location, color: Colors.blue, size: 20),
           const SizedBox(width: 10),
           Expanded(
             child: TextField(
               controller: _fromController,
               style: const TextStyle(fontSize: 14, color: Colors.blue),
               readOnly: true, // For MVP, fixed to Current Location
               decoration: const InputDecoration(
                 labelText: "From",
                 border: InputBorder.none,
                 isDense: true,
                 contentPadding: EdgeInsets.zero,
               ),
             ),
           ),
        ],
      ),
    );
  }
}
