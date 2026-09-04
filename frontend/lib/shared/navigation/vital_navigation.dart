import 'package:flutter/material.dart';

import '../constants/route_names.dart';
import '../models/vital.dart';
import '../models/vital_detail_args.dart';

void openVitalDetail(
  BuildContext context,
  VitalKey vital, {
  int rangeDays = 7,
}) {
  Navigator.of(context).pushNamed(
    RouteNames.patientVitalDetail,
    arguments: VitalDetailArgs(vital: vital, rangeDays: rangeDays),
  );
}
