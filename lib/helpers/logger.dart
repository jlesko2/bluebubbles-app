import 'dart:convert';

import 'package:bluebubbles/helpers/share.dart';
import 'package:bluebubbles/helpers/utils.dart';
import 'package:bluebubbles/managers/life_cycle_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;
import 'package:universal_io/io.dart';

// ignore: non_constant_identifier_names
BaseLogger Logger = Get.isRegistered<BaseLogger>() ? Get.find<BaseLogger>() : Get.put(BaseLogger());

enum LogLevel { INFO, WARN, ERROR, DEBUG }

class BaseLogger extends GetxService {
  final RxBool saveLogs = false.obs;
  final RxBool startup = false.obs;
  final int lineLimit = 5000;
  List<String> logs = [];
  List<LogLevel> enabledLevels = [LogLevel.INFO, LogLevel.WARN, LogLevel.DEBUG, LogLevel.ERROR];
  final String _directoryPath = "/storage/emulated/0/Download/BlueBubbles-log-";
  late final File startupFile;
  late final File logFile;

  String get logPath {
    DateTime now = DateTime.now().toLocal();
    return "$_directoryPath${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}.txt";
  }

  set setEnabledLevels(List<LogLevel> levels) => enabledLevels = levels;

  init() async {
    // For now, only do logs on desktop
    if (kIsDesktop) {
      String startupPath = (await getDownloadsDirectory())!.path;
      startupPath = join(startupPath, "BlueBubbles_Logs_Startup.txt");
      startupFile = File(startupPath);
      if (startupFile.existsSync()) {
        startupFile.writeAsStringSync("", mode: FileMode.writeOnly);
        startup.listen((val) async {
          if (val) {
            await writeToStartupFile('----------------${DateTime.now().toLocal()}----------------');
          }
        });
      }

      String logPath = (await getApplicationSupportDirectory()).path;
      logPath = join(logPath, "BlueBubbles_Logs.txt");
      logFile = File(logPath);
      logFile.writeAsStringSync("", mode: FileMode.writeOnly);
      saveLogs.listen((val) async {
        if (val) {
          await writeLiveLogs('---------------- START LOG ${DateTime.now().toLocal()}----------------');
        } else {
          await writeLiveLogs('----------------   END LOG ${DateTime.now().toLocal()}----------------');
        }
      });
    }
  }

  void startSavingLogs() {
    saveLogs.value = true;
  }

  Future<void> stopSavingLogs() async {
    saveLogs.value = false;

    // Write the log to a file so the user can view/share it
    await writeLogToFile();

    // Clear the logs
    logs.clear();
  }

  Future<void> writeToStartupFile(String log) async {
    if (kIsDesktop && startupFile.existsSync()) {
      startupFile.writeAsStringSync('$log\n', mode: FileMode.writeOnlyAppend);
    }
  }

  Future<void> writeLiveLogs(String log) async {
    if (kIsDesktop) {
      logFile.writeAsStringSync('$log\n', mode: FileMode.writeOnlyAppend);
    }
  }

  Future<void> writeLogToFile() async {
    // Create the log file and write to it
    if (kIsWeb) {
      final bytes = utf8.encode(logs.join('\n'));
      final content = base64.encode(bytes);
      html.AnchorElement(href: "data:application/octet-stream;charset=utf-16le;base64,$content")
        ..setAttribute("download", logPath.split("/").last)
        ..click();
      return;
    }
    String filePath = logPath;
    if (kIsDesktop) {
      filePath = (await getApplicationSupportDirectory()).path;
      DateTime now = DateTime.now().toLocal();
      filePath = join(filePath, "Saved Logs",
          "BlueBubbles_Logs_${now.year}${now.month}${now.day}_${now.hour}${now.minute}${now.second}.txt");
    }
    File file = File(filePath);
    await file.create(recursive: true);
    await file.writeAsString(logs.join('\n'));

    // Show the snackbar when finished
    showSnackbar(
      "Success",
      "Logs exported successfully to $filePath",
      durationMs: kIsDesktop ? 5000 : 2500,
      button: kIsDesktop || kIsWeb
          ? null
          : TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Get.theme.colorScheme.secondary,
              ),
              onPressed: () {
                Share.file("BlueBubbles Logs", filePath);
              },
              child: Text("SHARE", style: TextStyle(color: Theme.of(Get.context!).primaryColor)),
            ),
    );
  }

  void info(dynamic log, {String? tag}) => _log(LogLevel.INFO, log, tag: tag);

  void warn(dynamic log, {String? tag}) => _log(LogLevel.WARN, log, tag: tag);

  void debug(dynamic log, {String? tag}) => _log(LogLevel.DEBUG, log, tag: tag);

  void error(dynamic log, {String? tag}) => _log(LogLevel.ERROR, log, tag: tag);

  void _log(LogLevel level, dynamic log, {String name = "BlueBubblesApp", String? tag}) {
    if (!enabledLevels.contains(level)) return;

    try {
      // Example: [BlueBubblesApp][INFO][2021-01-01 01:01:01.000] (Some Tag) -> <Some log here>
      String theLog = _buildLog(level, name, tag, log);

      // Log the data normally
      debugPrint(theLog);

      // If we are in startup, write the log to the startup file
      if (kIsDesktop) {
        if (startup.value) {
          writeToStartupFile(theLog);
        }
        writeLiveLogs(theLog);
      }

      // If we aren't saving logs, return here
      if (!saveLogs.value) return;

      // Otherwise, add the log to the list
      logs.add(theLog);

      // Make sure we concatenate to our limit
      if (logs.length >= lineLimit) {
        // Be safe with it. Make sure we don't go negative or the ranges max < min
        int min = logs.length - lineLimit;
        int max = logs.length;
        if (min < 0) min = 0;
        if (max < min) max = min;

        // Take the last x amount of logs (based on the line limit)
        logs = logs.sublist(min, max);
      }
    } catch (ex, stacktrace) {
      debugPrint("Failed to write log! ${ex.toString()}");
      debugPrint(stacktrace.toString());
    }
  }

  String _buildLog(LogLevel level, String name, String? tag, dynamic log) {
    final time = DateTime.now().toLocal().toString();
    String theLog = "[$time][${describeEnum(level).toUpperCase()}]${LifeCycleManager().isBubble ? "[Bubbled]" : ""}";

    // If we have a name, add the name
    if (name.isNotEmpty) {
      theLog = "[$name]$theLog";
    }

    // If we have a tag, add it before the log string
    if (tag != null && tag.isNotEmpty) {
      theLog = "$theLog ($tag) ->";
    }

    return "$theLog ${log.toString()}";
  }
}
