import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../main.dart';
import '../../services/crypto_service.dart';
import '../../services/p2p_service.dart';

class ChatFolderTab {
  final String id;
  final String title;
  final IconData icon;
  final Color badgeColor;
  final String? filterType; // null = все, 'direct', 'channel', 'space', 'bot'

  ChatFolderTab({
    required this.id,
    required this.title,
    required this.icon,
    required this.badgeColor,
    this.filterType,
  });
}

class ChatMessageItem {
  final String id;
  final String senderName;
  final String senderRoleBadge;
  final String text;
  final String utcTime;
  final bool isMe;
  final int ttlSeconds;
  final bool isViewOnceMedia;
  final bool isCodeBlock;
  final String? quotedSnippet;
  List<String> reactions;
  bool isPinned;
  bool isViewOnceOpened;

  ChatMessageItem({
    required this.id,
    required this.senderName,
    this.senderRoleBadge = 'PEER',
    required this.text,
    required this.utcTime,
    required this.isMe,
    this.ttlSeconds = 0,
    this.isViewOnceMedia = false,
    this.isCodeBlock = false,
    this.quotedSnippet,
    List<String>? reactions,
    this.isPinned = false,
    this.isViewOnceOpened = false,
  }) : reactions = reactions ?? [];
}

class P2PChatEntity {
  final String id;
  final String title;
  final String handle;
  final String peerIdOnion;
  final String category; // 'direct', 'channel', 'space', 'bot'
  final String presenceStatus;
  bool isPinned;
  bool isArchived;
  bool keepArchivedOnNewMessage;
  int slowModeSeconds;
  String draftText;
  final List<ChatMessageItem> messages;

  P2PChatEntity({
    required this.id,
    required this.title,
    required this.handle,
    required this.peerIdOnion,
    required this.category,
    required this.presenceStatus,
    this.isPinned = false,
    this.isArchived = false,
    this.keepArchivedOnNewMessage = true,
    this.slowModeSeconds = 0,
    this.draftText = '',
    required this.messages,
  });
}

class DiscordP2PSpace {
  final String id;
  final String name;
  final String roleCertificate;
  final List<String> textChannels;
  final List<String> announcementChannels;
  final List<String> forumThreads;
  final List<String> voiceRooms;

  DiscordP2PSpace({
    required this.id,
    required this.name,
    required this.roleCertificate,
    required this.textChannels,
    required this.announcementChannels,
    required this.forumThreads,
    required this.voiceRooms,
  });
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedFolderIndex = 0;
  int _selectedSpaceIndex = 0;
  bool _isHiddenArchiveUnlocked = false;
  String _ftsSearchQuery = '';

  late List<ChatFolderTab> _folders;
  late List<P2PChatEntity> _chats;
  late List<DiscordP2PSpace> _spaces;

