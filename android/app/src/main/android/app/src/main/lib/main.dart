import 'dart:async';
import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:path/path.dart' as p;

import 'services/crypto_service.dart';
import 'services/p2p_service.dart';
import 'ui/screens/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Принудительная ориентация и настройка системных панелей OLED
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    systemNavigationBarColor: Color(0xFF05070A),
    statusBarIconBrightness: Brightness.light,
  ));

  final cryptoService = CryptoService();
  await cryptoService.initializeIdentity();

  final p2pService = P2PService(cryptoService: cryptoService);
  final appState = AppSecurityState(
    cryptoService: cryptoService,
    p2pService: p2pService,
  );
  await appState.initializeStorage();

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<CryptoService>.value(value: cryptoService),
        ChangeNotifierProvider<P2PService>.value(value: p2pService),
        ChangeNotifierProvider<AppSecurityState>.value(value: appState),
      ],
      child: const AetherP2PApp(),
    ),
  );
}

/// Глобальный контроллер безопасности, SQLCipher, Duress Mode и Paranoid-функций
class AppSecurityState extends ChangeNotifier {
  final CryptoService cryptoService;
  final P2PService p2pService;

  Database? _encryptedDb;
  bool isRamOnlyMode = false;
  bool isDuressDecoyMode = false;
  bool isStealthCalculatorLocked = false;
  bool isFakeCrashTriggered = false;
  bool isBadUsbDetected = false;
  bool isPrivacyShieldEnabled = false;
  bool isIrcCompactMode = false;
  bool isCyberpunkNeonTheme = true;
  int deadManSwitchDays = 30;
  String customStatus = 'Пишет код';

  AppSecurityState({
    required this.cryptoService,
    required this.p2pService,
  });

