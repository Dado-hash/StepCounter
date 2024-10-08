import 'dart:async';
import 'package:flutter/material.dart';
import 'package:pedometer/pedometer.dart';
import 'package:permission_handler/permission_handler.dart';

void main() => runApp(const StepCounterApp());

class StepCounterApp extends StatelessWidget {
  const StepCounterApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Contapassi',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const StepCounterHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class StepCounterHomePage extends StatefulWidget {
  const StepCounterHomePage({Key? key}) : super(key: key);

  @override
  _StepCounterHomePageState createState() => _StepCounterHomePageState();
}

class _StepCounterHomePageState extends State<StepCounterHomePage> {
  StreamSubscription<StepCount>? _stepCountSubscription;

  int _steps = 0;
  int? _initialSteps;
  double _calories = 0.0;

  final double _weightInKg = 70.0; // Puoi rendere questo valore dinamico

  @override
  void initState() {
    super.initState();
    _startStepCount();
  }

  @override
  void dispose() {
    _stepCountSubscription?.cancel();
    super.dispose();
  }

  void _startStepCount() async {
    if (await _checkAndRequestPermissions()) {
      _stepCountSubscription = Pedometer.stepCountStream.listen(
        _onStepCount,
        onError: _onStepCountError,
      );
    } else {
      // Gestisci il caso in cui i permessi non sono stati concessi
      _showPermissionDeniedDialog();
    }
  }

  Future<bool> _checkAndRequestPermissions() async {
    // Controlla e richiedi il permesso ACTIVITY_RECOGNITION
    PermissionStatus status = await Permission.activityRecognition.status;

    if (status.isDenied) {
      // Richiedi il permesso
      status = await Permission.activityRecognition.request();
    }

    if (status.isPermanentlyDenied) {
      // Apri le impostazioni dell'app se il permesso è permanentemente negato
      await openAppSettings();
      return false;
    }

    return status.isGranted;
  }

  void _showPermissionDeniedDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Permesso Negato'),
        content: Text('Per utilizzare questa funzione, devi concedere il permesso richiesto.'),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
            },
            child: Text('OK'),
          ),
        ],
      ),
    );
  }

  void _onStepCount(StepCount event) {
    setState(() {
      _initialSteps ??= event.steps;
      _steps = event.steps - _initialSteps!;
      _calories = _calculateCalories(_steps, _weightInKg);
    });
  }

  void _onStepCountError(error) {
    print('Errore nel conteggio dei passi: $error');
  }

  double _calculateCalories(int steps, double weightInKg) {
    // Calorie bruciate per passo = 0.04 kcal (valore medio)
    return steps * 0.04 * (weightInKg / 70); // 70 kg come peso di riferimento
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contapassi'),
        centerTitle: true,
      ),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          children: [
            _buildStatCard('Passi', '$_steps', Icons.directions_walk),
            _buildStatCard(
                'Calorie Bruciate',
                '${_calories.toStringAsFixed(2)} kcal',
                Icons.local_fire_department),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, String data, IconData icon) {
    return Card(
      elevation: 4.0,
      margin: const EdgeInsets.symmetric(vertical: 12.0),
      shape:
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.0)),
      child: ListTile(
        leading: Icon(icon, size: 40.0, color: Colors.blueAccent),
        title: Text(
          title,
          style: const TextStyle(fontSize: 18.0, fontWeight: FontWeight.w600),
        ),
        trailing: Text(
          data,
          style: const TextStyle(fontSize: 22.0, fontWeight: FontWeight.bold),
        ),
      ),
    );
  }
}
