class SearchResult {
  final String displayName;
  final double lat;
  final double lng;

  SearchResult({required this.displayName, required this.lat, required this.lng});

  factory SearchResult.fromJson(Map<String, dynamic> json) {
    return SearchResult(
      displayName: json['display_name'] ?? '',
      lat: double.parse(json['lat']),
      lng: double.parse(json['lon']),
    );
  }
}
