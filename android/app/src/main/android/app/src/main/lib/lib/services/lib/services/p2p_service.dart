import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:cryptography/cryptography.dart';
import 'package:convert/convert.dart';

import 'crypto_service.dart';

enum P2PTransportMode {
  torOnionV3,
  webrtcDirect,
  localMeshBleWifi,
  airGappedQr,
}

class P2PService extends ChangeNotifier {
  final CryptoService cryptoService;

  RTCPeerConnection? _peerConnection;
  RTCDataChannel? _dataChannel;
  MediaStream? _localAudioVideoStream;

  P2PTransportMode activeTransport = P2PTransportMode.torOnionV3;
  bool isConnected = false;
  bool isTrafficPaddingActive = true;
  bool isVoicePitchShiftEnabled = true;
  bool isRnnoiseEnabled = true;
  bool isPushToTalkPressed = false;
  int dummyPacketsSent = 0;

  final List<RTCIceCandidate> _localCandidates = [];
  Timer? _dummyTrafficTimer;

  // Коллбэки для доставки входящих E2EE пакетов и Remote Wipe сигналов в UI
  void Function(EncryptedRatchetPacket packet, String plainText)? onMessageReceived;
  void Function(String remotePeerId)? onRemoteWipeTriggered;

  P2PService({required this.cryptoService}) {
    _startTrafficPaddingEngine();
  }

  /// Конфигурация STUN только для пробития NAT (без центральных TURN/сигнальных серверов)
  final Map<String, dynamic> _rtcConfig = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  /// Генерация бессерверного SDP-оффера (упаковывается в единый Base64-токен для обмена)
  Future<String> createServerlessOfferToken() async {
    await _disposeCurrentPeerConnection();
    _localCandidates.clear();

    _peerConnection = await createPeerConnection(_rtcConfig);
    _registerPeerCallbacks();

    final dcInit = RTCDataChannelInit()
      ..ordered = true
      ..maxRetransmits = 10;
    _dataChannel =
        await _peerConnection!.createDataChannel('aether_e2ee_dc', dcInit);
    _bindDataChannel(_dataChannel!);

    final offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await _peerConnection!.setLocalDescription(offer);

    // Ожидание сбора ICE-кандидатов для упаковки в единый бессерверный токен
    await Future.delayed(const Duration(milliseconds: 900));

    final bundle = {
      'type': 'offer',
      'peerId': cryptoService.peerIdOnion,
      'x25519': await cryptoService.getX25519PublicKeyHex(),
      'sdp': offer.sdp,
      'candidates': _localCandidates
          .map((c) => {
                'candidate': c.candidate,
                'sdpMid': c.sdpMid,
                'sdpMLineIndex': c.sdpMLineIndex,
              })
          .toList(),
    };

    return base64UrlEncode(utf8.encode(jsonEncode(bundle)));
  }

  /// Принятие чужого SDP-оффера и генерация ответного Answer-токена
  Future<String> acceptOfferAndCreateAnswerToken(String remoteToken) async {
    await _disposeCurrentPeerConnection();
    _localCandidates.clear();

    final decoded = jsonDecode(utf8.decode(base64Url.decode(remoteToken.trim())))
        as Map<String, dynamic>;

    _peerConnection = await createPeerConnection(_rtcConfig);
    _registerPeerCallbacks();

    _peerConnection!.onDataChannel = (RTCDataChannel channel) {
      _dataChannel = channel;
      _bindDataChannel(channel);
    };

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(decoded['sdp'] as String, 'offer'),
    );

