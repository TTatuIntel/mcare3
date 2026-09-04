import 'vital.dart';

/// Route arguments for opening a specific vital detail screen.
class VitalDetailArgs {
  const VitalDetailArgs({required this.vital, this.rangeDays = 7});

  final VitalKey vital;
  final int rangeDays;

  static VitalDetailArgs? tryParse(Object? args) {
    if (args is VitalDetailArgs) return args;
    if (args is VitalKey) return VitalDetailArgs(vital: args);
    return null;
  }
}
