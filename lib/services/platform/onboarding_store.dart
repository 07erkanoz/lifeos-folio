import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_directories.dart';
import 'atomic_file.dart';

class OnboardingStatus {
  final bool licenseAccepted;
  final bool completed;
  const OnboardingStatus({
    this.licenseAccepted = false,
    this.completed = false,
  });
}

class OnboardingStore {
  static const licenseVersion = '2026-09-11';
  final String? path;
  const OnboardingStore({this.path});
  Future<File> _file() async => File(
    path ?? p.join((await folioSupportDirectory()).path, 'onboarding.json'),
  );
  Future<OnboardingStatus> load() async {
    final file = await _file();
    if (!await file.exists()) return const OnboardingStatus();
    try {
      final json = jsonDecode(await file.readAsString());
      if (json is! Map<String, dynamic>) return const OnboardingStatus();
      return OnboardingStatus(
        licenseAccepted: json['licenseVersion'] == licenseVersion,
        completed: json['completed'] == true,
      );
    } on FormatException {
      return const OnboardingStatus();
    }
  }

  Future<void> save({required bool completed}) async {
    await replaceFileIfChanged(
      await _file(),
      utf8.encode(
        jsonEncode({
          'licenseVersion': licenseVersion,
          'acceptedAt': DateTime.now().toUtc().toIso8601String(),
          'completed': completed,
        }),
      ),
    );
  }
}