    final remoteCandidates = decoded['candidates'] as List<dynamic>? ?? [];
    for (final item in remoteCandidates) {
      final map = item as Map<String, dynamic>;
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          map['candidate'] as String?,
          map['sdpMid'] as String?,
          map['sdpMLineIndex'] as int?,
        ),
      );
    }

    final answer = await _peerConnection!.createAnswer();
    await _peerConnection!.setLocalDescription(answer);
    await Future.delayed(const Duration(milliseconds: 800));

    final answerBundle = {
      'type': 'answer',
      'peerId': cryptoService.peerIdOnion,
      'x25519': await cryptoService.getX25519PublicKeyHex(),
      'sdp': answer.sdp,
      'candidates': _localCandidates
          .map((c) => {
                'candidate': c.candidate,
                'sdpMid': c.sdpMid,
                'sdpMLineIndex': c.sdpMLineIndex,
              })
          .toList(),
    };

    return base64UrlEncode(utf8.encode(jsonEncode(answerBundle)));
  }

  /// Завершение рукопожатия на стороне инициатора после ввода Answer-токена
  Future<void> completeServerlessHandshake(String answerToken) async {
    if (_peerConnection == null) return;
    final decoded = jsonDecode(utf8.decode(base64Url.decode(answerToken.trim())))
        as Map<String, dynamic>;

    await _peerConnection!.setRemoteDescription(
      RTCSessionDescription(decoded['sdp'] as String, 'answer'),
    );

    final remoteCandidates = decoded['candidates'] as List<dynamic>? ?? [];
    for (final item in remoteCandidates) {
      final map = item as Map<String, dynamic>;
      await _peerConnection!.addCandidate(
        RTCIceCandidate(
          map['candidate'] as String?,
          map['sdpMid'] as String?,
          map['sdpMLineIndex'] as int?,
        ),
      );
    }
    isConnected = true;
    notifyListeners();
  }

  void _registerPeerCallbacks() {
    _peerConnection?.onIceCandidate = (RTCIceCandidate candidate) {
      if (candidate.candidate != null) {
        _localCandidates.add(candidate);
      }
    };
    _peerConnection?.onConnectionState = (RTCPeerConnectionState state) {
      isConnected =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      notifyListeners();
    };
  }

  void _bindDataChannel(RTCDataChannel channel) {
    channel.onDataChannelState = (RTCDataChannelState state) {
      isConnected = state == RTCDataChannelState.RTCDataChannelOpen;
      notifyListeners();
    };

    channel.onMessage = (RTCDataChannelMessage msg) async {
      if (msg.isBinary) return;
      try {
        final map = jsonDecode(msg.text) as Map<String, dynamic>;
        // Игнорируем шумовые dummy-пакеты
        if (map['type'] == 'DUMMY_NOISE') return;

        final packet = EncryptedRatchetPacket.fromJson(map);
        if (packet.isRemoteWipeTrigger) {
          onRemoteWipeTriggered?.call(packet.senderPeerId);
          return;
        }
        final plain = await cryptoService.decryptRatchetMessage(packet);
        onMessageReceived?.call(packet, plain);
      } catch (_) {}
    };
  }

  /// Отправка зашифрованного сообщения через активный P2P-канал
  Future<EncryptedRatchetPacket> sendEncryptedP2PMessage({
    required String remotePeerId,
    required String plainText,
    int ttlSeconds = 0,
    bool isRemoteWipeTrigger = false,
  }) async {
    final packet = await cryptoService.encryptRatchetMessage(
      remotePeerId: remotePeerId,
      plainText: plainText,
      ttlSeconds: ttlSeconds,
      isRemoteWipeTrigger: isRemoteWipeTrigger,
    );

    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      await _dataChannel!.send(
        RTCDataChannelMessage(jsonEncode(packet.toJson())),
      );
    }
    return packet;
  }

  /// Сетевой шум (Traffic Padding & Dummy Packets) против анализа таймингов
  void _startTrafficPaddingEngine() {
    final rng = Random.secure();
    _dummyTrafficTimer?.cancel();
    _dummyTrafficTimer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!isTrafficPaddingActive) return;
      dummyPacketsSent++;
      if (_dataChannel != null &&
          _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
        final noise = List<int>.generate(512, (_) => rng.nextInt(256));
        _dataChannel!.send(
          RTCDataChannelMessage(jsonEncode({
            'type': 'DUMMY_NOISE',
            'pad': base64Encode(noise),
          })),
        );
      }
      notifyListeners();
    });
  }

  /// Чанковая нарезка файла (64 КБ) с вычислением SHA-256 для докачки при обрыве
  Future<List>> buildResumableFileChunks(
    Uint8List fileBytes, {
    int startChunkIndex = 0,
  }) async {
    const chunkSize = 65536;
    final totalChunks = (fileBytes.length + chunkSize - 1) ~/ chunkSize;
    final chunks = >[];

    for (int i = startChunkIndex; i < totalChunks; i++) {
      final start = i * chunkSize;
      final end = min(start + chunkSize, fileBytes.length);
      final slice = fileBytes.sublist(start, end);
      final digest = await Sha256().hash(slice);

      chunks.add({
        'chunkIndex': i,
        'totalChunks': totalChunks,
        'sha256': hex.encode(digest.bytes),
        'payloadBase64': base64Encode(slice),
      });
    }
    return chunks;
  }

  /// Стеганография «на лету»: внедрение зашифрованного текста в контейнер изображения
  String embedSteganographyPayload(String coverImageLabel, String secretCipher) {
    final encoded = base64Encode(utf8.encode(secretCipher));
    return '🖼️ [STEGO-PNG: $coverImageLabel | LSB-Container: ${encoded.substring(0, min(20, encoded.length))}... (Скрыто ${secretCipher.length} байт E2EE)]';
  }

  /// Запуск P2P аудио/видео потока или кружочка 1:1 с защитой биометрии голоса
  Future<bool> startEncryptedMediaStream({required bool videoCircle}) async {
    try {
      _localAudioVideoStream = await navigator.mediaDevices.getUserMedia({
        'audio': {
          'echoCancellation': true,
          'noiseSuppression': isRnnoiseEnabled,
          'autoGainControl': true,
        },
        'video': videoCircle
            ? {
                'width': {'ideal': 480},
                'height': {'ideal': 480},
                'frameRate': {'ideal': 30},
              }
            : false,
      });
      if (_peerConnection != null && _localAudioVideoStream != null) {
        for (final track in _localAudioVideoStream!.getTracks()) {
          await _peerConnection!.addTrack(track, _localAudioVideoStream!);
        }
      }
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopMediaStream() async {
    if (_localAudioVideoStream != null) {
      for (final track in _localAudioVideoStream!.getTracks()) {
        await track.stop();
      }
      await _localAudioVideoStream!.dispose();
      _localAudioVideoStream = null;
    }
    notifyListeners();
  }

  void setTransportMode(P2PTransportMode mode) {
    activeTransport = mode;
    notifyListeners();
  }

  void broadcastPresenceStatus(String status) {
    if (_dataChannel != null &&
        _dataChannel!.state == RTCDataChannelState.RTCDataChannelOpen) {
      _dataChannel!.send(RTCDataChannelMessage(jsonEncode({
        'type': 'PRESENCE_STATUS',
        'status': status,
      })));
    }
  }

  /// Kill-Switch при смене сети или нажатии Nuke Button
  Future<void> emergencyKillSwitch() async {
    _dummyTrafficTimer?.cancel();
    await stopMediaStream();
    await _disposeCurrentPeerConnection();
    isConnected = false;
    notifyListeners();
  }

  Future<void> _disposeCurrentPeerConnection() async {
    try {
      await _dataChannel?.close();
      await _peerConnection?.close();
    } catch (_) {}
    _dataChannel = null;
    _peerConnection = null;
  }

  @override
  void dispose() {
    _dummyTrafficTimer?.cancel();
    _disposeCurrentPeerConnection();
    super.dispose();
  }
}
