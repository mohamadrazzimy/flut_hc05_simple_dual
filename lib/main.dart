import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  runApp(const MyApp());
}

class BtDeviceItem {
  final String name;
  final String id;
  final String type;

  BtDeviceItem({
    required this.name,
    required this.id,
    required this.type,
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: ScannerPage(),
    );
  }
}

/* ===================== SCANNER PAGE ===================== */

class ScannerPage extends StatefulWidget {
  const ScannerPage({super.key});

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> {
  static const MethodChannel classicChannel =
  MethodChannel('classic_bluetooth');

  final List<BtDeviceItem> bleDevices = [];
  final List<BtDeviceItem> classicDevices = [];

  StreamSubscription<List<ScanResult>>? scanSub;

  bool scanning = false;

  @override
  void dispose() {
    scanSub?.cancel();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  Future<void> requestPermissions() async {
    await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse,
    ].request();
  }

  Future<void> scan() async {
    await requestPermissions();

    bleDevices.clear();
    classicDevices.clear();

    setState(() {
      scanning = true;
    });

    await loadClassicPairedDevices();
    await scanBleDevices();

    setState(() {
      scanning = false;
    });
  }

  Future<void> loadClassicPairedDevices() async {
    try {
      final result = await classicChannel.invokeMethod('getPairedDevices');

      for (final item in result) {
        classicDevices.add(
          BtDeviceItem(
            name: item['name'] ?? 'Unknown Classic Device',
            id: item['address'] ?? '',
            type: 'Classic',
          ),
        );
      }
    } catch (_) {}
  }

  Future<void> scanBleDevices() async {
    scanSub?.cancel();

    scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        final name = r.device.platformName.isNotEmpty
            ? r.device.platformName
            : 'Unknown BLE Device';

        final id = r.device.remoteId.str;

        if (!bleDevices.any((d) => d.id == id)) {
          bleDevices.add(
            BtDeviceItem(name: name, id: id, type: 'BLE'),
          );
        }
      }
      setState(() {});
    });

    try {
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 8),
      );
      await Future.delayed(const Duration(seconds: 8));
    } catch (_) {}
  }

  void openControlPage(BtDeviceItem device) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ControlPage(device: device),
      ),
    );
  }

  Widget buildList(String title, List<BtDeviceItem> devices) {
    return Card(
      margin: const EdgeInsets.all(12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style:
                const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (devices.isEmpty)
              const Text('No devices found')
            else
              ...devices.map(
                    (d) => ListTile(
                  leading: const Icon(Icons.bluetooth),
                  title: Text(d.name),
                  subtitle: Text('${d.type}\n${d.id}'),
                  isThreeLine: true,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => openControlPage(d),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allCount = bleDevices.length + classicDevices.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('HC-05 Simple Scanner'),
      ),
      body: ListView(
        children: [
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.all(12),
            child: ElevatedButton.icon(
              onPressed: scanning ? null : scan,
              icon: const Icon(Icons.search),
              label:
              Text(scanning ? 'Scanning...' : 'Scan BLE + Paired Classic'),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Text('Total devices found: $allCount'),
          ),
          buildList('Paired Classic Devices', classicDevices),
          buildList('BLE Devices', bleDevices),
        ],
      ),
    );
  }
}

/* ===================== CONTROL PAGE ===================== */

class ControlPage extends StatefulWidget {
  final BtDeviceItem device;

  const ControlPage({super.key, required this.device});

  @override
  State<ControlPage> createState() => _ControlPageState();
}

class _ControlPageState extends State<ControlPage> {
  static const MethodChannel classicChannel =
  MethodChannel('classic_bluetooth');

  BluetoothDevice? bleDevice;
  BluetoothCharacteristic? bleChar;
  StreamSubscription<List<int>>? notifySub;

  final ScrollController scrollController = ScrollController();

  bool connecting = false;
  bool connected = false;

  String logText = 'Not connected.';
  final TextEditingController customController = TextEditingController();

  final Guid serviceUuid = Guid('ffe0');
  final Guid charUuid = Guid('ffe1');

  String timestamp() {
    final now = DateTime.now();
    return '${now.hour}:${now.minute}:${now.second}';
  }

  void addLog(String text) {
    if (!mounted) return;

    setState(() {
      logText += '\n[${timestamp()}] $text';
    });

    Future.delayed(const Duration(milliseconds: 100), () {
      if (scrollController.hasClients) {
        scrollController.jumpTo(scrollController.position.maxScrollExtent);
      }
    });
  }

  void clearLog() {
    setState(() {
      logText = '';
    });
  }

  @override
  void initState() {
    super.initState();
    connect();
  }

  @override
  void dispose() {
    notifySub?.cancel();
    scrollController.dispose();
    customController.dispose();
    disconnect();
    super.dispose();
  }

  Future<void> connect() async {
    if (widget.device.type == 'Classic') {
      // skip for now
    } else {
      await connectBle();
    }
  }

  Future<void> connectBle() async {
    try {
      bleDevice = BluetoothDevice.fromId(widget.device.id);

      await bleDevice!.connect(
        timeout: const Duration(seconds: 10),
        autoConnect: false,
        license: License.free,
      );

      final services = await bleDevice!.discoverServices();

      for (final s in services) {
        if (s.uuid.toString().toLowerCase() == serviceUuid.toString()) {
          for (final c in s.characteristics) {
            if (c.uuid.toString().toLowerCase() == charUuid.toString()) {
              bleChar = c;
            }
          }
        }
      }

      if (bleChar!.properties.notify) {
        await bleChar!.setNotifyValue(true);

        notifySub = bleChar!.lastValueStream.listen((value) {
          if (value.isNotEmpty) {
            final received = String.fromCharCodes(value);
            addLog('RX: $received');
          }
        });
      }

      setState(() => connected = true);
      addLog('Connected');
    } catch (e) {
      addLog('Error: $e');
    }
  }

  Future<void> send(String text) async {
    if (!connected) return;

    await bleChar!.write(
      ('$text\n').codeUnits,
      withoutResponse: bleChar!.properties.writeWithoutResponse,
    );

    addLog('TX: $text');
  }

  Future<void> disconnect() async {
    await notifySub?.cancel();
    await bleDevice?.disconnect();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('HC-05 Control')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Text(widget.device.name),
            Text(widget.device.id),

            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => send('1'),
                    child: const Text('ON'),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => send('0'),
                    child: const Text('OFF'),
                  ),
                ),
              ],
            ),

            TextField(controller: customController),

            ElevatedButton(
              onPressed: () => send(customController.text),
              child: const Text('Send'),
            ),

            OutlinedButton(
              onPressed: clearLog,
              child: const Text('Clear Log'),
            ),

            Expanded(
              child: SingleChildScrollView(
                controller: scrollController,
                child: SelectableText(logText),
              ),
            ),
          ],
        ),
      ),
    );
  }
}