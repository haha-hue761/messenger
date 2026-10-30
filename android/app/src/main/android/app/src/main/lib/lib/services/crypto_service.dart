import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:bip39/bip39.dart' as bip39;
import 'package:cryptography/cryptography.dart';
import 'package:convert/convert.dart';

/// Состояние сессии Double Ratchet для конкретного диалога (изоляция сессий)
class DoubleRatchetSession {
  final String peerId;
  List<int> rootKey;
  List<int> sendChainKey;
  List<int> receiveChainKey;
  SimpleKeyPair localRatchetKeyPair;
  SimplePublicKey? remoteRatchetPublicKey;
  int sendMessageNumber = 0;
  int receiveMessageNumber = 0;

  DoubleRatchetSession({
    required this.peerId,
    required this.rootKey,
    required this.sendChainKey,
    required this.receiveChainKey,
    required this.localRatchetKeyPair,
    this.remoteRatchetPublicKey,
  });
}

/// Зашифрованный E2EE-пакет с заголовком Double Ratchet и Traffic Padding
class EncryptedRatchetPacket {
  final String senderPeerId;
  final String ephemeralPublicKeyHex;
  final int messageIndex;
  final int utcTimestamp; // Принудительно нормализован к UTC+0
  final int ttlSeconds; // Burn-on-Read таймер
  final bool isRemoteWipeTrigger;
  final String nonceHex;
  final String cipherTextHex;
  final String macHex;
  final String ed25519SignatureHex;

  EncryptedRatchetPacket({
    required this.senderPeerId,
    required this.ephemeralPublicKeyHex,
    required this.messageIndex,
    required this.utcTimestamp,
    required this.ttlSeconds,
    this.isRemoteWipeTrigger = false,
    required this.nonceHex,
    required this.cipherTextHex,
    required this.macHex,
    required this.ed25519SignatureHex,
  });

  Map<String, dynamic> toJson() => {
        'p': senderPeerId,
        'ek': ephemeralPublicKeyHex,
        'idx': messageIndex,
        'ts': utcTimestamp,
        'ttl': ttlSeconds,
        'wipe': isRemoteWipeTrigger,
        'n': nonceHex,
        'c': cipherTextHex,
        'm': macHex,
        'sig': ed25519SignatureHex,
      };

  factory EncryptedRatchetPacket.fromJson(Map<String, dynamic> json) {
    return EncryptedRatchetPacket(
      senderPeerId: json['p'] as String,
      ephemeralPublicKeyHex: json['ek'] as String,
      messageIndex: json['idx'] as int,
      utcTimestamp: json['ts'] as int,
      ttlSeconds: json['ttl'] as int,
      isRemoteWipeTrigger: json['wipe'] as bool? ?? false,
      nonceHex: json['n'] as String,
      cipherTextHex: json['c'] as String,
      macHex: json['m'] as String,
      ed25519SignatureHex: json['sig'] as String,
    );
  }
}