  @override
  void initState() {
    super.initState();
    _initFoldersAndData();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p2p = context.read<P2PService>();
      p2p.onMessageReceived = (packet, plainText) {
        if (!mounted) return;
        setState(() {
          final target = _chats.first;
          target.messages.add(
            ChatMessageItem(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              senderName: target.title,
              text: plainText,
              utcTime: _formatUtcNow(),
              isMe: false,
              ttlSeconds: packet.ttlSeconds,
            ),
          );
        });
      };
      p2p.onRemoteWipeTriggered = (remotePeerId) {
        if (!mounted) return;
        setState(() {
          for (final chat in _chats) {
            if (chat.peerIdOnion == remotePeerId) {
              chat.messages.clear();
            }
          }
        });
      };
    });
  }

  String _formatUtcNow() {
    final now = DateTime.now().toUtc();
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '$hh:$mm UTC+0';
  }

  void _initFoldersAndData() {
    _folders = [
      ChatFolderTab(
        id: 'all',
        title: 'Все',
        icon: Icons.grid_view_rounded,
        badgeColor: const Color(0xFF00F5D4),
      ),
      ChatFolderTab(
        id: 'direct',
        title: 'Личные',
        icon: Icons.lock_person_outlined,
        badgeColor: const Color(0xFF3B82F6),
        filterType: 'direct',
      ),
      ChatFolderTab(
        id: 'channel',
        title: 'Каналы',
        icon: Icons.campaign_outlined,
        badgeColor: const Color(0xFFF59E0B),
        filterType: 'channel',
      ),
      ChatFolderTab(
        id: 'space',
        title: 'Серверы',
        icon: Icons.hub_outlined,
        badgeColor: const Color(0xFF9B5DE5),
        filterType: 'space',
      ),
      ChatFolderTab(
        id: 'bot',
        title: 'Боты',
        icon: Icons.smart_toy_outlined,
        badgeColor: const Color(0xFF10B981),
        filterType: 'bot',
      ),
    ];

    _spaces = [
      DiscordP2PSpace(
        id: 'space_cyber',
        name: 'Zero-Knowledge Mesh Hub',
        roleCertificate: 'CERT-ED25519: OWNER / ROOT-ADMIN',
        textChannels: ['# general-e2ee', '# rust-libp2p-dev', '# opsec-audit'],
        announcementChannels: ['📢 release-notes-readonly'],
        forumThreads: ['🧵 Tor v3 Circuit Optimization', '🧵 BadUSB Hardware Trigger'],
        voiceRooms: ['🔊 P2P Voice Lounge (Opus 64kbps)', '📻 Tactical PTT Channel'],
      ),
      DiscordP2PSpace(
        id: 'space_crypto',
        name: 'Monero & Lightning P2P DEX',
        roleCertificate: 'CERT-ED25519: VERIFIED ARBITER (2-of-3)',
        textChannels: ['# xmr-atomic-swaps', '# escrow-contracts'],
        announcementChannels: ['📢 fee-oracle-feed'],
        forumThreads: ['🧵 Multisig 2-of-3 Dispute Rules'],
        voiceRooms: ['🔊 Escrow Voice Room'],
      ),
    ];

    _chats = [
      P2PChatEntity(
        id: 'c1',
        title: 'Valkyrie_0x',
        handle: '@valkyrie_sec',
        peerIdOnion: '7f9a2b4c8d1e6f3a0b5c9d2e4f1a8b3c.onion',
        category: 'direct',
        presenceStatus: 'Пишет код (Double Ratchet)',
        isPinned: true,
        messages: [
          ChatMessageItem(
            id: 'm1',
            senderName: 'Valkyrie_0x',
            senderRoleBadge: 'VERIFIED SAS',
            text: 'Туннель Tor v3 + WebRTC DataChannel поднят. Все пакеты выровнены до 512 байт.',
            utcTime: '18:10 UTC+0',
            isMe: false,
            isPinned: true,
            reactions: ['⚡', '🛡️'],
          ),
          ChatMessageItem(
            id: 'm2',
            senderName: 'Valkyrie_0x',
            senderRoleBadge: 'VERIFIED SAS',
            text: 'void stepRatchet(SecretKey root) {\n  // Forward Secrecy KDF step\n  deriveNextEphemeralPair();\n}',
            utcTime: '18:12 UTC+0',
            isMe: false,
            isCodeBlock: true,
            reactions: ['🔥'],
          ),
        ],
      ),
      P2PChatEntity(
        id: 'c2',
        title: 'ZeroNet Core Announcements',
        handle: '@zeronet_feed',
        peerIdOnion: '3c8b1a4f9d2e5c0b6a3f8e1d4c2b9a7f.onion',
        category: 'channel',
        presenceStatus: 'Канал-анонс (Ed25519 Read-Only)',
        isPinned: true,
        messages: [
          ChatMessageItem(
            id: 'm3',
            senderName: 'ZeroNet Core',
            senderRoleBadge: 'CHANNEL OWNER',
            text: 'Обновление протокола Local Mesh: добавлена ретрансляция DTN Drop-boxes через BLE + Wi-Fi Direct.',
            utcTime: '16:40 UTC+0',
            isMe: false,
            isPinned: true,
          ),
        ],
      ),
      P2PChatEntity(
        id: 'c3',
        title: 'Mesh Dev Space // #general',
        handle: '@mesh_space_crdt',
        peerIdOnion: '9e4d2c1b8a7f6e5d4c3b2a1f0e9d8c7b.onion',
        category: 'space',
        presenceStatus: '14 пиров в DHT Kademlia',
        slowModeSeconds: 10,
        messages: [
          ChatMessageItem(
            id: 'm4',
            senderName: 'CipherArchitect',
            senderRoleBadge: 'ADMIN CERT',
            text: 'Проверьте новый хэш-контракт для P2P-сделки в ветке #escrow-contracts.',
            utcTime: '17:05 UTC+0',
            isMe: false,
          ),
        ],
      ),
      P2PChatEntity(
        id: 'c4',
        title: 'Local Lua/JS Watchdog Bot',
        handle: '@sandbox_watchdog_bot',
        peerIdOnion: '1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d.onion',
        category: 'bot',
        presenceStatus: 'Локальный изолированный движок',
        messages: [
          ChatMessageItem(
            id: 'm5',
            senderName: 'Watchdog Bot',
            senderRoleBadge: 'LOCAL BOT',
            text: '[WEBHOOK OK]: Проверка целостности ключей пройдена. Попыток подключения BadUSB не обнаружено.',
            utcTime: '18:00 UTC+0',
            isMe: false,
          ),
        ],
      ),
      P2PChatEntity(
        id: 'c5',
        title: 'DarkDrop Cold Vault (Скрытый)',
        handle: '@cold_vault_xmr',
        peerIdOnion: '5f4e3d2c1b0a9f8e7d6c5b4a3f2e1d0c.onion',
        category: 'direct',
        presenceStatus: 'В сети через Air-Gap QR',
        isArchived: true,
        messages: [
          ChatMessageItem(
            id: 'm6',
            senderName: 'DarkDrop',
            senderRoleBadge: 'AIR-GAPPED',
            text: 'Этот диалог находится в изолированном Архиве и не всплывает при новых сообщениях.',
            utcTime: '12:00 UTC+0',
            isMe: false,
          ),
        ],
      ),
    ];
  }

  List<P2PChatEntity> _getFilteredChats() {
    final activeFolder = _folders[_selectedFolderIndex];
    final list = _chats.where((chat) {
      if (_isHiddenArchiveUnlocked) {
        if (!chat.isArchived) return false;
      } else {
        if (chat.isArchived) return false;
      }

      if (activeFolder.filterType != null &&
          chat.category != activeFolder.filterType) {
        return false;
      }

      if (_ftsSearchQuery.trim().isNotEmpty) {
        final q = _ftsSearchQuery.toLowerCase();
        final matchTitle = chat.title.toLowerCase().contains(q) ||
            chat.handle.toLowerCase().contains(q);
        final matchMessages =
            chat.messages.any((m) => m.text.toLowerCase().contains(q));
        return matchTitle || matchMessages;
      }
      return true;
    }).toList();

    list.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return a.title.compareTo(b.title);
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<AppSecurityState>();
    final crypto = context.watch<CryptoService>();
    final p2p = context.watch<P2PService>();

    final filteredChats = _getFilteredChats();

    return Scaffold(
      drawer: _buildDiscordSpacesDrawer(context, crypto, p2p),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        titleSpacing: 0,
        title: GestureDetector(
          // Секретный жест (долгое нажатие на заголовок) для открытия скрытого Архива
          onLongPress: () {
            setState(() {
              _isHiddenArchiveUnlocked = !_isHiddenArchiveUnlocked;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _isHiddenArchiveUnlocked
                      ? '🔓 Скрытый изолированный Архив разблокирован'
                      : '🔒 Архив снова скрыт из дерева чатов',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
          child: Row(
            children: [
              _IdenticonAvatar(
                matrix: crypto.buildIdenticonMatrix(crypto.peerIdOnion),
                size: 34,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _isHiddenArchiveUnlocked
                                ? '🗄️ СКРЫТЫЙ АРХИВ'
                                : crypto.displayName,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        if (security.isRamOnlyMode)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 5, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.amber, width: 0.8),
                            ),
                            child: const Text(
                              'RAM-ONLY',
                              style: TextStyle(fontSize: 9, color: Colors.amber),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      '${security.customStatus} • ${crypto.peerIdOnion.substring(0, 10)}….onion',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF00F5D4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Privacy Shield (Размытие сообщений от подглядывания)',
            icon: Icon(
              security.isPrivacyShieldEnabled
                  ? Icons.visibility_off
                  : Icons.visibility_outlined,
              color: security.isPrivacyShieldEnabled
                  ? const Color(0xFF00F5D4)
                  : Colors.white70,
            ),
            onPressed: security.togglePrivacyShield,
          ),
          IconButton(
            tooltip: 'Бессерверное рукопожатие WebRTC / Tor / Mesh',
            icon: Icon(
              Icons.settings_input_antenna,
              color: p2p.isConnected
                  ? const Color(0xFF10B981)
                  : const Color(0xFFF59E0B),
            ),
            onPressed: () => _showServerlessSignalingSheet(context),
          ),
          IconButton(
            tooltip: 'Крипто-профиль, BIP-39 Seed и Параноидальный режим',
            icon: const Icon(Icons.security_rounded, color: Color(0xFF9B5DE5)),
            onPressed: () => _showSecurityCommandCenter(context),
          ),
        ],
      ),
      body: Column(
        children: [
          // Информационная полоса сетевого транспорта и защиты от трафик-анализа
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: const Color(0xFF101624),
            child: Row(
              children: [
                const Icon(Icons.sync_lock, size: 14, color: Color(0xFF00F5D4)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Транспорт: ${_transportLabel(p2p.activeTransport)} | Noise Padding: ${p2p.dummyPacketsSent} pkts | UTC+0',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ),
                GestureDetector(
                  onTap: security.toggleIrcCompactMode,
                  child: Text(
                    security.isIrcCompactMode ? '[IRC MODE]' : '[CARD MODE]',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF00F5D4),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Полнотекстовый локальный поиск FTS5
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              onChanged: (v) => setState(() => _ftsSearchQuery = v),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                hintText:
                    'Локальный FTS5 поиск по зашифрованной БД (Zero-Leak)...',
                prefixIcon: const Icon(Icons.search, size: 18),
                isDense: true,
                filled: true,
                fillColor: const Color(0xFF111726),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),

          // Пользовательские папки (Custom Tabs) с ручной сортировкой и добавлением
          SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _folders.length,
                    itemBuilder: (context, index) {
                      final tab = _folders[index];
                      final isSelected = index == _selectedFolderIndex;
                      return Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 6),
                        child: GestureDetector(
                          onTap: () =>
                              setState(() => _selectedFolderIndex = index),
                          onLongPress: () => _reorderFolderTab(index),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? tab.badgeColor.withOpacity(0.22)
                                  : const Color(0xFF111726),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: isSelected
                                    ? tab.badgeColor
                                    : Colors.white12,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(tab.icon, size: 15, color: tab.badgeColor),
                                const SizedBox(width: 6),
                                Text(
                                  tab.title,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                IconButton(
                  tooltip: 'Создать кастомную папку (Tab)',
                  icon: const Icon(Icons.create_new_folder_outlined,
                      size: 20, color: Color(0xFF00F5D4)),
                  onPressed: () => _showCreateCustomTabDialog(context),
                ),
              ],
            ),
          ),

          // Список диалогов с поддержкой свайпа в Архив и закрепления (Pins)
          Expanded(
            child: filteredChats.isEmpty
                ? const Center(
                    child: Text(
                      'В этой папке пока нет чатов.\nЗажмите заголовок сверху для доступа к скрытому Архиву.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white38, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    itemCount: filteredChats.length,
                    itemBuilder: (context, index) {
                      final chat = filteredChats[index];
                      final lastMsg = chat.messages.isNotEmpty
                          ? chat.messages.last.text
                          : 'Нет сообщений';

                      return Dismissible(
                        key: ValueKey(chat.id),
                        background: Container(
                          color: const Color(0xFF9B5DE5),
                          alignment: Alignment.centerLeft,
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: Row(
                            children: [
                              const Icon(Icons.archive_outlined,
                                  color: Colors.white),
                              const SizedBox(width: 8),
                              Text(
                                chat.isArchived
                                    ? 'Разархивировать'
                                    : 'В скрытый Архив',
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                        confirmDismiss: (_) async {
                          setState(() {
                            chat.isArchived = !chat.isArchived;
                          });
                          return false;
                        },
                        child: ListTile(
                          dense: security.isIrcCompactMode,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 2),
                          leading: _IdenticonAvatar(
                            matrix:
                                crypto.buildIdenticonMatrix(chat.peerIdOnion),
                            size: security.isIrcCompactMode ? 32 : 44,
                          ),
                          title: Row(
                            children: [
                              if (chat.isPinned)
                                const Padding(
                                  padding: EdgeInsets.only(right: 5),
                                  child: Icon(Icons.push_pin,
                                      size: 14, color: Color(0xFF00F5D4)),
                                ),
                              Expanded(
                                child: Text(
                                  chat.title,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Text(
                                chat.messages.isNotEmpty
                                    ? chat.messages.last.utcTime
                                    : '',
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white38),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                chat.presenceStatus,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: Color(0xFF00F5D4),
                                ),
                              ),
                              const SizedBox(height: 2),
                              security.isPrivacyShieldEnabled
                                  ? const Text(
                                      '████████████████ [PRIVACY SHIELD]',
                                      style: TextStyle(
                                          fontSize: 12, color: Colors.white24),
                                    )
                                  : Text(
                                      chat.draftText.isNotEmpty
                                          ? 'Черновик: ${chat.draftText}'
                                          : lastMsg,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: chat.draftText.isNotEmpty
                                            ? Colors.amber
                                            : Colors.white70,
                                      ),
                                    ),
                            ],
                          ),
                          onLongPress: () {
                            setState(() {
                              chat.isPinned = !chat.isPinned;
                            });
                          },
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    EncryptedChatScreen(chat: chat),
                              ),
                            );
                            setState(() {});
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: const Color(0xFF00F5D4),
        foregroundColor: Colors.black,
        icon: const Icon(Icons.qr_code_scanner),
        label: const Text(
          'Новый P2P / Air-Gap',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        onPressed: () => _showNewPeerDialog(context),
      ),
    );
  }

  String _transportLabel(P2PTransportMode mode) {
    switch (mode) {
      case P2PTransportMode.torOnionV3:
        return 'Tor Onion v3';
      case P2PTransportMode.webrtcDirect:
        return 'WebRTC E2EE Direct';
      case P2PTransportMode.localMeshBleWifi:
        return 'BLE + Wi-Fi Mesh';
      case P2PTransportMode.airGappedQr:
        return 'Air-Gapped Optical QR';
    }
  }

  void _reorderFolderTab(int index) {
    if (index == 0) return;
    setState(() {
      final item = _folders.removeAt(index);
      _folders.insert(1, item);
      _selectedFolderIndex = 1;
    });
  }

  /// Боковая панель P2P Spaces (Бессерверные сообщества в стиле Discord)
  Widget _buildDiscordSpacesDrawer(
    BuildContext context,
    CryptoService crypto,
    P2PService p2p,
  ) {
    final space = _spaces[_selectedSpaceIndex];
    return Drawer(
      backgroundColor: const Color(0xFF090D16),
      child: SafeArea(
        child: Row(
          children: [
            // Левая рельса серверов (Discord Server Rail)
            Container(
              width: 68,
              color: const Color(0xFF05070C),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  ...List.generate(_spaces.length, (i) {
                    final active = i == _selectedSpaceIndex;
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: GestureDetector(
                        onTap: () => setState(() => _selectedSpaceIndex = i),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 46,
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFF9B5DE5)
                                : const Color(0xFF161C2C),
                            borderRadius:
                                BorderRadius.circular(active ? 14 : 23),
                          ),
                          child: Text(
                            _spaces[i].name.substring(0, 2).toUpperCase(),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  const Divider(color: Colors.white12),
                  IconButton(
                    tooltip: 'Переключить транспорт P2P Mesh',
                    icon: const Icon(Icons.radar, color: Color(0xFF00F5D4)),
                    onPressed: () {
                      final next = P2PTransportMode.values[
                          (p2p.activeTransport.index + 1) %
                              P2PTransportMode.values.length];
                      p2p.setTransportMode(next);
                    },
                  ),
                ],
              ),
            ),
            // Правая колонка каналов, тредов и голосовых комнат
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(
                    space.name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00F5D4).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      space.roleCertificate,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF00F5D4),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'КАНАЛЫ-АНОНСЫ (ED25519 READ-ONLY)',
                    style: TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                  ...space.announcementChannels.map(
                    (c) => ListTile(
                      dense: true,
                      title:
                          Text(c, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ТЕКСТОВЫЕ P2P КАНАЛЫ (CRDT DAG)',
                    style: TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                  ...space.textChannels.map(
                    (c) => ListTile(
                      dense: true,
                      title:
                          Text(c, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'КАНАЛЫ-ФОРУМЫ (THREADS)',
                    style: TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                  ...space.forumThreads.map(
                    (c) => ListTile(
                      dense: true,
                      title:
                          Text(c, style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'ГОЛОСОВЫЕ P2P КОМНАТЫ (OPUS + RNNOISE)',
                    style: TextStyle(fontSize: 10, color: Colors.white38),
                  ),
                  ...space.voiceRooms.map(
                    (c) => ListTile(
                      dense: true,
                      trailing: const Icon(Icons.graphic_eq,
                          size: 16, color: Color(0xFF10B981)),
                      title:
                          Text(c, style: const TextStyle(fontSize: 13)),
                      onTap: () {
                        p2p.startEncryptedMediaStream(videoCircle: false);
                        Navigator.pop(context);
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCreateCustomTabDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF10141F),
        title: const Text('Новая пользовательская папка'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Например: Скрытые / Сделки XMR / Офлайн',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (controller.text.trim().isNotEmpty) {
                setState(() {
                  _folders.add(
                    ChatFolderTab(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: controller.text.trim(),
                      icon: Icons.folder_special_outlined,
                      badgeColor: const Color(0xFFEC4899),
                    ),
                  );
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  /// Панель бессерверного обмена SDP-токенами (WebRTC DataChannel без сигнального сервера)
  void _showServerlessSignalingSheet(BuildContext context) {
    final p2p = context.read<P2PService>();
    final security = context.read<AppSecurityState>();
    final remoteTokenController = TextEditingController();
    String generatedToken = '';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0C101B),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Бессерверный P2P сигналинг (WebRTC + Tor v3)',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Обмен SDP-офферами происходит напрямую через одноразовые зашифрованные токены или QR без участия сигнальных серверов.',
                  style: TextStyle(fontSize: 12, color: Colors.white60),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  children: [
                    ElevatedButton.icon(
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('1. Создать Offer-токен'),
                      onPressed: () async {
                        final token = await p2p.createServerlessOfferToken();
                        setModalState(() => generatedToken = token);
                        await security.copyWithZeroTrace(token);
                      },
                    ),
                    ElevatedButton.icon(
                      icon: const Icon(Icons.download_done, size: 16),
                      label: const Text('2. Принять Offer / Answer'),
                      onPressed: () async {
                        final input = remoteTokenController.text.trim();
                        if (input.isEmpty) return;
                        try {
                          final answer = await p2p
                              .acceptOfferAndCreateAnswerToken(input);
                          setModalState(() => generatedToken = answer);
                          await security.copyWithZeroTrace(answer);
                        } catch (_) {
                          await p2p.completeServerlessHandshake(input);
                        }
                      },
                    ),
                  ],
                ),
                if (generatedToken.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFF00F5D4)),
                    ),
                    child: Text(
                      'Токен скопирован в Zero-Trace буфер (очистка через 15 сек):\n${generatedToken.substring(0, generatedToken.length > 120 ? 120 : generatedToken.length)}...',
                      style: const TextStyle(fontSize: 11),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                TextField(
                  controller: remoteTokenController,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    hintText: 'Вставьте встречный SDP-токен собеседника...',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Центр управления криптографией, BIP-39, калькулятором маскировки и красной кнопкой Nuke
  void _showSecurityCommandCenter(BuildContext context) {
    final crypto = context.read<CryptoService>();
    final security = context.read<AppSecurityState>();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF0B0E17),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Icons.verified_user, color: Color(0xFF00F5D4)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Zero-Knowledge Identity & Paranoid Mode',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.redAccent,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.warning_amber_rounded, size: 16),
                    label: const Text('PANIC NUKE'),
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await security.triggerPanicNuke();
                    },
                  ),
                ],
              ),
              const Divider(height: 24, color: Colors.white12),
              Text(
                'Ваш постоянный Peer ID (.onion v3):\n${crypto.peerIdOnion}',
                style: const TextStyle(fontSize: 12, color: Color(0xFF00F5D4)),
              ),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF141B2D),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Мнемоническая фраза BIP-39 (24 слова для переноса профиля):',
                      style: TextStyle(fontSize: 11, color: Colors.white60),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      crypto.mnemonic,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.amberAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('RAM-Only режим (без записи на Flash)',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Все новые ключи и сообщения живут только в ОЗУ',
                    style: TextStyle(fontSize: 11)),
                value: security.isRamOnlyMode,
                onChanged: (v) {
                  security.toggleRamOnlyMode(v);
                  Navigator.pop(ctx);
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Stealth Camouflage (Маскировка под калькулятор)',
                    style: TextStyle(fontSize: 13)),
                subtitle: const Text(
                    'Код 1337= (Основной) | 9999= (Двойное дно) | 0000= (Kill)',
                    style: TextStyle(fontSize: 11)),
                value: security.isStealthCalculatorLocked,
                onChanged: (_) {
                  Navigator.pop(ctx);
                  security.toggleStealthCalculator();
                },
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Тема Cyberpunk Neon / Pure OLED Black',
                    style: TextStyle(fontSize: 13)),
                value: security.isCyberpunkNeonTheme,
                onChanged: (_) => security.toggleTheme(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNewPeerDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final onionCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF10141F),
        title: const Text('Добавить P2P пира (.onion / QR)'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration:
                  const InputDecoration(hintText: 'Локальный никнейм пира'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: onionCtrl,
              decoration: const InputDecoration(
                  hintText: 'Публичный ключ или .onion адрес'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Отмена'),
          ),
          ElevatedButton(
            onPressed: () {
              if (nameCtrl.text.trim().isNotEmpty) {
                setState(() {
                  _chats.insert(
                    0,
                    P2PChatEntity(
                      id: DateTime.now().millisecondsSinceEpoch.toString(),
                      title: nameCtrl.text.trim(),
                      handle:
                          '@${nameCtrl.text.trim().toLowerCase().replaceAll(' ', '_')}',
                      peerIdOnion: onionCtrl.text.trim().isEmpty
                          ? '8b9c0d1e2f3a4b5c6d7e8f9a0b1c2d3e.onion'
                          : onionCtrl.text.trim(),
                      category: 'direct',
                      presenceStatus: 'Инициализация X3DH...',
                      messages: [],
                    ),
                  );
                });
              }
              Navigator.pop(ctx);
            },
            child: const Text('Создать X3DH канал'),
          ),
        ],
      ),
    );
  }
}

/// Экран диалога со сквозным шифрованием Double Ratchet, SAS, кружочками 1:1 и XMR-сделками
class EncryptedChatScreen extends StatefulWidget {
  final P2PChatEntity chat;

  const EncryptedChatScreen({super.key, required this.chat});

  @override
  State<EncryptedChatScreen> createState() => _EncryptedChatScreenState();
}

class _EncryptedChatScreenState extends State<EncryptedChatScreen> {
  late TextEditingController _msgController;
  int _selectedBurnTtl = 0; // 0 = бессрочно, 5 = 5 сек, 60 = 1 мин
  int _pinnedCarouselIndex = 0;
  String? _activeQuoteSnippet;
  String _sasString = 'Вычисление SAS...';
  double _voicePlaybackSpeed = 1.0;
  bool _silentSend = false;
  final Set<String> _temporarilyUnblurredIds = {};

  @override
  void initState() {
    super.initState();
    _msgController = TextEditingController(text: widget.chat.draftText);
    _loadSas();
  }

  Future<void> _loadSas() async {
    final crypto = context.read<CryptoService>();
    final sas = await crypto.generateSasVerification(widget.chat.peerIdOnion);
    if (mounted) {
      setState(() => _sasString = sas);
    }
  }

  @override
  void dispose() {
    widget.chat.draftText = _msgController.text;
    _msgController.dispose();
    super.dispose();
  }

  List<ChatMessageItem> get _pinnedMessages =>
      widget.chat.messages.where((m) => m.isPinned).toList();

  Future<void> _sendMessage({String? customBody, bool isCode = false}) async {
    final text = (customBody ?? _msgController.text).trim();
    if (text.isEmpty) return;

    final p2p = context.read<P2PService>();
    await p2p.sendEncryptedP2PMessage(
      remotePeerId: widget.chat.peerIdOnion,
      plainText: text,
      ttlSeconds: _selectedBurnTtl,
    );

    final msgId = DateTime.now().millisecondsSinceEpoch.toString();
    final newItem = ChatMessageItem(
      id: msgId,
      senderName: 'Вы',
      senderRoleBadge: _silentSend ? 'SILENT E2EE' : 'RATCHET OK',
      text: text,
      utcTime:
          '${DateTime.now().toUtc().hour.toString().padLeft(2, '0')}:${DateTime.now().toUtc().minute.toString().padLeft(2, '0')} UTC+0',
      isMe: true,
      ttlSeconds: _selectedBurnTtl,
      isCodeBlock: isCode,
      quotedSnippet: _activeQuoteSnippet,
    );

    setState(() {
      widget.chat.messages.add(newItem);
      if (customBody == null) {
        _msgController.clear();
        widget.chat.draftText = '';
      }
      _activeQuoteSnippet = null;
    });

    // Таймер самоуничтожения Burn-on-Read
    if (_selectedBurnTtl > 0) {
      Timer(Duration(seconds: _selectedBurnTtl), () {
        if (mounted) {
          setState(() {
            widget.chat.messages.removeWhere((m) => m.id == msgId);
          });
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<AppSecurityState>();
    final crypto = context.watch<CryptoService>();
    final p2p = context.watch<P2PService>();
    final pinned = _pinnedMessages;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0F19),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.chat.title, style: const TextStyle(fontSize: 15)),
            Text(
              'SAS: $_sasString',
              style: const TextStyle(fontSize: 10, color: Color(0xFF00F5D4)),
            ),
          ],
        ),
        actions: [
          // Переключатель скорости войсов (0.5x - 3.0x)
          TextButton(
            onPressed: () {
              setState(() {
                _voicePlaybackSpeed = _voicePlaybackSpeed >= 2.5
                    ? 0.5
                    : _voicePlaybackSpeed + 0.5;
              });
            },
            child: Text(
              '${_voicePlaybackSpeed.toStringAsFixed(1)}x',
              style: const TextStyle(
                  color: Color(0xFF00F5D4), fontWeight: FontWeight.bold),
            ),
          ),
          // Видеокружочек 1:1 / P2P Звонок
          IconButton(
            tooltip: 'Записать E2EE видеокружочек 1:1 (Dual-Camera + Pitch Shift)',
            icon: const Icon(Icons.videocam_outlined),
            onPressed: () => _recordEncryptedVideoCircle(context),
          ),
          // Двустороннее удаление истории у обоих участников (Two-Way Remote Wipe)
          IconButton(
            tooltip: 'Two-Way Remote Wipe (Удалить чат у всех)',
            icon: const Icon(Icons.delete_forever_outlined,
                color: Colors.redAccent),
            onPressed: () async {
              await p2p.sendEncryptedP2PMessage(
                remotePeerId: widget.chat.peerIdOnion,
                plainText: 'REMOTE_WIPE_SIGNAL',
                isRemoteWipeTrigger: true,
              );
              setState(() => widget.chat.messages.clear());
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Карусель закрепленных сообщений (Pin System в заголовке чата)
          if (pinned.isNotEmpty)
            GestureDetector(
              onTap: () {
                setState(() {
                  _pinnedCarouselIndex =
                      (_pinnedCarouselIndex + 1) % pinned.length;
                });
              },
              child: Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                color: const Color(0xFF121A2B),
                child: Row(
                  children: [
                    const Icon(Icons.push_pin,
                        size: 16, color: Color(0xFF00F5D4)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Закреплено #${_pinnedCarouselIndex + 1} из ${pinned.length}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF00F5D4),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            pinned[_pinnedCarouselIndex].text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Список сообщений
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: widget.chat.messages.length,
              itemBuilder: (context, index) {
                final msg = widget.chat.messages[index];
                final isBlurred = security.isPrivacyShieldEnabled &&
                    !_temporarilyUnblurredIds.contains(msg.id);

                return Align(
                  alignment:
                      msg.isMe ? Alignment.centerRight : Alignment.centerLeft,
                  child: GestureDetector(
                    // Касание снимает размытие Privacy Shield для конкретного сообщения
                    onTap: () {
                      if (security.isPrivacyShieldEnabled) {
                        setState(() {
                          if (_temporarilyUnblurredIds.contains(msg.id)) {
                            _temporarilyUnblurredIds.remove(msg.id);
                          } else {
                            _temporarilyUnblurredIds.add(msg.id);
                          }
                        });
                      } else if (msg.isViewOnceMedia) {
                        setState(() => msg.isViewOnceOpened = true);
                      }
                    },
                    onLongPress: () =>
                        _showMessageActionsSheet(context, msg, security),
                    child: Container(
                      margin: const EdgeInsets.symmetric(vertical: 5),
                      padding: const EdgeInsets.all(12),
                      constraints: BoxConstraints(
                        maxWidth: MediaQuery.of(context).size.width * 0.82,
                      ),
                      decoration: BoxDecoration(
                        color: msg.isMe
                            ? const Color(0xFF162A3A)
                            : const Color(0xFF141926),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: msg.isMe
                              ? const Color(0xFF00F5D4).withOpacity(0.4)
                              : Colors.white12,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg.senderName,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF00F5D4),
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.white10,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  msg.senderRoleBadge,
                                  style: const TextStyle(
                                      fontSize: 9, color: Colors.white70),
                                ),
                              ),
                              if (msg.ttlSeconds > 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '🔥 ${msg.ttlSeconds}s',
                                  style: const TextStyle(
                                      fontSize: 10, color: Colors.orangeAccent),
                                ),
                              ],
                            ],
                          ),
                          if (msg.quotedSnippet != null) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(6),
                              decoration: const BoxDecoration(
                                color: Colors.black26,
                                border: Border(
                                  left: BorderSide(
                                      color: Color(0xFF00F5D4), width: 3),
                                ),
                              ),
                              child: Text(
                                msg.quotedSnippet!,
                                style: const TextStyle(
                                    fontSize: 11, color: Colors.white60),
                              ),
                            ),
                          ],
                          const SizedBox(height: 6),
                          if (isBlurred)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: ImageFiltered(
                                imageFilter:
                                    ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                                child: Text(
                                  msg.text,
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            )
                          else if (msg.isViewOnceMedia && msg.isViewOnceOpened)
                            const Text(
                              '💥 [Одноразовое медиа уничтожено из ОЗУ после просмотра]',
                              style: TextStyle(
                                fontSize: 12,
                                fontStyle: FontStyle.italic,
                                color: Colors.redAccent,
                              ),
                            )
                          else if (msg.isCodeBlock)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: const Color(0xFF070A10),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                msg.text,
                                style: const TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  color: Color(0xFF10B981),
                                ),
                              ),
                            )
                          else
                            Text(
                              msg.text,
                              style: const TextStyle(fontSize: 13),
                            ),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                msg.utcTime,
                                style: const TextStyle(
                                    fontSize: 10, color: Colors.white38),
                              ),
                              if (msg.reactions.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Wrap(
                                  spacing: 4,
                                  children: msg.reactions
                                      .map((r) => Text(r,
                                          style: const TextStyle(fontSize: 12)))
                                      .toList(),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),

          // Полоса частичного цитирования
          if (_activeQuoteSnippet != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              color: const Color(0xFF141B2D),
              child: Row(
                children: [
                  const Icon(Icons.format_quote,
                      size: 16, color: Color(0xFF00F5D4)),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Цитата: $_activeQuoteSnippet',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () =>
                        setState(() => _activeQuoteSnippet = null),
                  ),
                ],
              ),
            ),

          // Панель быстрых инструментов (Burn-on-Read, Monero, Hash-Contract, Stego, Игры)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: const Color(0xFF0E1320),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ActionChip(
                    label: Text(_selectedBurnTtl == 0
                        ? '⏱️ TTL: Выкл'
                        : '🔥 TTL: ${_selectedBurnTtl}s'),
                    onPressed: () {
                      setState(() {
                        if (_selectedBurnTtl == 0) {
                          _selectedBurnTtl = 10;
                        } else if (_selectedBurnTtl == 10) {
                          _selectedBurnTtl = 60;
                        } else {
                          _selectedBurnTtl = 0;
                        }
                      });
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('📜 Хэш-контракт'),
                    onPressed: () async {
                      final contract = await crypto.createSignedHashContract(
                        counterpartyPeerId: widget.chat.peerIdOnion,
                        terms: 'Поставка исходного кода P2P-модуля',
                        amountXmr: '2.50',
                      );
                      await _sendMessage(customBody: contract);
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('💸 XMR / Lightning'),
                    onPressed: () {
                      _sendMessage(
                        customBody:
                            '⚡ [P2P INVOICE: monero:44Affq5kSiGBoZ... | 1.25 XMR | Multisig 2-of-3 Ready]',
                      );
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('🖼️ Стеганография'),
                    onPressed: () {
                      final stego = p2p.embedSteganographyPayload(
                        'IMG_COVER_001.PNG',
                        'Координаты офлайн-узла: 53.2435, 34.3634',
                      );
                      _sendMessage(customBody: stego);
                    },
                  ),
                  const SizedBox(width: 6),
                  ActionChip(
                    label: const Text('♟️ P2P Шахматы'),
                    onPressed: () {
                      _sendMessage(
                        customBody:
                            '♟️ [P2P CHESS MOVE: e2 -> e4 | FENHash: 9a4f... | Подписано Ed25519]',
                      );
                    },
                  ),
                ],
              ),
            ),
          ),

          // Поле ввода + кнопка Рации (Push-to-Talk)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            color: const Color(0xFF090C14),
            child: Row(
              children: [
                GestureDetector(
                  onLongPressStart: (_) {
                    setState(() => p2p.isPushToTalkPressed = true);
                    p2p.startEncryptedMediaStream(videoCircle: false);
                  },
                  onLongPressEnd: (_) {
                    setState(() => p2p.isPushToTalkPressed = false);
                    p2p.stopMediaStream();
                    _sendMessage(
                      customBody:
                          '🎙️ [PTT VOICE PACKET | Opus + RNNoise + PitchShift | Скорость ${_voicePlaybackSpeed}x]',
                    );
                  },
                  child: CircleAvatar(
                    radius: 20,
                    backgroundColor: p2p.isPushToTalkPressed
                        ? Colors.redAccent
                        : const Color(0xFF172033),
                    child: const Icon(Icons.mic, color: Colors.white, size: 20),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _msgController,
                    onChanged: (v) => widget.chat.draftText = v,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'E2EE сообщение (удерживайте 🎙️ для Рации)...',
                      isDense: true,
                      filled: true,
                      fillColor: const Color(0xFF131929),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                IconButton(
                  tooltip: _silentSend
                      ? 'Беззвучный режим включен'
                      : 'Обычная отправка',
                  icon: Icon(
                    _silentSend
                        ? Icons.notifications_off
                        : Icons.notifications_none,
                    size: 20,
                    color: _silentSend
                        ? const Color(0xFF00F5D4)
                        : Colors.white54,
                  ),
                  onPressed: () => setState(() => _silentSend = !_silentSend),
                ),
                CircleAvatar(
                  radius: 20,
                  backgroundColor: const Color(0xFF00F5D4),
                  child: IconButton(
                    icon: const Icon(Icons.send, color: Colors.black, size: 18),
                    onPressed: () => _sendMessage(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _recordEncryptedVideoCircle(BuildContext context) {
    _sendMessage(
      customBody:
          '⭕ [VIDEO CIRCLE 1:1 | Dual-Camera + Pitch Shifter + EXIF Scrubbed | View-Once Protected]',
    );
  }

  void _showMessageActionsSheet(
    BuildContext context,
    ChatMessageItem msg,
    AppSecurityState security,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF0E1320),
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: ['⚡', '🔥', '🛡️', '💎', '👾', '🎯'].map((emoji) {
                  return GestureDetector(
                    onTap: () {
                      setState(() => msg.reactions.add(emoji));
                      Navigator.pop(ctx);
                    },
                    child: Text(emoji, style: const TextStyle(fontSize: 24)),
                  );
                }).toList(),
              ),
            ),
            const Divider(color: Colors.white12),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('Частичное цитирование фрагмента'),
              onTap: () {
                setState(() {
                  _activeQuoteSnippet = msg.text.length > 42
                      ? '${msg.text.substring(0, 42)}...'
                      : msg.text;
                });
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.push_pin_outlined),
              title: Text(msg.isPinned
                  ? 'Открепить сообщение'
                  : 'Закрепить в карусели чата'),
              onTap: () {
                setState(() => msg.isPinned = !msg.isPinned);
                Navigator.pop(ctx);
              },
            ),
            ListTile(
              leading: const Icon(Icons.copy),
              title: const Text('Копировать в Zero-Trace буфер (15 сек)'),
              onTap: () async {
                await security.copyWithZeroTrace(msg.text);
                if (ctx.mounted) Navigator.pop(ctx);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Генеративная аватарка (Identicon) 5x5 на базе хэша открытого ключа пира
class _IdenticonAvatar extends StatelessWidget {
  final List<bool> matrix;
  final double size;

  const _IdenticonAvatar({
    required this.matrix,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF141B2D),
        borderRadius: BorderRadius.circular(size * 0.28),
        border: Border.all(
          color: const Color(0xFF00F5D4).withOpacity(0.5),
          width: 1,
        ),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 5,
          mainAxisSpacing: 1,
          crossAxisSpacing: 1,
        ),
        itemCount: 25,
        itemBuilder: (context, i) {
          return Container(
            decoration: BoxDecoration(
              color: matrix[i] ? const Color(0xFF00F5D4) : Colors.transparent,
              borderRadius: BorderRadius.circular(1.5),
            ),
          );
        },
      ),
    );
  }
}
