import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:video_player/video_player.dart';

import '../services/relay_service.dart';
import '../widgets/trackpad.dart';

const _green = Color(0xFF2D7554);
const _dark = Color(0xFF17251F);

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final RelayService _relay = RelayService();
  final _serverController = TextEditingController(text: 'ws://localhost:8787');
  final _otpController = TextEditingController();
  final _keyboardController = TextEditingController();
  StreamSubscription<Map<String, dynamic>>? _subscription;
  String _status = 'Not connected';
  String? _otp;
  String? _incomingName;
  String? _notice;
  String _activeTab = 'Overview';
  bool _isHost = false;
  bool _busy = false;
  double _cursorX = .5, _cursorY = .5;
  final List<int> _incoming = [];
  String? _transferName;
  bool _incomingVideo = false;
  VideoPlayerController? _videoController;
  String? _videoName;
  final List<String> _activity = [];

  bool get _connected => _status == 'Connected';
  @override
  void initState() {
    super.initState();
    _subscription = _relay.events.listen(_onRelayEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _relay.dispose();
    _serverController.dispose();
    _otpController.dispose();
    _keyboardController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  void _log(String message) {
    if (!mounted) return;
    setState(() { _activity.insert(0, '${TimeOfDay.now().format(context)}  $message'); if (_activity.length > 5) _activity.removeLast(); });
  }

  void _onRelayEvent(Map<String, dynamic> e) {
    if (!mounted) return;
    switch (e['type']) {
      case 'hosted':
        setState(() { _otp = e['otp'] as String?; _status = 'Waiting for sender'; _isHost = true; _busy = false; _notice = 'Session is ready. Share the QR code or 10-digit code.'; });
        _log('Receiver session created');
        break;
      case 'connected':
      case 'peer_connected':
        setState(() { _status = 'Connected'; _notice = 'Secure local relay connection established.'; _busy = false; });
        _log('Peer connected');
        break;
      case 'peer_disconnected':
        setState(() { _status = _otp == null ? 'Not connected' : 'Waiting for sender'; _notice = 'The other device disconnected.'; });
        _log('Peer disconnected');
        break;
      case 'disconnected':
        if (mounted && _status == 'Connected') setState(() { _status = _otp == null ? 'Not connected' : 'Waiting for sender'; });
        break;
      case 'error':
        setState(() { _notice = e['message']?.toString() ?? 'Connection error'; _busy = false; });
        _log(_notice!);
        break;
      case 'control':
        final kind = e['kind'];
        if (kind == 'move') {
          setState(() { _cursorX = (_cursorX + ((e['dx'] as num?)?.toDouble() ?? 0) / 650).clamp(0.02, .98).toDouble(); _cursorY = (_cursorY + ((e['dy'] as num?)?.toDouble() ?? 0) / 420).clamp(0.04, .96).toDouble(); });
        } else if (kind == 'key') {
          _log('Keyboard input received');
        } else {
          _log('${kind == 'right' ? 'Right' : 'Left'} click');
        }
        break;
      case 'file_start':
        _incoming.clear();
        _transferName = e['name']?.toString() ?? 'received-file';
        _incomingVideo = e['kind'] == 'video';
        setState(() { _incomingName = _transferName; _notice = 'Receiving ${_incomingVideo ? 'video' : 'file'}: $_transferName'; });
        break;
      case 'file_chunk':
        try { _incoming.addAll(base64Decode(e['data'] as String)); } catch (_) { _log('A file chunk could not be decoded'); }
        break;
      case 'file_end':
        _completeIncoming();
        break;
      case 'text':
        _log('Text received: ${e['text'] ?? ''}');
        break;
    }
  }

  Future<void> _completeIncoming() async {
    final name = _transferName ?? 'received-file';
    final bytes = Uint8List.fromList(_incoming);
    final isVideo = _incomingVideo;
    setState(() { _incomingName = null; _notice = 'Received $name (${_formatSize(bytes.length)}).'; });
    _log('Received $name · ${_formatSize(bytes.length)}');
    if (isVideo) {
      try {
        final mime = name.toLowerCase().endsWith('.webm') ? 'video/webm' : name.toLowerCase().endsWith('.mov') ? 'video/quicktime' : 'video/mp4';
        final encoded = base64Encode(bytes);
        final controller = VideoPlayerController.networkUrl(Uri.parse('data:$mime;base64,$encoded'));
        await controller.initialize();
        await _videoController?.dispose();
        if (!mounted) { await controller.dispose(); return; }
        setState(() { _videoController = controller; _videoName = name; _activeTab = 'Media'; });
      } catch (_) {
        setState(() => _notice = 'Video received, but this browser could not decode it. Try MP4 (H.264/AAC).');
        await _saveBytes(name, bytes);
      }
    } else {
      await _saveBytes(name, bytes);
    }
  }

  Future<void> _saveBytes(String name, Uint8List bytes) async {
    try {
      await FilePicker.platform.saveFile(fileName: name, bytes: bytes);
    } catch (_) {
      setState(() => _notice = 'Received $name. Your browser may require a supported download location.');
    }
  }

  Future<void> _host() async {
    if (_busy) return;
    setState(() { _busy = true; _notice = null; });
    try {
      await _relay.connect(_serverController.text);
      _relay.send({'type': 'host'});
    } catch (e) { setState(() { _busy = false; _notice = 'Could not reach relay: $e'; }); }
  }

  Future<void> _join([String? scannedOtp, String? scannedUrl]) async {
    if (_busy) return;
    final code = (scannedOtp ?? _otpController.text).replaceAll(RegExp(r'\D'), '');
    if (code.length != 10) { setState(() => _notice = 'Enter the full 10-digit pairing code.'); return; }
    if (scannedUrl != null && scannedUrl.isNotEmpty) _serverController.text = scannedUrl;
    setState(() { _busy = true; _notice = null; });
    try {
      await _relay.connect(_serverController.text);
      _relay.send({'type': 'join', 'otp': code});
      _isHost = false;
      _otpController.text = code;
    } catch (e) { setState(() { _busy = false; _notice = 'Could not reach relay: $e'; }); }
  }

  Future<void> _disconnect() async {
    await _relay.disconnect();
    setState(() { _status = 'Not connected'; _otp = null; _notice = 'Disconnected.'; });
  }

  String get _qrPayload => jsonEncode({'url': _serverController.text.trim(), 'otp': _otp ?? ''});
  String _formatSize(int n) => n < 1024 * 1024 ? '${(n / 1024).toStringAsFixed(0)} KB' : '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';

  void _sendControl(Map<String, dynamic> payload) {
    if (!_connected) return;
    try { _relay.send({'type': 'control', ...payload}); } catch (_) {}
  }

  Future<void> _pickAndSend({bool video = false}) async {
    if (!_connected) { setState(() => _notice = 'Connect to a peer before sending.'); return; }
    final result = await FilePicker.platform.pickFiles(withData: true, allowMultiple: true, type: video ? FileType.video : FileType.any);
    if (result == null) return;
    for (final file in result.files) {
      final data = file.bytes;
      if (data == null) { setState(() => _notice = 'Could not read ${file.name}; try selecting it again.'); continue; }
      try {
        _relay.send({'type': 'file_start', 'name': file.name, 'size': data.length, 'kind': video ? 'video' : 'file'});
        const chunk = 36 * 1024;
        for (var i = 0; i < data.length; i += chunk) {
          final end = (i + chunk < data.length) ? i + chunk : data.length;
          _relay.send({'type': 'file_chunk', 'data': base64Encode(data.sublist(i, end))});
        }
        _relay.send({'type': 'file_end'});
        setState(() => _notice = 'Sending ${file.name}…');
        _log('Sent ${file.name} · ${_formatSize(data.length)}');
      } catch (e) { setState(() => _notice = 'Transfer failed: $e'); }
    }
  }

  Future<void> _showScanner() async {
    final result = await showDialog<BarcodeCapture>(context: context, builder: (context) => Dialog(
      child: SizedBox(width: 420, height: 500, child: Column(children: [
        Padding(padding: const EdgeInsets.all(16), child: Row(children: [const Expanded(child: Text('Scan receiver QR', style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold))), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))])),
        Expanded(child: MobileScanner(onDetect: (capture) { if (capture.barcodes.isNotEmpty) Navigator.pop(context, capture); })),
      ])),
    ));
    if (result == null || result.barcodes.isEmpty) return;
    try {
      final map = jsonDecode(result.barcodes.first.rawValue ?? '') as Map<String, dynamic>;
      await _join(map['otp']?.toString(), map['url']?.toString());
    } catch (_) { setState(() => _notice = 'This QR code is not a QR Sender pairing code.'); }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final mobile = width < 760;
    return Scaffold(
      body: SafeArea(child: Row(children: [
        if (!mobile) _sideNav(),
        Expanded(child: Column(children: [
          _topBar(mobile),
          Expanded(child: SingleChildScrollView(padding: EdgeInsets.fromLTRB(mobile ? 18 : 36, 24, mobile ? 18 : 36, 36), child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1150), child: _mainContent(mobile, width))))),
        ])),
      ])),
      bottomNavigationBar: mobile ? _mobileNav() : null,
    );
  }

  Widget _sideNav() => Container(width: 235, decoration: const BoxDecoration(color: Colors.white, border: Border(right: BorderSide(color: Color(0xFFE9EEEA)))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Padding(padding: const EdgeInsets.fromLTRB(25, 25, 20, 32), child: Row(children: [_brandMark(40), const SizedBox(width: 11), const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('QR Sender', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: _dark)), Text('LOCAL CONNECTION', style: TextStyle(fontSize: 9, letterSpacing: 1.3, color: Color(0xFF849188), fontWeight: FontWeight.w700))])])),
    const Padding(padding: EdgeInsets.fromLTRB(25, 0, 0, 10), child: Text('WORKSPACE', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Color(0xFF9AA69F), fontWeight: FontWeight.w700))),
    _navItem('Overview', Icons.grid_view_rounded), _navItem('Air mouse', Icons.mouse_rounded), _navItem('File transfer', Icons.folder_copy_rounded), _navItem('Media', Icons.play_circle_outline_rounded),
    const Spacer(), Container(margin: const EdgeInsets.all(16), padding: const EdgeInsets.all(14), decoration: BoxDecoration(color: const Color(0xFFF3F7F3), borderRadius: BorderRadius.circular(16)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.shield_outlined, size: 18, color: _green), SizedBox(width: 9), Expanded(child: Text('Your files travel through your own local relay.', style: TextStyle(fontSize: 11, height: 1.4, color: Color(0xFF63746A))))])),
  ]));

  Widget _navItem(String label, IconData icon) {
    final selected = _activeTab == label;
    return InkWell(onTap: () => setState(() => _activeTab = label), child: Container(margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3), padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12), decoration: BoxDecoration(color: selected ? const Color(0xFFEAF3EC) : Colors.transparent, borderRadius: BorderRadius.circular(12)), child: Row(children: [Icon(icon, size: 19, color: selected ? _green : const Color(0xFF86938B)), const SizedBox(width: 12), Text(label, style: TextStyle(fontSize: 13, color: selected ? _green : const Color(0xFF65736B), fontWeight: selected ? FontWeight.w700 : FontWeight.w500))])));
  }

  Widget _mobileNav() => NavigationBar(height: 68, selectedIndex: ['Overview','Air mouse','File transfer','Media'].indexOf(_activeTab), onDestinationSelected: (i) => setState(() => _activeTab = ['Overview','Air mouse','File transfer','Media'][i]), destinations: const [NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Home'), NavigationDestination(icon: Icon(Icons.mouse_rounded), label: 'Mouse'), NavigationDestination(icon: Icon(Icons.folder_copy_rounded), label: 'Files'), NavigationDestination(icon: Icon(Icons.play_circle_outline_rounded), label: 'Media')]);

  Widget _topBar(bool mobile) => Container(height: 72, padding: EdgeInsets.symmetric(horizontal: mobile ? 18 : 34), decoration: const BoxDecoration(color: Colors.white, border: Border(bottom: BorderSide(color: Color(0xFFE9EEEA)))), child: Row(children: [if (mobile) ...[_brandMark(34), const SizedBox(width: 9), const Text('QR Sender', style: TextStyle(fontWeight: FontWeight.w800, color: _dark, fontSize: 17))] else Text(_activeTab, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _dark)), const Spacer(), _statusPill(), if (_connected) ...[const SizedBox(width: 12), IconButton(tooltip: 'Disconnect', onPressed: _disconnect, icon: const Icon(Icons.link_off_rounded, color: Color(0xFFB35545)))]]));

  Widget _statusPill() { final isOnline = _connected; return Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), decoration: BoxDecoration(color: isOnline ? const Color(0xFFEAF5ED) : const Color(0xFFF3F5F3), borderRadius: BorderRadius.circular(20)), child: Row(children: [Container(width: 7, height: 7, decoration: BoxDecoration(color: isOnline ? _green : const Color(0xFFA5B0A9), shape: BoxShape.circle)), const SizedBox(width: 7), Text(_status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isOnline ? _green : const Color(0xFF78857D)))])); }

  Widget _mainContent(bool mobile, double width) {
    if (_activeTab == 'Air mouse') return _airMousePage(mobile);
    if (_activeTab == 'File transfer') return _filesPage(mobile);
    if (_activeTab == 'Media') return _mediaPage(mobile);
    return _overview(mobile, width);
  }

  Widget _overview(bool mobile, double width) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Text('Move things between\nyour devices.', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontSize: mobile ? 32 : 42, height: 1.12)),
    const SizedBox(height: 11), const Text('A simple local bridge for your files, media and controls.', style: TextStyle(color: Color(0xFF6A786F), fontSize: 15)),
    const SizedBox(height: 28),
    if (_notice != null) _noticeBanner(),
    if (_connected) _connectedPanel(mobile) else _connectionCards(mobile),
    if (_connected && _isHost) ...[const SizedBox(height: 14), _remotePointerPreview()],
    const SizedBox(height: 26),
    Row(children: [const Expanded(child: Text('Your workspace', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: _dark))), if (_connected) _tinyTag('PEER LINK ACTIVE')]),
    const SizedBox(height: 13),
    Wrap(spacing: 14, runSpacing: 14, children: [
      _featureCard(width, mobile, 'Air mouse', 'Use your phone as a wireless trackpad and keyboard.', Icons.mouse_rounded, const Color(0xFFEAF3EC), () => setState(() => _activeTab = 'Air mouse')),
      _featureCard(width, mobile, 'Send files', 'Share documents and photos across your devices.', Icons.drive_folder_upload_rounded, const Color(0xFFF1EFFB), () => setState(() => _activeTab = 'File transfer')),
      _featureCard(width, mobile, 'Stream video', 'Send a local video to play on the connected screen.', Icons.video_library_outlined, const Color(0xFFFFF3E7), () => setState(() => _activeTab = 'Media')),
    ]),
    const SizedBox(height: 24),
    if (_activity.isNotEmpty) _activityCard(),
    const SizedBox(height: 16),
    _privacyNote(),
  ]);

  Widget _connectionCards(bool mobile) => Padding(padding: const EdgeInsets.only(top: 24, bottom: 30), child: LayoutBuilder(builder: (context, constraints) {
    final hostCard = _connectionCard(host: true, mobile: mobile);
    final joinCard = _connectionCard(host: false, mobile: mobile);
    if (mobile || constraints.maxWidth < 700) return Column(children: [hostCard, const SizedBox(height: 14), joinCard]);
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: hostCard), const SizedBox(width: 16), Expanded(child: joinCard)]);
  }));

  Widget _connectionCard({required bool host, required bool mobile}) => Container(padding: EdgeInsets.all(mobile ? 20 : 24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22), border: Border.all(color: const Color(0xFFE8EDE9)), boxShadow: const [BoxShadow(color: Color(0x080D2B18), blurRadius: 18, offset: Offset(0, 5))]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: host ? const Color(0xFFEAF3EC) : const Color(0xFFF0EEFA), borderRadius: BorderRadius.circular(14)), child: Icon(host ? Icons.qr_code_2_rounded : Icons.phonelink_rounded, color: host ? _green : const Color(0xFF6A58A8))), const SizedBox(width: 12), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(host ? 'Host a receiver' : 'Connect as sender', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _dark)), Text(host ? 'Show a code for another device' : 'Scan a QR or enter a pairing code', style: const TextStyle(fontSize: 12, color: Color(0xFF7B8980)))]))]),
    const SizedBox(height: 17),
    if (host) ...[
      const Text('This device will receive the connection. Share the QR code or 10-digit code with the sender.', style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF78857D))),
      const SizedBox(height: 13), _serverField(),
      const SizedBox(height: 14), _primaryButton(_busy ? 'Starting…' : 'Host / Display receiver', Icons.cast_connected_rounded, _busy ? null : _host),
      if (_otp != null) Padding(padding: const EdgeInsets.only(top: 12), child: _showCodeButton()),
    ] else ...[
      const Text('Pair this device with a receiver using the displayed QR code or one-time code.', style: TextStyle(fontSize: 12, height: 1.5, color: Color(0xFF78857D))),
      const SizedBox(height: 13), _serverField(),
      const SizedBox(height: 10), Row(children: [Expanded(child: TextField(controller: _otpController, keyboardType: TextInputType.number, maxLength: 10, decoration: const InputDecoration(hintText: '10-digit pairing code', counterText: '', prefixIcon: Icon(Icons.pin_outlined)), onSubmitted: (_) => _join())), const SizedBox(width: 9), SizedBox(height: 51, child: FilledButton(onPressed: _busy ? null : () => _join(), style: FilledButton.styleFrom(backgroundColor: _green, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))), child: const Icon(Icons.arrow_forward_rounded))) ]),
      const SizedBox(height: 4), SizedBox(width: double.infinity, child: OutlinedButton.icon(onPressed: _busy ? null : _showScanner, icon: const Icon(Icons.qr_code_scanner_rounded), label: const Text('Scan receiver QR'), style: OutlinedButton.styleFrom(foregroundColor: _green, side: const BorderSide(color: Color(0xFFD8E6DC)), padding: const EdgeInsets.symmetric(vertical: 12), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))))),
    ],
  ]));

  Widget _serverField() => TextField(controller: _serverController, autocorrect: false, decoration: const InputDecoration(labelText: 'Local relay address', hintText: 'ws://192.168.1.20:8787', prefixIcon: Icon(Icons.lan_outlined), isDense: true), style: const TextStyle(fontSize: 13));

  Widget _showCodeButton() => OutlinedButton.icon(onPressed: _showHostDialog, icon: const Icon(Icons.qr_code_2_rounded), label: const Text('Show QR & pairing code'), style: OutlinedButton.styleFrom(foregroundColor: _green, side: const BorderSide(color: Color(0xFFD8E6DC)), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13))));

  Future<void> _showHostDialog() async { if (_otp == null) return; await showDialog<void>(context: context, builder: (context) => AlertDialog(title: const Text('Pair with QR Sender'), content: SizedBox(width: 320, child: Column(mainAxisSize: MainAxisSize.min, children: [Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)), child: QrImageView(data: _qrPayload, size: 200, backgroundColor: Colors.white)), const SizedBox(height: 10), const Text('ONE-TIME PAIRING CODE', style: TextStyle(fontSize: 10, letterSpacing: 1.2, color: Color(0xFF829087), fontWeight: FontWeight.bold)), const SizedBox(height: 7), SelectableText(_otp!, style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: 5, color: _green)), const SizedBox(height: 8), const Text('Code expires after 10 minutes. Keep both devices on the same trusted network.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF77857D)))])), actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))])); }

  Widget _connectedPanel(bool mobile) => Container(margin: const EdgeInsets.only(top: 24), padding: const EdgeInsets.all(22), decoration: BoxDecoration(color: const Color(0xFF1F3A2C), borderRadius: BorderRadius.circular(22)), child: Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: Colors.white.withOpacity(.11), borderRadius: BorderRadius.circular(16)), child: const Icon(Icons.link_rounded, color: Colors.white)), const SizedBox(width: 15), Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('You’re connected', style: TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold)), const SizedBox(height: 4), Text('Choose a tool below to control or share with your peer.', style: TextStyle(color: Colors.white.withOpacity(.7), fontSize: 12))])), if (!mobile) OutlinedButton(onPressed: _disconnect, style: OutlinedButton.styleFrom(foregroundColor: Colors.white, side: BorderSide(color: Colors.white.withOpacity(.3))), child: const Text('Disconnect'))]));

  Widget _remotePointerPreview() => Container(height: 155, width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EDE9))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Remote pointer preview', style: TextStyle(fontWeight: FontWeight.w700, color: _dark, fontSize: 12)), const SizedBox(height: 9), Expanded(child: LayoutBuilder(builder: (context, box) => Container(width: double.infinity, decoration: BoxDecoration(color: const Color(0xFFF6F8F6), borderRadius: BorderRadius.circular(12)), child: Stack(children: [Positioned(left: (_cursorX * (box.maxWidth - 24)).clamp(0, box.maxWidth - 24).toDouble(), top: (_cursorY * (box.maxHeight - 24)).clamp(0, box.maxHeight - 24).toDouble(), child: const Icon(Icons.near_me_rounded, size: 24, color: _green))]))))]));

  Widget _featureCard(double width, bool mobile, String title, String body, IconData icon, Color tint, VoidCallback onTap) {
    final cardWidth = mobile ? width - 36 : (width - 340) / 3;
    return SizedBox(width: cardWidth.clamp(220, 360).toDouble(), child: InkWell(onTap: onTap, borderRadius: BorderRadius.circular(18), child: Container(padding: const EdgeInsets.all(19), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EDE9))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(13)), child: Icon(icon, color: _green)), const SizedBox(height: 15), Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15, color: _dark)), const SizedBox(height: 6), Text(body, style: const TextStyle(fontSize: 12, color: Color(0xFF78857D), height: 1.45)), const SizedBox(height: 11), const Row(children: [Text('Open tool', style: TextStyle(fontSize: 12, color: _green, fontWeight: FontWeight.w700)), SizedBox(width: 5), Icon(Icons.arrow_forward_rounded, size: 14, color: _green)])]))));
  }

  Widget _airMousePage(bool mobile) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [ _pageHeading('Air mouse', 'A wireless trackpad and keyboard for your connected device.'), if (_notice != null) _noticeBanner(), const SizedBox(height: 18), if (!_connected) _emptyConnection() else LayoutBuilder(builder: (context, c) { final pad = Trackpad(connected: _connected, onMove: (dx,dy) { _sendControl({'kind':'move','dx':dx,'dy':dy}); }, onClick: (b) { _sendControl({'kind':b}); _log('$b click sent'); }); if (c.maxWidth > 780) return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(flex: 6, child: _toolCard('Trackpad', 'Finger movement sends relative pointer motion.', pad)), const SizedBox(width: 16), Expanded(flex: 4, child: _keyboardCard())]); return Column(children: [_toolCard('Trackpad', 'Finger movement sends relative pointer motion.', pad), const SizedBox(height: 15), _keyboardCard()]); }), const SizedBox(height: 16), _privacyNote()]);

  Widget _keyboardCard() => _toolCard('Keyboard', 'Send text to the connected peer.', Column(children: [TextField(controller: _keyboardController, minLines: 2, maxLines: 4, textInputAction: TextInputAction.newline, decoration: const InputDecoration(hintText: 'Type here…', alignLabelWithHint: true), onChanged: (text) { if (_connected && text.isNotEmpty) _sendControl({'kind':'key','text':text}); }), const SizedBox(height: 12), Align(alignment: Alignment.centerRight, child: _primaryButton('Send text', Icons.keyboard_return_rounded, _connected ? () { _sendControl({'kind':'key','text':_keyboardController.text}); _log('Text sent to peer'); } : null))]));

  Widget _filesPage(bool mobile) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_pageHeading('File transfer', 'Move documents, photos and other files over your local connection.'), if (_notice != null) _noticeBanner(), const SizedBox(height: 18), if (!_connected) _emptyConnection() else _toolCard('Send files', 'Select one or more files from this device. The receiver will be asked to save them.', Column(children: [Container(width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 15), decoration: BoxDecoration(color: const Color(0xFFF5F8F5), border: Border.all(color: const Color(0xFFDDE8DF), style: BorderStyle.solid), borderRadius: BorderRadius.circular(18)), child: Column(children: [const Icon(Icons.cloud_upload_outlined, size: 38, color: _green), const SizedBox(height: 9), const Text('Choose files to send', style: TextStyle(fontWeight: FontWeight.w700, color: _dark)), const SizedBox(height: 5), const Text('Files are chunked and relayed locally.', style: TextStyle(fontSize: 12, color: Color(0xFF78857D))), const SizedBox(height: 16), _primaryButton('Browse files', Icons.folder_open_rounded, _connected ? () => _pickAndSend() : null)])), const SizedBox(height: 15), if (_incomingName != null) LinearProgressIndicator(color: _green, backgroundColor: const Color(0xFFE5ECE6)), if (_incomingName != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text('Receiving $_incomingName…', style: const TextStyle(fontSize: 12))), const SizedBox(height: 8), const Align(alignment: Alignment.centerLeft, child: Text('Note: transfers are buffered in memory; very large files may exceed browser memory.', style: TextStyle(fontSize: 11, color: Color(0xFF859189))))])), const SizedBox(height: 18), if (_activity.isNotEmpty) _activityCard(), const SizedBox(height: 16), _privacyNote()]);

  Widget _mediaPage(bool mobile) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [_pageHeading('Cross-device media', 'Send a local video to your peer and play it in the receiver view.'), if (_notice != null) _noticeBanner(), const SizedBox(height: 18), if (!_connected) _emptyConnection() else _toolCard('Share a video', 'Choose a video file. The peer receives the complete file before playback begins.', Column(children: [if (_videoController != null) _videoPlayer() else Container(height: 220, width: double.infinity, decoration: BoxDecoration(color: const Color(0xFF17251F), borderRadius: BorderRadius.circular(16)), child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.play_circle_outline_rounded, size: 48, color: Colors.white70), SizedBox(height: 8), Text('Ready for a video', style: TextStyle(color: Colors.white70))])), const SizedBox(height: 14), Row(children: [Expanded(child: Text(_videoName ?? 'MP4, WebM and other browser-supported formats', style: const TextStyle(fontSize: 12, color: Color(0xFF75837A)), overflow: TextOverflow.ellipsis)), const SizedBox(width: 12), _primaryButton('Choose video', Icons.video_file_outlined, _connected ? () => _pickAndSend(video:true) : null)])])), const SizedBox(height: 16), _privacyNote()]);

  Widget _videoPlayer() => ClipRRect(borderRadius: BorderRadius.circular(16), child: AspectRatio(aspectRatio: _videoController!.value.aspectRatio, child: Stack(alignment: Alignment.bottomCenter, children: [VideoPlayer(_videoController!), VideoProgressIndicator(_videoController!, allowScrubbing: true, colors: const VideoProgressColors(playedColor: Color(0xFF63BE87), bufferedColor: Colors.white30, backgroundColor: Colors.white12)), Positioned.fill(child: Center(child: IconButton(onPressed: () => setState(() { _videoController!.value.isPlaying ? _videoController!.pause() : _videoController!.play(); }), iconSize: 52, color: Colors.white, icon: Icon(_videoController!.value.isPlaying ? Icons.pause_circle : Icons.play_circle))))])));

  Widget _emptyConnection() => Container(width: double.infinity, padding: const EdgeInsets.all(24), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: const Color(0xFFE8EDE9))), child: Column(children: [const Icon(Icons.link_off_rounded, size: 32, color: Color(0xFF91A096)), const SizedBox(height: 9), const Text('Connect a device to use this tool', style: TextStyle(fontWeight: FontWeight.w700, color: _dark)), const SizedBox(height: 5), const Text('Go to Overview to host a receiver or join with a code.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Color(0xFF78857D))), const SizedBox(height: 13), TextButton(onPressed: () => setState(() => _activeTab = 'Overview'), child: const Text('Go to Overview'))]));

  Widget _pageHeading(String title, String subtitle) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 5), Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF6A786F)))]);

  Widget _toolCard(String title, String subtitle, Widget child) => Container(width: double.infinity, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0xFFE8EDE9))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: _dark)), const SizedBox(height: 3), Text(subtitle, style: const TextStyle(fontSize: 12, color: Color(0xFF7B8980))), const SizedBox(height: 16), child]));

  Widget _primaryButton(String label, IconData icon, VoidCallback? action) => FilledButton.icon(onPressed: action, icon: Icon(icon, size: 18), label: Text(label), style: FilledButton.styleFrom(backgroundColor: _green, foregroundColor: Colors.white, disabledBackgroundColor: const Color(0xFFBBCBC0), padding: const EdgeInsets.symmetric(horizontal: 17, vertical: 13), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)), textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)));

  Widget _noticeBanner() => Container(width: double.infinity, margin: const EdgeInsets.only(bottom: 16), padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: const Color(0xFFF0F5EF), borderRadius: BorderRadius.circular(13)), child: Row(children: [const Icon(Icons.info_outline_rounded, color: _green, size: 18), const SizedBox(width: 9), Expanded(child: Text(_notice!, style: const TextStyle(fontSize: 12, color: Color(0xFF45604D))))]));

  Widget _activityCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(17),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFE8EDE9)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Recent activity',
            style: TextStyle(fontWeight: FontWeight.w700, color: _dark),
          ),
          const SizedBox(height: 8),
          ..._activity.map(
            (item) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 5, color: _green),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(
                      item,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF748178),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _privacyNote() => Container(padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: const Color(0xFFF0F4EF), borderRadius: BorderRadius.circular(15)), child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.lock_outline_rounded, color: _green, size: 18), SizedBox(width: 10), Expanded(child: Text('Local relay mode: data is sent through the relay you run on your network, not a cloud service. Use only on a trusted LAN. For internet use, configure TLS (wss://) and a hardened relay.', style: TextStyle(fontSize: 11, height: 1.45, color: Color(0xFF67756D))))]));

  Widget _tinyTag(String label) => Container(padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5), decoration: BoxDecoration(color: const Color(0xFFEAF5ED), borderRadius: BorderRadius.circular(20)), child: Text(label, style: const TextStyle(fontSize: 9, color: _green, fontWeight: FontWeight.w800, letterSpacing: .5)));
  Widget _brandMark(double size) => Container(width: size, height: size, decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(size * .3)), child: Icon(Icons.qr_code_2_rounded, color: Colors.white, size: size * .62));
}
