import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:args/args.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
import 'package:prosthesis_mobile_controller/config/utils.dart';
import 'package:prosthesis_mobile_controller/models/action_command.dart';
import 'package:prosthesis_mobile_controller/models/power_feedback.dart';

const _description = '''
Sends the prosthesis batches of commands the way the app does, each command once the previous one
was answered: power on, change the gait mode, change the actuator current, power off. A batch where
a command fails or goes unanswered is discarded and run again, until the requested number of
batches went through.

Run it from the project root, with the prosthesis off and the app closed:

    dart run tool/command_batches.dart [options]''';

const _commandLogsValidatedTopic = 'prosthesis/actions/validated';

const _currents = (3000, 4000);

const _maxFailuresInARow = 5;

Future<void> main(List<String> arguments) async {
  final code = await _run(arguments);
  await Future.wait([stdout.flush(), stderr.flush()]);
  exit(code);
}

Future<int> _run(List<String> arguments) async {
  final parser = ArgParser()
    ..addOption('batches', defaultsTo: '100', help: 'Batches to get through.')
    ..addOption(
      'timeout',
      help: 'Seconds to wait for the answer to each command.\n(defaults to powerFeedbackTimeoutSeconds, as in the app)',
    )
    ..addOption('env', defaultsTo: 'dev', help: 'Config in assets/config to connect with, as APP_ENV in the app.')
    ..addFlag('help', abbr: 'h', negatable: false, help: 'Show this help.');

  final ArgResults options;
  try {
    options = parser.parse(arguments);
  } on FormatException catch (error) {
    stderr.writeln('${error.message}\n\n${parser.usage}');
    return 64;
  }
  if (options.flag('help')) {
    stdout.writeln('$_description\n\n${parser.usage}');
    return 0;
  }

  final Map<String, dynamic> config;
  final Map<String, dynamic> secrets;
  try {
    config = _readJsonObject('assets/config/${options.option('env')}.json');
    secrets = File('secrets.json').existsSync() ? _readJsonObject('secrets.json') : const {};
  } on Exception catch (error) {
    stderr.writeln('Could not read the config (run this from the project root): $error');
    return 1;
  }

  final batches = int.tryParse(options.option('batches')!);
  final timeout = options.option('timeout');
  final timeoutSeconds = timeout == null
      ? readInt(config, 'powerFeedbackTimeoutSeconds', fallback: 10)
      : int.tryParse(timeout);
  if (batches == null || batches < 1 || timeoutSeconds == null || timeoutSeconds < 1) {
    stderr.writeln('--batches and --timeout take a positive whole number.\n\n${parser.usage}');
    return 64;
  }

  final link = _ProsthesisLink(config, timeout: Duration(seconds: timeoutSeconds));
  try {
    await link.connect(
      username: readString(secrets, 'MQTT_USERNAME', fallback: ''),
      password: readString(secrets, 'MQTT_PASSWORD', fallback: ''),
    );
  } on Exception catch (error) {
    stderr.writeln('Could not connect to ${link.server}: $error');
    return 1;
  }
  stdout.writeln('Connected to ${link.server}');

  final interrupts = ProcessSignal.sigint.watch().listen((_) {
    if (link.stopReason != null) {
      exit(130);
    }
    link.stopReason = 'interrupted';
    stdout.writeln('Stopping once the command on its way is answered (Ctrl+C again to quit now)');
  });

  var done = 0;
  var failed = 0;
  var failedInARow = 0;
  while (done < batches && failedInARow < _maxFailuresInARow) {
    try {
      await _runBatch(link);
      done++;
      failedInARow = 0;
      stdout.writeln('Batch $done/$batches done');
    } on _CommandFailed catch (failure) {
      failed++;
      failedInARow++;
      stdout.writeln('Batch failed: $failure');
    } on _Stopped {
      break;
    }
  }

  final stopReason = link.stopReason;
  if (stopReason != null) {
    stdout.writeln('Stopped: $stopReason');
  } else if (failedInARow == _maxFailuresInARow) {
    stdout.writeln('Stopped: $failedInARow batches in a row failed');
  }
  if (link.mayBeOn) {
    stdout.writeln('Turning the prosthesis off');
    try {
      await link.turnOff();
    } on _CommandFailed catch (failure) {
      stderr.writeln('Could not turn the prosthesis off, check on it: $failure');
    }
  }
  await interrupts.cancel();
  link.disconnect();

  stdout
    ..writeln('Batches done: $done/$batches')
    ..writeln('Batches failed: $failed');
  final ids = link.storedIds;
  if (ids.isNotEmpty) {
    stdout.writeln('Command ids: ${ids.first} to ${ids.last}');
  }
  return done == batches ? 0 : 1;
}

