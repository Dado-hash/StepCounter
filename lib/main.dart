import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:health/health.dart';
import 'utils.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:carp_serializable/carp_serializable.dart';

void main() => runApp(HealthApp());

class HealthApp extends StatefulWidget {
  @override
  _HealthAppState createState() => _HealthAppState();
}

enum AppState {
  DATA_NOT_FETCHED,
  FETCHING_DATA,
  DATA_READY,
  NO_DATA,
  AUTHORIZED,
  AUTH_NOT_GRANTED,
  STEPS_READY,
  HEALTH_CONNECT_STATUS,
}

class _HealthAppState extends State<HealthApp> {
  List<HealthDataPoint> _healthDataList = [];
  AppState _state = AppState.DATA_NOT_FETCHED;
  int _nofSteps = 0;
  List<RecordingMethod> recordingMethodsToFilter = [];

  // All types available depending on platform (iOS ot Android).
  List<HealthDataType> get types => (Platform.isAndroid)
      ? dataTypesAndroid
      : (Platform.isIOS)
      ? dataTypesIOS
      : [];

  // Set up corresponding permissions

  // READ only
  List<HealthDataAccess> get permissions =>
      types.map((e) => HealthDataAccess.READ).toList();

  @override
  void initState() {
    // configure the health plugin before use and check the Health Connect status
    Health().configure();
    _requestPermissionsOnStartup();
    if (Platform.isAndroid) {
      Health().getHealthConnectSdkStatus();
    }
    super.initState();
  }

  Future<void> _requestPermissionsOnStartup() async {
    // Richiedi i permessi necessari quando l'app viene aperta per la prima volta
    await Permission.activityRecognition.request();
    await Permission.location.request();

    // Controllo permessi già esistenti
    bool? hasPermissions = await Health().hasPermissions(types, permissions: permissions);

    // Se i permessi non sono stati già concessi, richiedili
    if (!hasPermissions!) {
      try {
        bool authorized = await Health().requestAuthorization(types, permissions: permissions);
        setState(() {
          _state = authorized ? AppState.AUTHORIZED : AppState.AUTH_NOT_GRANTED;
        });
      } catch (error) {
        debugPrint("Exception in requestPermissionsOnStartup: $error");
        setState(() => _state = AppState.AUTH_NOT_GRANTED);
      }
    } else {
      setState(() => _state = AppState.AUTHORIZED);
    }
  }

  /// Install Google Health Connect on this phone.
  Future<void> installHealthConnect() async =>
      await Health().installHealthConnect();

  /// Gets the Health Connect status on Android.
  Future<void> getHealthConnectSdkStatus() async {
    assert(Platform.isAndroid, "This is only available on Android");

    final status = await Health().getHealthConnectSdkStatus();

    setState(() {
      _contentHealthConnectStatus =
          Text('Health Connect Status: ${status?.name.toUpperCase()}');
      _state = AppState.HEALTH_CONNECT_STATUS;
    });
  }

  /// Fetch data points from the health plugin and show them in the app.
  Future<void> fetchData() async {
    setState(() => _state = AppState.FETCHING_DATA);

    // get data within the last 24 hours
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(hours: 24));

    // Clear old data points
    _healthDataList.clear();

    try {
      // fetch health data
      List<HealthDataPoint> healthData = await Health().getHealthDataFromTypes(
        types: types,
        startTime: yesterday,
        endTime: now,
        recordingMethodsToFilter: recordingMethodsToFilter,
      );

      debugPrint('Total number of data points: ${healthData.length}. '
          '${healthData.length > 100 ? 'Only showing the first 100.' : ''}');

      // sort the data points by date
      healthData.sort((a, b) => b.dateTo.compareTo(a.dateTo));

      // save all the new data points (only the first 100)
      _healthDataList.addAll(
          (healthData.length < 100) ? healthData : healthData.sublist(0, 100));
    } catch (error) {
      debugPrint("Exception in getHealthDataFromTypes: $error");
    }

    // filter out duplicates
    _healthDataList = Health().removeDuplicates(_healthDataList);

    _healthDataList.forEach((data) => debugPrint(toJsonString(data)));

