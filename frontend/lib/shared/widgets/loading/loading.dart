/// mCare loading system — one import for every wait state.
///
/// * [McarePulse] — the branded ECG indicator.
/// * [DelayedLoader] / [InlineBusy] — show an indicator only for real delays.
/// * [AppBusyBar] — global top bar fed by in-flight API requests.
/// * [McareEcgPath] — the shared lifeline geometry.
library;

export 'app_busy_bar.dart';
export 'delayed_loader.dart';
export 'mcare_ecg_path.dart';
export 'mcare_pulse.dart';