Future<void> _runBatch(_ProsthesisLink link) async {
  if (link.mayBeOn) {
    stdout.writeln('Turning the prosthesis off before the next batch');
    await link.send(CommandLog.fromPower(PowerState.off));
  }

  final on = await link.send(CommandLog.fromPower(PowerState.on));
  final mode = on.gaitMode;
  final nextMode = GaitMode.values[mode == null ? 0 : (mode.index + 1) % GaitMode.values.length];
  await link.send(CommandLog.fromGaitMode(nextMode));
  await link.send(CommandLog.fromActuatorCurrent(on.current == _currents.$1 ? _currents.$2 : _currents.$1));
  await link.send(CommandLog.fromPower(PowerState.off));
}

class _ProsthesisLink {
  _ProsthesisLink(Map<String, dynamic> config, {required this.timeout})
    : _client = MqttServerClient(
        readString(config, 'host', fallback: 'localhost'),
        '${readString(config, 'clientId', fallback: 'prosthesis-mobile-controller')}-batches-'
        '${DateTime.now().millisecondsSinceEpoch}',
      ),
      _commandTopic = readString(config, 'commandLogsTopic', fallback: 'prosthesis/actions'),
      _feedbackTopic = readString(
        config,
        'powerFeedbackValidatedTopic',
        fallback: 'prosthesis/actions/feedback/validated',
      ),
      _connectionTimeout = Duration(seconds: readInt(config, 'connectionTimeoutSeconds', fallback: 15)) {
    _client
      ..port = readInt(config, 'port', fallback: 1883)
      ..secure = readBool(config, 'useSSL', fallback: false)
      ..keepAlivePeriod = 20
      ..autoReconnect = true
      ..connectionMessage = MqttConnectMessage().withClientIdentifier(_client.clientIdentifier).startClean();
  }

  final MqttServerClient _client;
  final String _commandTopic;
  final String _feedbackTopic;
  final Duration _connectionTimeout;
  final Duration timeout;

  final _storedCommands = StreamController<String>.broadcast(sync: true);
  final _feedback = StreamController<PowerFeedback>.broadcast(sync: true);

  bool mayBeOn = false;

  String? stopReason;

  final storedIds = <int>[];

  String get server => '${_client.server}:${_client.port}';

  Future<void> connect({required String username, required String password}) async {
    await _client
        .connect(username.isEmpty ? null : username, password.isEmpty ? null : password)
        .timeout(_connectionTimeout);
    if (_client.connectionStatus?.state != MqttConnectionState.connected) {
      throw Exception('MQTT connect failed with state: ${_client.connectionStatus?.state}');
    }

    _client.updates!.listen(_onMessages);
    final topics = [_feedbackTopic, _commandLogsValidatedTopic];
    for (final topic in topics) {
      _client.subscribe(topic, MqttQos.atLeastOnce);
    }
    final subscribed = await _waitFor(
      () => topics.every((topic) => _client.getSubscriptionsStatus(topic) == MqttSubscriptionStatus.active),
      _connectionTimeout,
    );
    if (!subscribed) {
      throw Exception('the broker did not confirm the subscriptions');
    }
  }

  void disconnect() => _client.disconnect();

  Future<PowerFeedback> send(CommandLog command) async {
    if (stopReason != null) {
      throw const _Stopped();
    }
    return _exchange(command);
  }

  Future<PowerFeedback> turnOff() => _exchange(CommandLog.fromPower(PowerState.off));

