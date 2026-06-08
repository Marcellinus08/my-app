import 'package:latlong2/latlong.dart';

/// Model untuk menyimpan instruksi navigasi turn-by-turn dari OSRM
class NavigationInstruction {
  final String instruction; // e.g., "Turn right", "Go straight"
  final String roadName; // Nama jalan
  final double distance; // Jarak sampai instruksi berikutnya (meter)
  final double duration; // Durasi sampai instruksi berikutnya (detik)
  final TurnType turnType; // Jenis belokan
  final double bearing; // Arah (0-360 derajat)
  final LatLng location; // Lokasi instruksi
  final List<LatLng> polylinePoints; // Polyline untuk segment ini

  NavigationInstruction({
    required this.instruction,
    required this.roadName,
    required this.distance,
    required this.duration,
    required this.turnType,
    required this.bearing,
    required this.location,
    required this.polylinePoints,
  });

  @override
  String toString() {
    return 'NavigationInstruction('
        'instruction: $instruction, '
        'roadName: $roadName, '
        'distance: $distance m, '
        'duration: $duration s, '
        'turnType: $turnType'
        ')';
  }
}

/// Enum untuk jenis belokan
enum TurnType {
  uturn,
  sharpRight,
  right,
  slightRight,
  straight,
  slightLeft,
  left,
  sharpLeft,
  unknown,
}

/// Helper class untuk parse OSRM maneuver
class ManeuverParser {
  /// Parse maneuver dari OSRM response ke TurnType
  static TurnType parseTurnType(String? type, String? modifier) {
    if (type == null) return TurnType.straight;

    type = type.toLowerCase();
    modifier = modifier?.toLowerCase();

    if (type == 'depart') {
      return TurnType.straight;
    }

    if (modifier == 'uturn' || modifier == 'u-turn') {
      return TurnType.uturn;
    }
    if (modifier == 'sharp right') return TurnType.sharpRight;
    if (modifier == 'right') return TurnType.right;
    if (modifier == 'slight right') return TurnType.slightRight;
    if (modifier == 'sharp left') return TurnType.sharpLeft;
    if (modifier == 'left') return TurnType.left;
    if (modifier == 'slight left') return TurnType.slightLeft;

    switch (type) {
      case 'uturn':
      case 'u-turn':
        return TurnType.uturn;
      case 'turn':
        return TurnType.unknown;
      case 'straight':
      case 'continue':
        return TurnType.straight;
      case 'depart':
      case 'arrive':
      case 'merge':
      case 'on ramp':
      case 'off ramp':
      case 'fork':
      case 'roundabout':
      case 'rotary':
        return TurnType.straight;
      default:
        return TurnType.unknown;
    }
  }

  /// Dapatkan instruksi readable dari TurnType dan nama jalan
  static String getInstructionText(TurnType turnType, String roadName) {
    String turnText = _getTurnText(turnType);
    if (roadName.isNotEmpty) {
      return '$turnText ke $roadName';
    }
    return turnText;
  }

  /// Terjemahan teks untuk setiap jenis belokan
  static String _getTurnText(TurnType turnType) {
    switch (turnType) {
      case TurnType.uturn:
        return 'Balik arah';
      case TurnType.sharpRight:
        return 'Belok kanan tajam';
      case TurnType.right:
        return 'Belok kanan';
      case TurnType.slightRight:
        return 'Belok kanan sedikit';
      case TurnType.straight:
        return 'Lurus';
      case TurnType.slightLeft:
        return 'Belok kiri sedikit';
      case TurnType.left:
        return 'Belok kiri';
      case TurnType.sharpLeft:
        return 'Belok kiri tajam';
      case TurnType.unknown:
        return 'Lanjutkan perjalanan';
    }
  }

  /// Dapatkan icon emoji untuk visualisasi
  static String getTurnEmoji(TurnType turnType) {
    switch (turnType) {
      case TurnType.uturn:
        return '🔄';
      case TurnType.sharpRight:
        return '⤴️';
      case TurnType.right:
        return '↗️';
      case TurnType.slightRight:
        return '→';
      case TurnType.straight:
        return '⬆️';
      case TurnType.slightLeft:
        return '←';
      case TurnType.left:
        return '↖️';
      case TurnType.sharpLeft:
        return '⤵️';
      case TurnType.unknown:
        return '➡️';
    }
  }
}
