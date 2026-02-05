import 'package:cc_insights_v2/models/project_config.dart';
import 'package:cc_insights_v2/services/project_config_service.dart';

/// A fake [ProjectConfigService] for testing.
///
/// Returns empty config by default. Configure [configs] to return
/// specific configs for different project roots.
class FakeProjectConfigService extends ProjectConfigService {
  /// Map of project root paths to their configs.
  final Map<String, ProjectConfig> configs = {};

  /// If true, will throw an exception when loading config.
  bool shouldThrow = false;

  /// The exception message to throw.
  String throwMessage = 'Fake config error';

  @override
  Future<ProjectConfig> loadConfig(String projectRoot) async {
    if (shouldThrow) {
      throw Exception(throwMessage);
    }
    return configs[projectRoot] ?? const ProjectConfig.empty();
  }

  @override
  Future<void> saveConfig(String projectRoot, ProjectConfig config) async {
    if (shouldThrow) {
      throw Exception(throwMessage);
    }
    configs[projectRoot] = config;
  }

  @override
  Future<bool> configExists(String projectRoot) async {
    return configs.containsKey(projectRoot);
  }
}