  Future<PowerFeedback> _exchange(CommandLog command) async {
    final name = _describe(command);
    if (!await _waitFor(() => _client.connectionStatus?.state == MqttConnectionState.connected, _connectionTimeout)) {
      throw _CommandFailed('$name not sent: not connected to the broker');
    }

    final answer = Completer<PowerFeedback>();
    int? id;
    final unclaimed = <int, PowerFeedback>{};
    void claim(PowerFeedback? feedback) {
      if (feedback != null && !answer.isCompleted) {
        answer.complete(feedback);
      }
    }

    final subscriptions = [
      _storedCommands.stream.listen((payload) {
        final storedId = id == null ? _storedIdOf(payload, command) : null;
        if (storedId != null) {
          id = storedId;
          storedIds.add(storedId);
          claim(unclaimed[storedId]);
        }
      }),
      _feedback.stream.listen((feedback) {
        final commandId = feedback.commandId;
        if (commandId == null) {
          return;
        }
        if (id == null) {
          unclaimed[commandId] = feedback;
        } else if (commandId == id) {
          claim(feedback);
        }
      }),
    ];

    try {
      final builder = MqttClientPayloadBuilder()..addUTF8String(command.toJson());
      try {
        _client.publishMessage(_commandTopic, MqttQos.atLeastOnce, builder.payload!, retain: false);
      } on Exception catch (error) {
        throw _CommandFailed('$name not sent: $error');
      }
      mayBeOn = true;

      final feedback = await answer.future.timeout(timeout);
      mayBeOn = feedback.state.isOn;
      if (!feedback.isSuccess) {
        throw _CommandFailed('$name failed: ${feedback.message}');
      }
      return feedback;
    } on TimeoutException {
      throw _CommandFailed(
        id == null
            ? '$name was not stored by the orchestrator within ${timeout.inSeconds} s'
            : '$name (command $id) got no answer within ${timeout.inSeconds} s',
      );
    } finally {
      for (final subscription in subscriptions) {
        await subscription.cancel();
      }
    }
  }

  void _onMessages(List<MqttReceivedMessage<MqttMessage>> messages) {
    for (final received in messages) {
      final publishMessage = received.payload as MqttPublishMessage;
      final payload = utf8.decode(publishMessage.payload.message, allowMalformed: true);

      if (received.topic == _commandLogsValidatedTopic) {
        _storedCommands.add(payload);
        continue;
      }
      if (received.topic != _feedbackTopic) {
        continue;
      }

      final feedback = PowerFeedback.tryParse(payload);
      if (feedback == null) {
        continue;
      }
      if (feedback.isInternal) {
        stopReason ??= 'the prosthesis was stopped on the Pi (${feedback.message})';
      }
      _feedback.add(feedback);
    }
  }
}

class _CommandFailed implements Exception {
  const _CommandFailed(this.reason);

  final String reason;

  @override
  String toString() => reason;
}

class _Stopped implements Exception {
  const _Stopped();
}

int? _storedIdOf(String payload, CommandLog command) {
  Object? decoded;
  try {
    decoded = json.decode(payload);
  } on FormatException {
    return null;
  }
  if (decoded is! Map<String, dynamic>) {
    return null;
  }

  final id = decoded['command_id'];
  final timestamp = decoded['timestamp'];
  final isThisCommand =
      timestamp is String &&
      (DateTime.tryParse(timestamp)?.isAtSameMomentAs(command.timestamp) ?? false) &&
      decoded['command_type'] == command.commandType.value &&
      decoded['value'] == command.value;
  return isThisCommand && id is int ? id : null;
}

String _describe(CommandLog command) => switch (command.commandType) {
  CommandType.power => command.value == PowerState.on.value ? 'power on' : 'power off',
  CommandType.gaitMode => 'gait mode ${GaitMode.fromValue(command.value)?.label}',
  CommandType.actuatorCurrent => 'actuator current ${command.value} mA',
};

Future<bool> _waitFor(bool Function() condition, Duration timeout) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      return false;
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
  return true;
}

Map<String, dynamic> _readJsonObject(String path) {
  final decoded = json.decode(File(path).readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    throw FormatException('$path must contain a JSON object.');
  }
  return decoded;
}