    // update the UI to display the results
    setState(() {
      _state = _healthDataList.isEmpty ? AppState.NO_DATA : AppState.DATA_READY;
    });
  }

  /// Fetch steps from the health plugin and show them in the app.
  Future<void> fetchStepData() async {
    int? steps;

    // get steps for today (i.e., since midnight)
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);

    bool stepsPermission =
        await Health().hasPermissions([HealthDataType.STEPS]) ?? false;
    if (!stepsPermission) {
      stepsPermission =
      await Health().requestAuthorization([HealthDataType.STEPS]);
    }

    if (stepsPermission) {
      try {
        steps = await Health().getTotalStepsInInterval(midnight, now,
            includeManualEntry:
            !recordingMethodsToFilter.contains(RecordingMethod.manual));
      } catch (error) {
        debugPrint("Exception in getTotalStepsInInterval: $error");
      }

      debugPrint('Total number of steps: $steps');

      setState(() {
        _nofSteps = (steps == null) ? 0 : steps;
        _state = (steps == null) ? AppState.NO_DATA : AppState.STEPS_READY;
      });
    } else {
      debugPrint("Authorization not granted - error in authorization");
      setState(() => _state = AppState.DATA_NOT_FETCHED);
    }
  }

  // UI building below

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Health Example'),
        ),
        body: Column(
          children: [
            Wrap(
              spacing: 10,
              children: [
                  Wrap(spacing: 10, children: [
                    TextButton(
                        onPressed: fetchData,
                        style: const ButtonStyle(
                            backgroundColor:
                            WidgetStatePropertyAll(Colors.blue)),
                        child: const Text("Fetch Data",
                            style: TextStyle(color: Colors.white))),
                    TextButton(
                        onPressed: fetchStepData,
                        style: const ButtonStyle(
                            backgroundColor:
                            WidgetStatePropertyAll(Colors.blue)),
                        child: const Text("Fetch Step Data",
                            style: TextStyle(color: Colors.white))),
                  ]),
              ],
            ),
            const Divider(thickness: 3),
            if (_state == AppState.DATA_READY) _dataFiltration,
            if (_state == AppState.STEPS_READY) _stepsFiltration,
            Expanded(child: Center(child: _content))
          ],
        ),
      ),
    );
  }

  Widget get _dataFiltration => Column(
    children: [
      Wrap(
        children: [
          for (final method in Platform.isAndroid
              ? [
            RecordingMethod.manual,
            RecordingMethod.automatic,
            RecordingMethod.active,
            RecordingMethod.unknown,
          ]
              : [
            RecordingMethod.automatic,
            RecordingMethod.manual,
          ])
            SizedBox(
              width: 150,
              child: CheckboxListTile(
                title: Text(
                    '${method.name[0].toUpperCase()}${method.name.substring(1)} entries'),
                value: !recordingMethodsToFilter.contains(method),
                onChanged: (value) {
                  setState(() {
                    if (value!) {
                      recordingMethodsToFilter.remove(method);
                    } else {
                      recordingMethodsToFilter.add(method);
                    }
                    fetchData();
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          // Add other entries here if needed
        ],
      ),
      const Divider(thickness: 3),
    ],
  );

  Widget get _stepsFiltration => Column(
    children: [
      Wrap(
        children: [
          for (final method in [
            RecordingMethod.manual,
          ])
            SizedBox(
              width: 150,
              child: CheckboxListTile(
                title: Text(
                    '${method.name[0].toUpperCase()}${method.name.substring(1)} entries'),
                value: !recordingMethodsToFilter.contains(method),
                onChanged: (value) {
                  setState(() {
                    if (value!) {
                      recordingMethodsToFilter.remove(method);
                    } else {
                      recordingMethodsToFilter.add(method);
                    }
                    fetchStepData();
                  });
                },
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
            ),
          // Add other entries here if needed
        ],
      ),
      const Divider(thickness: 3),
    ],
  );

  Widget get _contentFetchingData => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: <Widget>[
      Container(
          padding: const EdgeInsets.all(20),
          child: const CircularProgressIndicator(
            strokeWidth: 10,
          )),
      const Text('Fetching data...')
    ],
  );

  Widget get _contentDataReady => ListView.builder(
      itemCount: _healthDataList.length,
      itemBuilder: (_, index) {
        // filter out manual entires if not wanted
        if (recordingMethodsToFilter
            .contains(_healthDataList[index].recordingMethod)) {
          return Container();
        }

        HealthDataPoint p = _healthDataList[index];
        if (p.value is AudiogramHealthValue) {
          return ListTile(
            title: Text("${p.typeString}: ${p.value}"),
            trailing: Text('${p.unitString}'),
            subtitle: Text('${p.dateFrom} - ${p.dateTo}\n${p.recordingMethod}'),
          );
        }
        if (p.value is WorkoutHealthValue) {
          return ListTile(
            title: Text(
                "${p.typeString}: ${(p.value as WorkoutHealthValue).totalEnergyBurned} ${(p.value as WorkoutHealthValue).totalEnergyBurnedUnit?.name}"),
            trailing: Text(
                '${(p.value as WorkoutHealthValue).workoutActivityType.name}'),
            subtitle: Text('${p.dateFrom} - ${p.dateTo}\n${p.recordingMethod}'),
          );
        }
        if (p.value is NutritionHealthValue) {
          return ListTile(
            title: Text(
                "${p.typeString} ${(p.value as NutritionHealthValue).mealType}: ${(p.value as NutritionHealthValue).name}"),
            trailing:
            Text('${(p.value as NutritionHealthValue).calories} kcal'),
            subtitle: Text('${p.dateFrom} - ${p.dateTo}\n${p.recordingMethod}'),
          );
        }
        return ListTile(
          title: Text("${p.typeString}: ${p.value}"),
          trailing: Text('${p.unitString}'),
          subtitle: Text('${p.dateFrom} - ${p.dateTo}\n${p.recordingMethod}'),
        );
      });

  Widget _contentNoData = const Text('No Data to show');

  Widget _contentNotFetched =
  const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Text("Press 'Auth' to get permissions to access health data."),
    const Text("Press 'Fetch Dat' to get health data."),
    const Text("Press 'Add Data' to add some random health data."),
    const Text("Press 'Delete Data' to remove some random health data."),
  ]);

  Widget _authorized = const Text('Authorization granted!');

  Widget _authorizationNotGranted = const Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Text('Authorization not given.'),
      const Text(
          'For Google Health Connect please check if you have added the right permissions and services to the manifest file.'),
      const Text('For Apple Health check your permissions in Apple Health.'),
    ],
  );

  Widget _contentHealthConnectStatus = const Text(
      'No status, click getHealthConnectSdkStatus to get the status.');

  Widget get _stepsFetched => Text('Total number of steps: $_nofSteps.');

  Widget get _content => switch (_state) {
    AppState.DATA_READY => _contentDataReady,
    AppState.DATA_NOT_FETCHED => _contentNotFetched,
    AppState.FETCHING_DATA => _contentFetchingData,
    AppState.NO_DATA => _contentNoData,
    AppState.AUTHORIZED => _authorized,
    AppState.AUTH_NOT_GRANTED => _authorizationNotGranted,
    AppState.STEPS_READY => _stepsFetched,
    AppState.HEALTH_CONNECT_STATUS => _contentHealthConnectStatus,
  };
}
