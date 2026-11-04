# prosthesis_mobile_controller

## Environment configs

The app loads MQTT settings from a JSON file in `assets/config/`.

- `assets/config/dev.json` is for local development and emulator runs.

Select the configuration with `APP_ENV`:

```bash
flutter run --dart-define=APP_ENV=dev
```

If you do not pass `APP_ENV`, the app defaults to `dev`.

## MQTT credentials

The broker username and password are kept out of the config files and out of
git. They are read from `secrets.json` at the project root, which is ignored by
git. Create it from the template and fill in your credentials:

```bash
cp secrets.example.json secrets.json
```

Then pass it when running or building (the VS Code launch profiles already do
this):

```bash
flutter run --dart-define=APP_ENV=dev --dart-define-from-file=secrets.json
flutter build apk --release --dart-define-from-file=secrets.json
```

Leaving a value empty connects without that credential. Note that the values
are compiled into the app binary, so use a broker user restricted to the
`prosthesis/#` topics rather than an admin account.

## Command batches

`tool/command_batches.dart` drives the prosthesis without the app, e.g. to
gather latency samples. It sends the same commands the app sends, one at a
time, each once the previous one was answered, in batches of four: power on,
change the gait mode, change the actuator current, power off. A batch where a
command fails or goes unanswered is discarded and run again, until the
requested number of batches went through. The script saves nothing itself: the
orchestrator stores the commands and their feedback as it does for the app. At
the end it prints how many batches went through, how many failed, and the range
of ids the orchestrator stored the commands under.

Run it from the project root, with the prosthesis off and the app closed. It
connects with the same config file and `secrets.json` as the app:

```bash
dart run tool/command_batches.dart              # 100 batches
dart run tool/command_batches.dart --batches 1 --timeout 30
```

- Each command waits for its answer as long as the app does
  (`powerFeedbackTimeoutSeconds`), unless `--timeout` says otherwise. The answer
  is recognized by the id the orchestrator stored the command under, read from
  `prosthesis/actions/validated`, so a late answer to a command that timed out
  is never taken for a later command's.
- Each gait change moves on to the gait mode after the one the prosthesis came
  up in, and each current change alternates between 3000 and 4000 mA, so both
  always change what it runs.
- A failed batch that may have left the prosthesis on is followed by a power
  off, so every batch starts with a real power on. After five failed batches in
  a row the script gives up.
- Ctrl+C, or a stop from the Pi, stops it once the command on its way is
  answered, and it turns the prosthesis off before quitting (a second Ctrl+C
  quits at once).
