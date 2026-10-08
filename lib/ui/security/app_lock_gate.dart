import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../services/editor/lawyer_profile.dart';
import '../../services/office/office_ledger.dart';
import '../../services/security/app_lock.dart';

const _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];
const _days = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];

/// Covers all of Folio while it is locked, as a screen saver does: the
/// time, the office's name, and the password; or the recovery code, for a
/// new one. Any touch or key while open starts the idle time again.
class AppLockGate extends StatefulWidget {
  const AppLockGate({
    super.key,
    required this.child,
    this.lock,
    this.office,
    this.identify,
  });

  final Widget child;
  final AppLock? lock;

  /// Who signs in to e-Devlet, by TC number: a forgotten password renewed
  /// with e-imza or mobil imza. Null where it cannot be asked.
  final Future<String?> Function(BuildContext context)? identify;

  /// The office's name, when this device belongs to one; read from the
  /// office's ledger when not given.
  final String? office;

  @override
  State<AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends State<AppLockGate> with WidgetsBindingObserver {
  AppLock get _lock => widget.lock ?? AppLock.instance;
  String _office = '';
  DateTime? _away;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_key);
    _office = widget.office ?? '';
    if (widget.office == null) unawaited(_readOffice());
  }

  /// The office of the network; else the one the profile names; else the
  /// lawyer's own name.
  Future<void> _readOffice() async {
    final ledger = OfficeLedger();
    await ledger.load();
    var name = ledger.exists ? ledger.officeName.trim() : '';
    if (name.isEmpty) {
      try {
        final profile = await LawyerProfile.load();
        name = profile.officeName.trim();
        if (name.isEmpty) name = profile.lawyer?.titled ?? '';
      } catch (_) {}
    }
    if (mounted && name.isNotEmpty) setState(() => _office = name);
  }

  bool _key(KeyEvent _) {
    _lock.touch();
    return false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // A phone does not run the idle timer in the background: the time away
    // is counted when it comes back.
    if (state == AppLifecycleState.paused) _away = DateTime.now();
    if (state == AppLifecycleState.resumed) {
      final away = _away;
      _away = null;
      final idle = _lock.idleMinutes;
      if (away != null &&
          idle > 0 &&
          DateTime.now().difference(away).inMinutes >= idle) {
        _lock.lockNow();
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    HardwareKeyboard.instance.removeHandler(_key);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _lock,
    builder: (context, _) {
      final locked = _lock.loaded && _lock.locked;
      return Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (_) => _lock.touch(),
            child: ExcludeFocus(
              excluding: locked,
              child: TickerMode(enabled: !locked, child: widget.child),
            ),
          ),
          if (locked)
            Positioned.fill(
              child: Overlay(
                initialEntries: [
                  // A navigator of its own: e-Devlet's dialog opens over
                  // the lock, never over what it keeps hidden.
                  OverlayEntry(
                    builder: (_) => Navigator(
                      onGenerateRoute: (_) => PageRouteBuilder<void>(
                        pageBuilder: (_, _, _) => _LockScreen(
                          lock: _lock,
                          office: _office,
                          identify: widget.identify,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.lock, required this.office, this.identify});
  final AppLock lock;
  final String office;
  final Future<String?> Function(BuildContext context)? identify;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _password = TextEditingController();
  final _code = TextEditingController();
  final _new = TextEditingController();
  final _again = TextEditingController();
  late final Timer _clock;
  DateTime _now = DateTime.now();
  bool _busy = false, _recovering = false;
  String? _error, _newCode;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock.cancel();
    for (final c in [_password, _code, _new, _again]) {
      c.dispose();
    }
    super.dispose();
  }

  String? _waiting() {
    final until = widget.lock.waitUntil;
    if (until == null || !DateTime.now().isBefore(until)) return null;
    final s = until.difference(DateTime.now()).inSeconds + 1;
    return 'Çok sayıda yanlış deneme: $s saniye sonra yeniden deneyin.';
  }

  Future<void> _open() async {
    if (_busy) return;
    final wait = _waiting();
    if (wait != null) return setState(() => _error = wait);
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await widget.lock.unlock(_password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (!ok) _error = _waiting() ?? 'Şifre yanlış.';
      _password.clear();
    });
  }

  /// The new password, by e-Devlet: the TC number who signs in gives must
  /// be the lawyer's.
  Future<void> _recoverByEdevlet() async {
    if (_busy) return;
    final weak = AppLock.weakness(_new.text);
    if (weak != null) return setState(() => _error = weak);
    if (_new.text != _again.text) {
      return setState(() => _error = 'İki şifre aynı değil.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final tc = await widget.identify!(context);
    if (!mounted) return;
    final ok = tc != null && await widget.lock.recoverByIdentity(tc, _new.text);
    if (!mounted) return;
    // Renewed, Folio opens: there is no code to write down.
    setState(() {
      _busy = false;
      if (tc == null) {
        _error = 'e-Devlet girişi tamamlanmadı.';
      } else if (!ok) {
        _error =
            _waiting() ??
            'e-Devlet’e giren bu Folio’nun avukatı değil; şifre '
                'yenilenmedi.';
      } else {
        _recovering = false;
      }
    });
  }

  Future<void> _recover() async {
    if (_busy) return;
    final weak = AppLock.weakness(_new.text);
    if (weak != null) return setState(() => _error = weak);
    if (_new.text != _again.text) {
      return setState(() => _error = 'İki şifre aynı değil.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final code = await widget.lock.recover(_code.text, _new.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (code == null) {
        _error = _waiting() ?? 'Kurtarma kodu yanlış.';
      } else {
        _newCode = code;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final time =
        '${_now.hour.toString().padLeft(2, '0')}:${_now.minute.toString().padLeft(2, '0')}';
    final date =
        '${_now.day} ${_months[_now.month - 1]} ${_now.year}, ${_days[_now.weekday - 1]}';
    final office = widget.office.trim();
    InputDecoration field(String hint) => InputDecoration(
      hintText: hint,
      filled: true,
      fillColor: Colors.white.withValues(alpha: .08),
      hintStyle: TextStyle(color: Colors.white.withValues(alpha: .45)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: Color(0xFF8FB8F2)),
      ),
    );
    const ink = TextStyle(color: Colors.white);
    final shown = _newCode != null
        ? Column(
            key: const ValueKey('lock-new-code'),
            children: [
              const Text(
                'Yeni şifreniz konuldu. Eski kurtarma kodu artık geçmez; '
                'bu yeni kodu güvenli bir yere yazın:',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white70, height: 1.4),
              ),
              const SizedBox(height: 12),
              SelectableText(
                _newCode!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton(
                onPressed: () => setState(() {
                  _newCode = null;
                  _recovering = false;
                }),
                child: const Text('Yazdım, devam et'),
              ),
            ],
          )
        : _recovering
        ? Column(
            key: const ValueKey('lock-recover'),
            children: [
              if (widget.lock.hasCode) ...[
                TextField(
                  key: const ValueKey('lock-code'),
                  controller: _code,
                  autofocus: true,
                  style: ink,
                  textCapitalization: TextCapitalization.characters,
                  decoration: field('Kurtarma kodu'),
                ),
                const SizedBox(height: 8),
              ],
              TextField(
                key: const ValueKey('lock-new'),
                controller: _new,
                obscureText: true,
                style: ink,
                decoration: field('Yeni şifre'),
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('lock-again'),
                controller: _again,
                obscureText: true,
                style: ink,
                onSubmitted: (_) => unawaited(_recover()),
                decoration: field('Yeni şifre (yeniden)'),
              ),
              const SizedBox(height: 12),
              if (widget.lock.hasCode)
                FilledButton(
                  key: const ValueKey('lock-recover-go'),
                  onPressed: _busy ? null : () => unawaited(_recover()),
                  child: const Text('Kurtarma koduyla yenile'),
                ),
              if (widget.identify != null && widget.lock.knowsWhose) ...[
                const SizedBox(height: 10),
                Text(
                  widget.lock.hasCode
                      ? 'Kurtarma kodu elinizde değilse yeni şifreyi yazın '
                            've e-Devlet’e e-imza ya da mobil imzayla girin:'
                      : 'Yeni şifreyi yazın ve e-Devlet’e e-imza ya da '
                            'mobil imzayla girin:',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  key: const ValueKey('lock-recover-edevlet'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF8FB8F2)),
                  ),
                  onPressed: _busy
                      ? null
                      : () => unawaited(_recoverByEdevlet()),
                  icon: const Icon(Icons.verified_user_outlined, size: 18),
                  label: const Text('e-Devlet ile doğrula'),
                ),
              ],
              TextButton(
                onPressed: () => setState(() {
                  _recovering = false;
                  _error = null;
                }),
                child: const Text('Şifreyle aç'),
              ),
            ],
          )
        : Column(
            key: const ValueKey('lock-open'),
            children: [
              TextField(
                key: const ValueKey('lock-password'),
                controller: _password,
                autofocus: true,
                obscureText: true,
                style: ink,
                onSubmitted: (_) => unawaited(_open()),
                decoration: field('Şifre').copyWith(
                  suffixIcon: IconButton(
                    key: const ValueKey('lock-go'),
                    tooltip: 'Aç',
                    onPressed: _busy ? null : () => unawaited(_open()),
                    icon: _busy
                        ? const SizedBox.square(
                            dimension: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(
                            Icons.arrow_forward_rounded,
                            color: Colors.white,
                          ),
                  ),
                ),
              ),
              TextButton(
                key: const ValueKey('lock-forgot'),
                onPressed: () => setState(() {
                  _recovering = true;
                  _error = null;
                }),
                child: const Text(
                  'Şifremi unuttum',
                  style: TextStyle(color: Color(0xFF8FB8F2)),
                ),
              ),
            ],
          );
    return Material(
      color: const Color(0xFF0A1428),
      child: Stack(
        children: [
          const Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment(0, .55),
                  radius: 1.1,
                  colors: [Color(0x662B5EA8), Color(0x000A1428)],
                ),
              ),
            ),
          ),
          Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 72,
                        fontWeight: FontWeight.w200,
                        letterSpacing: 2,
                        fontFeatures: [FontFeature.tabularFigures()],
                      ),
                    ),
                    Text(
                      date,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .7),
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 36),
                    Text(
                      office.isEmpty ? 'LifeOS Folio' : office,
                      key: const ValueKey('lock-office'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: .5,
                      ),
                    ),
                    if (office.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          'LifeOS Folio',
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .5),
                            fontSize: 12.5,
                            letterSpacing: 2,
                          ),
                        ),
                      ),
                    const SizedBox(height: 26),
                    shown,
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          key: const ValueKey('lock-error'),
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Color(0xFFFF9C9C)),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
