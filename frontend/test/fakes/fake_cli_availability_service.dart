import 'package:flutter/foundation.dart';
import 'package:cc_insights_v2/services/cli_availability_service.dart';

/// A fake [CliAvailabilityService] for testing.
///
/// Defaults to both CLIs available. Use the setters to configure
/// different availability states.
class FakeCliAvailabilityService extends ChangeNotifier
    implements CliAvailabilityService {
  bool _claudeAvailable = true;
  bool _codexAvailable = true;
  bool _acpAvailable = true;
  bool _checked = true;
  int checkAllCalls = 0;

  @override
  bool get claudeAvailable => _claudeAvailable;

  @override
  bool get codexAvailable => _codexAvailable;

  @override
  bool get acpAvailable => _acpAvailable;

  @override
  bool get checked => _checked;

  set claudeAvailable(bool value) {
    _claudeAvailable = value;
    notifyListeners();
  }

  set codexAvailable(bool value) {
    _codexAvailable = value;
    notifyListeners();
  }

  set acpAvailable(bool value) {
    _acpAvailable = value;
    notifyListeners();
  }

  set checked(bool value) {
    _checked = value;
    notifyListeners();
  }

  @override
  Future<void> checkAll({
    String claudePath = '',
    String codexPath = '',
    String acpPath = '',
  }) async {
    checkAllCalls++;
  }
}
