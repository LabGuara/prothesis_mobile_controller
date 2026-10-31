import 'package:flutter/material.dart';

import '../models/action_command.dart';

const gaitModeStyles = <GaitMode, ({IconData icon, Color color})>{
  GaitMode.walking: (icon: Icons.directions_walk_rounded, color: Color(0xFF2563EB)),
  GaitMode.stairAscent: (icon: Icons.north_rounded, color: Color(0xFF7C3AED)),
  GaitMode.standing: (icon: Icons.accessibility_new_rounded, color: Color(0xFF059669)),
  GaitMode.stairDescent: (icon: Icons.south_rounded, color: Color(0xFFDB2777)),
  GaitMode.upslopeWalking: (icon: Icons.trending_up_rounded, color: Color(0xFFD97706)),
  GaitMode.downslopeWalking: (icon: Icons.trending_down_rounded, color: Color(0xFF0891B2)),
  GaitMode.sitting: (icon: Icons.airline_seat_recline_normal_rounded, color: Color(0xFF65A30D)),
  GaitMode.sitToStand: (icon: Icons.upload_rounded, color: Color(0xFFEA580C)),
  GaitMode.standToSit: (icon: Icons.download_rounded, color: Color(0xFF6D28D9)),
};