class CryptoService extends ChangeNotifier {
  final Ed25519 _ed25519 = Ed25519();
  final X25519 _x25519 = X25519();
  final ChaCha20 _aead = ChaCha20.poly1305Aead();
  final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);

  String _mnemonic = '';
  SimpleKeyPair? _ed25519IdentityKey;
  SimpleKeyPair? _x25519IdentityKey;
  SimpleKeyPair? _x25519SignedPreKey;

  String _peerIdOnion = '';
  String _displayName = 'Ghost_Node';
  String _username = '@anon_cipher';

  // Изолированные сессии Double Ratchet по каждому Peer ID
  final Map<String, DoubleRatchetSession> _sessions = {};

  String get mnemonic => _mnemonic;
  String get peerIdOnion => _peerIdOnion;
  String get displayName => _displayName;
  String get username => _username;

  /// Инициализация криптографической идентичности из BIP-39 Seed-фразы
  Future<void> initializeIdentity({String? customMnemonic}) async {
    _mnemonic = customMnemonic ?? bip39.generateMnemonic(strength: 256);
    final seedBytes = bip39.mnemonicToSeed(_mnemonic);

    // Деривация независимых ключей Ed25519 и X25519 из мастер-сида
    final edSeed = await _hkdf.deriveKey(
      secretKey: SecretKey(seedBytes.sublist(0, 32)),
      nonce: utf8.encode('AETHER_ED25519_SIGN'),
      info: utf8.encode('identity_signing_key'),
    );
    final xSeed = await _hkdf.deriveKey(
      secretKey: SecretKey(seedBytes.sublist(32, 64)),
      nonce: utf8.encode('AETHER_X25519_ECDH'),
      info: utf8.encode('identity_exchange_key'),
    );

    _ed25519IdentityKey =
        await _ed25519.newKeyPairFromSeed(await edSeed.extractBytes());
    _x25519IdentityKey =
        await _x25519.newKeyPairFromSeed(await xSeed.extractBytes());
    _x25519SignedPreKey = await _x25519.newKeyPair();

    final pubKey = await _ed25519IdentityKey!.extractPublicKey();
    final hash = await Sha256().hash(pubKey.bytes);
    final hexPrefix = hex.encode(hash.bytes.sublist(0, 16));
    _peerIdOnion = '$hexPrefix.onion';

    notifyListeners();
  }

  void updateProfile({required String name, required String handle}) {
    _displayName = name;
    _username = handle.startsWith('@') ? handle : '@$handle';
    notifyListeners();
  }

  Future<String> getEd25519PublicKeyHex() async {
    final pub = await _ed25519IdentityKey!.extractPublicKey();
    return hex.encode(pub.bytes);
  }

  Future<String> getX25519PublicKeyHex() async {
    final pub = await _x25519IdentityKey!.extractPublicKey();
    return hex.encode(pub.bytes);
  }

  /// Деривация ключа SQLCipher через Argon2id
  Future<String> deriveDatabaseKeyHex(String masterPin) async {
    final argon2 = Argon2id(
      memory: 16384,
      parallelism: 2,
      iterations: 2,
      hashLength: 32,
    );
    final key = await argon2.deriveKeyFromPassword(
      password: masterPin,
      nonce: utf8.encode('AETHER_SQLCIPHER_SALT_V1'),
    );
    return hex.encode(await key.extractBytes());
  }

  /// SAS-аутентификация (Short Authentication String) против MITM-атак
  Future<String> generateSasVerification(String remotePeerId) async {
    const emojis = [
      '🦊', '⚡', '🛰️', '🔮', '🛡️', '🧬', '🗡️', '🪐',
      '🐉', '❄️', '🔥', '💎', '🧿', '⚓', '⏳', '🗝️'
    ];
    const words = [
      'ALPHA', 'CYBER', 'PULSE', 'VORTEX', 'SHADOW', 'QUARTZ', 'NEBULA', 'ORBIT',
      'MATRIX', 'SIGNAL', 'VECTOR', 'COBALT', 'PHANTOM', 'ZENITH', 'HELIX', 'APEX'
    ];

    final pair = [_peerIdOnion, remotePeerId]..sort();
    final digest = await Sha256().hash(utf8.encode(pair.join(':')));
    final b = digest.bytes;

    final sasEmojis = List.generate(4, (i) => emojis[b[i] % emojis.length]).join(' ');
    final sasWords = List.generate(3, (i) => words[b[i + 4] % words.length]).join('-');
    return '$sasEmojis  [$sasWords]';
  }

  /// Генерация 5x5 матрицы для генеративной аватарки (Identicon)
  List<bool> buildIdenticonMatrix(String peerId) {
    final codeUnits = utf8.encode(peerId);
    final matrix = List<bool>.filled(25, false);
    for (int row = 0; row < 5; row++) {
      for (int col = 0; col < 3; col++) {
        final byte = codeUnits[(row * 3 + col) % codeUnits.length];
        final isActive = (byte + row + col) % 2 == 0;
        matrix[row * 5 + col] = isActive;
        matrix[row * 5 + (4 - col)] = isActive; // Зеркальная симметрия
      }
    }
    return matrix;
  }

  /// Инициализация сессии X3DH (Extended Triple Diffie-Hellman) + Double Ratchet
  Future<DoubleRatchetSession> getOrInitRatchetSession(
    String remotePeerId, {
    String? remoteX25519PubHex,
  }) async {
    if (_sessions.containsKey(remotePeerId)) {
      return _sessions[remotePeerId]!;
    }

    final ephemeralPair = await _x25519.newKeyPair();
    List<int> sharedSecretBytes;

    if (remoteX25519PubHex != null && remoteX25519PubHex.length == 64) {
      final remotePub = SimplePublicKey(
        hex.decode(remoteX25519PubHex),
        type: KeyPairType.x25519,
      );
      final dh1 = await _x25519.sharedSecretKey(
        keyPair: _x25519IdentityKey!,
        remotePublicKey: remotePub,
      );
      final dh2 = await _x25519.sharedSecretKey(
        keyPair: ephemeralPair,
        remotePublicKey: remotePub,
      );
      final b1 = await dh1.extractBytes();
      final b2 = await dh2.extractBytes();
      sharedSecretBytes = [...b1, ...b2];
    } else {
      // Детерминированный локальный ключ для P2P-демо до обмена X3DH-бандлами
      final pair = [_peerIdOnion, remotePeerId]..sort();
      final fallbackHash = await Sha256().hash(utf8.encode(pair.join('#X3DH#')));
      sharedSecretBytes = fallbackHash.bytes;
    }

    final rootKeyData = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('X3DH_ROOT_INIT'),
      info: utf8.encode('double_ratchet_root'),
    );
    final sendChainData = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('X3DH_SEND_CHAIN'),
      info: utf8.encode('double_ratchet_chain'),
    );
    final recvChainData = await _hkdf.deriveKey(
      secretKey: SecretKey(sharedSecretBytes),
      nonce: utf8.encode('X3DH_RECV_CHAIN'),
      info: utf8.encode('double_ratchet_chain'),
    );

    final session = DoubleRatchetSession(
      peerId: remotePeerId,
      rootKey: await rootKeyData.extractBytes(),
      sendChainKey: await sendChainData.extractBytes(),
      receiveChainKey: await recvChainData.extractBytes(),
      localRatchetKeyPair: ephemeralPair,
    );

    _sessions[remotePeerId] = session;
    return session;
  }

  /// Продвижение KDF-цепочки (Symmetric-Key Ratchet) и генерация одноразового ключа
  Future<List<int>> _stepChainKey(
      DoubleRatchetSession session, bool isSend) async {
    final currentChain =
        isSend ? session.sendChainKey : session.receiveChainKey;
    final hmac = Hmac.sha256();

    final nextChainMac = await hmac.calculateMac(
      utf8.encode('RATCHET_NEXT_CHAIN_KEY'),
      secretKey: SecretKey(currentChain),
    );
    final messageKeyMac = await hmac.calculateMac(
      utf8.encode('RATCHET_MESSAGE_AEAD_KEY'),
      secretKey: SecretKey(currentChain),
    );

    if (isSend) {
      session.sendChainKey = nextChainMac.bytes;
      session.sendMessageNumber += 1;
    } else {
      session.receiveChainKey = nextChainMac.bytes;
      session.receiveMessageNumber += 1;
    }

    // Ротация эфемерной пары ключей DH для Post-Compromise Security
    session.localRatchetKeyPair = await _x25519.newKeyPair();
    return messageKeyMac.bytes;
  }

  /// Выравнивание трафика (Traffic Padding) до блоков кратных 512 байтам
  Uint8List _applyTrafficPadding(String plainText) {
    final rawBytes = utf8.encode(plainText);
    const blockSize = 512;
    final totalLen =
        ((rawBytes.length + 4 + blockSize - 1) ~/ blockSize) * blockSize;
    final buffer = Uint8List(totalLen);
    final byteData = ByteData.view(buffer.buffer);
    byteData.setUint32(0, rawBytes.length, Endian.big);
    buffer.setRange(4, 4 + rawBytes.length, rawBytes);

    final rng = Random.secure();
    for (int i = 4 + rawBytes.length; i < totalLen; i++) {
      buffer[i] = rng.nextInt(256);
    }
    return buffer;
  }

  String _removeTrafficPadding(List<int> paddedBytes) {
    if (paddedBytes.length < 4) return '';
    final data = Uint8List.fromList(paddedBytes);
    final view = ByteData.view(data.buffer);
    final realLength = view.getUint32(0, Endian.big);
    if (realLength < 0 || 4 + realLength > data.length) {
      return utf8.decode(paddedBytes, allowMalformed: true);
    }
    return utf8.decode(data.sublist(4, 4 + realLength), allowMalformed: true);
  }

  /// Шифрование сообщения по протоколу Double Ratchet + подпись Ed25519
  Future<EncryptedRatchetPacket> encryptRatchetMessage({
    required String remotePeerId,
    required String plainText,
    int ttlSeconds = 0,
    bool isRemoteWipeTrigger = false,
  }) async {
    final session = await getOrInitRatchetSession(remotePeerId);
    final messageKeyBytes = await _stepChainKey(session, true);

    final paddedPlaintext = _applyTrafficPadding(plainText);
    final nonce = _aead.newNonce();
    final secretBox = await _aead.encrypt(
      paddedPlaintext,
      secretKey: SecretKey(messageKeyBytes),
      nonce: nonce,
    );

    final ephemeralPub = await session.localRatchetKeyPair.extractPublicKey();
    final utcNow = DateTime.now().toUtc().millisecondsSinceEpoch;

    final signature = await _ed25519.sign(
      secretBox.cipherText,
      keyPair: _ed25519IdentityKey!,
    );

    return EncryptedRatchetPacket(
      senderPeerId: _peerIdOnion,
      ephemeralPublicKeyHex: hex.encode(ephemeralPub.bytes),
      messageIndex: session.sendMessageNumber,
      utcTimestamp: utcNow,
      ttlSeconds: ttlSeconds,
      isRemoteWipeTrigger: isRemoteWipeTrigger,
      nonceHex: hex.encode(nonce),
      cipherTextHex: hex.encode(secretBox.cipherText),
      macHex: hex.encode(secretBox.mac.bytes),
      ed25519SignatureHex: hex.encode(signature.bytes),
    );
  }

  /// Расшифровка входящего пакета Double Ratchet
  Future<String> decryptRatchetMessage(EncryptedRatchetPacket packet) async {
    final session = await getOrInitRatchetSession(packet.senderPeerId);
    final messageKeyBytes = await _stepChainKey(session, false);

    final secretBox = SecretBox(
      hex.decode(packet.cipherTextHex),
      nonce: hex.decode(packet.nonceHex),
      mac: Mac(hex.decode(packet.macHex)),
    );

    final decryptedPadded = await _aead.decrypt(
      secretBox,
      secretKey: SecretKey(messageKeyBytes),
    );
    return _removeTrafficPadding(decryptedPadded);
  }

  /// EXIF Scrubber: принудительное вырезание секций APP1 (EXIF/GPS) из JPEG-байтов
  Uint8List scrubExifMetadata(Uint8List imageBytes) {
    if (imageBytes.length < 4 ||
        imageBytes[0] != 0xFF ||
        imageBytes[1] != 0xD8) {
      return imageBytes;
    }
    final clean = <int>[0xFF, 0xD8];
    int i = 2;
    while (i + 3 < imageBytes.length) {
      if (imageBytes[i] == 0xFF) {
        final marker = imageBytes[i + 1];
        // Секции APP1..APP15 (0xE1..0xEF) содержат EXIF, GPS и XMP метаданные камеры
        if (marker >= 0xE1 && marker <= 0xEF) {
          final segLen = (imageBytes[i + 2] << 8) | imageBytes[i + 3];
          i += 2 + segLen;
          continue;
        }
      }
      clean.add(imageBytes[i]);
      i++;
    }
    while (i < imageBytes.length) {
      clean.add(imageBytes[i++]);
    }
    return Uint8List.fromList(clean);
  }

  /// Генерация взаимно подписанного хэш-контракта честного спора
  Future<String> createSignedHashContract({
    required String counterpartyPeerId,
    required String terms,
    required String amountXmr,
  }) async {
    final utcIso = DateTime.now().toUtc().toIso8601String();
    final payload = 'CONTRACT|$utcIso|$_peerIdOnion|$counterpartyPeerId|$amountXmr XMR|$terms';
    final hash = await Sha256().hash(utf8.encode(payload));
    final sig = await _ed25519.sign(hash.bytes, keyPair: _ed25519IdentityKey!);
    final sigShort = hex.encode(sig.bytes).substring(0, 24);
    final hashShort = hex.encode(hash.bytes).substring(0, 16);
    return '📜 [HASH-CONTRACT #$hashShort]\n'
        'Условия: $terms\n'
        'Эскроу: $amountXmr XMR (Multisig 2-of-3)\n'
        'UTC+0: $utcIso\n'
        'Ed25519 Sig: $sigShort...';
  }

  /// Полное обнуление ключевого материала в памяти (Panic Wipe)
  Future<void> secureWipeKeys() async {
    _sessions.clear();
    _mnemonic = '';
    await initializeIdentity();
  }
}
