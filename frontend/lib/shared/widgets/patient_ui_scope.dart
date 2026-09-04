import 'package:flutter/widgets.dart';

/// Marks widgets rendered inside the patient application shell.
class PatientUiScope extends InheritedWidget {
  const PatientUiScope({super.key, required super.child});

  static bool isActive(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PatientUiScope>() != null;

  @override
  bool updateShouldNotify(PatientUiScope oldWidget) => false;
}