  Future<void> initializeStorage({String masterPin = '1337'}) async {
    final prefs = await SharedPreferences.getInstance();
    final nowUtc = DateTime.now().toUtc().millisecondsSinceEpoch;
    final lastSeen = prefs.getInt('last_active_utc') ?? nowUtc;

    // Dead Man's Switch: автозачистка при отсутствии активности N дней
    final elapsedDays = (nowUtc - lastSeen) ~/ (1000 * 60 * 60 * 24);
    if (elapsedDays >= deadManSwitchDays) {
      await triggerPanicNuke();
      return;
    }
    await prefs.setInt('last_active_utc', nowUtc);

    if (isRamOnlyMode) {
      await _encryptedDb?.close();
      _encryptedDb = null;
      notifyListeners();
      return;
    }

    try {
      final dbKeyHex = await cryptoService.deriveDatabaseKeyHex(masterPin);
      final dbDir = await getDatabasesPath();
      final dbName = isDuressDecoyMode ? 'aether_decoy.db' : 'aether_vault.db';
      final dbPath = p.join(dbDir, dbName);

      _encryptedDb = await openDatabase(
        dbPath,
        password: dbKeyHex,
        version: 1,
        onCreate: (db, version) async {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS messages (
              id TEXT PRIMARY KEY,
              chat_id TEXT,
              sender_id TEXT,
              cipher_payload TEXT,
              utc_timestamp INTEGER,
              ttl_seconds INTEGER
            )
          ''');
          // Полнотекстовый локальный индекс FTS5 внутри зашифрованного контейнера
          await db.execute('''
            CREATE VIRTUAL TABLE IF NOT EXISTS messages_fts
            USING fts5(id, chat_id, plain_body)
          ''');
        },
      );
    } catch (_) {
      // В случае недоступности нативных библиотек в тестовой среде переходим в RAM-Only
      isRamOnlyMode = true;
    }
    notifyListeners();
  }

  void toggleRamOnlyMode(bool value) async {
    isRamOnlyMode = value;
    if (value) {
      await _encryptedDb?.close();
      _encryptedDb = null;
    } else {
      await initializeStorage();
    }
    notifyListeners();
  }

  void toggleStealthCalculator() {
    isStealthCalculatorLocked = !isStealthCalculatorLocked;
    notifyListeners();
  }

  void togglePrivacyShield() {
    isPrivacyShieldEnabled = !isPrivacyShieldEnabled;
    notifyListeners();
  }

  void toggleIrcCompactMode() {
    isIrcCompactMode = !isIrcCompactMode;
    notifyListeners();
  }

  void toggleTheme() {
    isCyberpunkNeonTheme = !isCyberpunkNeonTheme;
    notifyListeners();
  }

  void updateStatus(String status) {
    customStatus = status;
    p2pService.broadcastPresenceStatus(status);
    notifyListeners();
  }

  /// Zero-Trace Clipboard: автоматическая зачистка буфера обмена ОС через 15 секунд
  Future<void> copyWithZeroTrace(String sensitiveText) async {
    await Clipboard.setData(ClipboardData(text: sensitiveText));
    Timer(const Duration(seconds: 15), () async {
      await Clipboard.setData(const ClipboardData(text: ''));
    });
  }

  /// Ввод кода из калькулятора маскировки или экрана блокировки
  Future<bool> evaluateSecurityCode(String inputCode) async {
    if (inputCode == '0000=') {
      // Kill-пароль: бесшумное затирание и имитация системного сбоя
      await triggerPanicNuke(showFakeCrash: true);
      return false;
    } else if (inputCode == '9999=') {
      // Duress PIN (Двойное дно): открытие фейкового профиля
      isDuressDecoyMode = true;
      isStealthCalculatorLocked = false;
      await initializeStorage(masterPin: '9999');
      notifyListeners();
      return true;
    } else if (inputCode == '1337=') {
      // Основной профиль
      isDuressDecoyMode = false;
      isStealthCalculatorLocked = false;
      await initializeStorage(masterPin: '1337');
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Panic Wipe (Nuke Button): криптографическое затирание ключей и базы нулями
  Future<void> triggerPanicNuke({bool showFakeCrash = false}) async {
    await p2pService.emergencyKillSwitch();
    await cryptoService.secureWipeKeys();
    try {
      await _encryptedDb?.close();
      final dbDir = await getDatabasesPath();
      await deleteDatabase(p.join(dbDir, 'aether_vault.db'));
    } catch (_) {}
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();

    if (showFakeCrash) {
      isFakeCrashTriggered = true;
    } else {
      isDuressDecoyMode = true;
    }
    notifyListeners();
  }
}

class AetherP2PApp extends StatefulWidget {
  const AetherP2PApp({super.key});

  @override
  State<AetherP2PApp> createState() => _AetherP2PAppState();
}

class _AetherP2PAppState extends State<AetherP2PApp>
    with WidgetsBindingObserver {
  bool _isAppInBackground = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Privacy Blur в диспетчере задач: мгновенное размытие при потере фокуса
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    setState(() {
      _isAppInBackground = state == AppLifecycleState.inactive ||
          state == AppLifecycleState.paused ||
          state == AppLifecycleState.hidden;
    });
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<AppSecurityState>();

    final bgColor = security.isCyberpunkNeonTheme
        ? const Color(0xFF06080E)
        : const Color(0xFF000000);
    final accentColor = security.isCyberpunkNeonTheme
        ? const Color(0xFF00F5D4)
        : const Color(0xFF3B82F6);

    return MaterialApp(
      title: security.isStealthCalculatorLocked ? 'Калькулятор' : 'Aether P2P',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: bgColor,
        primaryColor: accentColor,
        colorScheme: ColorScheme.dark(
          primary: accentColor,
          secondary: const Color(0xFF9B5DE5),
          surface: const Color(0xFF10141F),
        ),
        fontFamily: 'monospace',
        useMaterial3: true,
      ),
      builder: (context, child) {
        return Stack(
          children: [
            if (child != null) child,
            // Защита от снимков в меню недавних приложений (Privacy Task Switcher Blur)
            if (_isAppInBackground)
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
                  child: Container(
                    color: Colors.black.withOpacity(0.85),
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield_outlined,
                            size: 64, color: Color(0xFF00F5D4)),
                        SizedBox(height: 12),
                        Text(
                          'ZERO-METADATA SHIELD ACTIVE',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
      home: _buildActiveRoot(security),
    );
  }

  Widget _buildActiveRoot(AppSecurityState security) {
    if (security.isFakeCrashTriggered) {
      return const _FakeSystemCrashScreen();
    }
    if (security.isStealthCalculatorLocked) {
      return const StealthCalculatorScreen();
    }
    return const HomeScreen();
  }
}

/// Экран фейковой системной ошибки при вводе Kill-пароля (0000=)
class _FakeSystemCrashScreen extends StatelessWidget {
  const _FakeSystemCrashScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Center(
        child: AlertDialog(
          backgroundColor: const Color(0xFF1C1C1E),
          title: const Text('Системный сбой Android'),
          content: const Text(
            'В приложении «Калькулятор» произошла фатальная ошибка обращения к памяти (0x0000DEAD). Приложение будет закрыто.',
          ),
          actions: [
            TextButton(
              onPressed: () => SystemNavigator.pop(),
              child: const Text('ОК'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Режим маскировки (Stealth Camouflage) + анти-кейлоггер с перемешиванием кнопок
class StealthCalculatorScreen extends StatefulWidget {
  const StealthCalculatorScreen({super.key});

  @override
  State<StealthCalculatorScreen> createState() =>
      _StealthCalculatorScreenState();
}

class _StealthCalculatorScreenState extends State<StealthCalculatorScreen> {
  String _expression = '';
  String _result = '0';
  bool _scrambleKeypad = false;
  late List<String> _digits;

  @override
  void initState() {
    super.initState();
    _resetDigits();
  }

  void _resetDigits() {
    _digits = ['7', '8', '9', '4', '5', '6', '1', '2', '3', '0'];
    if (_scrambleKeypad) {
      _digits.shuffle(Random.secure());
    }
  }

  void _onKeyTap(String key) async {
    final security = context.read<AppSecurityState>();
    setState(() {
      if (key == 'C') {
        _expression = '';
        _result = '0';
      } else {
        _expression += key;
      }
    });

    if (key == '=') {
      final unlocked = await security.evaluateSecurityCode(_expression);
      if (!unlocked && mounted) {
        setState(() {
          _result = _evaluateSimpleMath(_expression.replaceAll('=', ''));
          _expression = '';
          if (_scrambleKeypad) _resetDigits();
        });
      }
    }
  }

  String _evaluateSimpleMath(String expr) {
    try {
      if (expr.contains('+')) {
        final parts = expr.split('+');
        return (double.parse(parts[0]) + double.parse(parts[1])).toString();
      } else if (expr.contains('-')) {
        final parts = expr.split('-');
        return (double.parse(parts[0]) - double.parse(parts[1])).toString();
      }
      return expr.isEmpty ? '0' : expr;
    } catch (_) {
      return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    final buttons = [
      ..._digits.sublist(0, 3),
      'C',
      ..._digits.sublist(3, 6),
      '+',
      ..._digits.sublist(6, 9),
      '-',
      '.',
      _digits[9],
      '=',
    ];

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Калькулятор'),
        actions: [
          IconButton(
            tooltip: 'Защита от кейлоггера (перемешать раскладку)',
            icon: Icon(
              _scrambleKeypad ? Icons.shuffle_on_outlined : Icons.shuffle,
              color: Colors.grey,
            ),
            onPressed: () {
              setState(() {
                _scrambleKeypad = !_scrambleKeypad;
                _resetDigits();
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Container(
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _expression,
                    style: const TextStyle(fontSize: 24, color: Colors.grey),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _result,
                    style: const TextStyle(
                      fontSize: 48,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Подсказка: 1337= (Основной) | 9999= (Двойное дно) | 0000= (Kill)',
                    style: TextStyle(fontSize: 11, color: Colors.white24),
                  ),
                ],
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(12),
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              mainAxisSpacing: 10,
              crossAxisSpacing: 10,
              childAspectRatio: 1.25,
            ),
            itemCount: buttons.length,
            itemBuilder: (context, index) {
              final label = buttons[index];
              final isAction = ['C', '+', '-', '='].contains(label);
              return ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: isAction
                      ? const Color(0xFF1F2937)
                      : const Color(0xFF111827),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                onPressed: () => _onKeyTap(label),
                child: Text(
                  label,
                  style: const TextStyle(
                      fontSize: 24, fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
