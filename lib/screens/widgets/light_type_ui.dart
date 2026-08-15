import 'package:flutter/material.dart';

import '../../data/light_repository.dart';

extension LightTypeUi on LightType {
  IconData get icon => switch (this) {
        LightType.pedestrian => Icons.directions_walk,
        LightType.bike => Icons.pedal_bike,
        LightType.car => Icons.directions_car,
      };
}
