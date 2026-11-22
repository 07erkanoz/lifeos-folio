// Folio Ajan'ın sesini denemek için küçük pencere (uygulamaya girmez):
//
//   flutter run -d linux -t tool/ajan_ses_deneme.dart
//
// Gemini anahtarı Folio'nun Ayarlar › Yapay zekâ bölümünde kayıtlı olmalı
// (ücretli anahtar). Beyin burada sahte: Folio'nun verisine dokunulmaz,
// "folio_ajan_sor" her soruya aynı deneme cevabını verir. Ölçülen, sesin
// kendisi: Türkçe anlama ve konuşma, eller serbest başlama, söze girme,
// yankı, sessizlikte kapanma ve tur başına maliyet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:evrak_convert/services/voice/live_conversation.dart';
import 'package:evrak_convert/services/voice/live_session.dart';
import 'package:evrak_convert/services/voice/live_tools.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MaterialApp(debugShowCheckedModeBanner: false, home: _Deneme()));
}

class _Deneme extends StatefulWidget {
  const _Deneme();
  @override
  State<_Deneme> createState() => _DenemeState();
}

class _DenemeState extends State<_Deneme> {
  late final LiveConversation c = LiveConversation(
    tools: FolioLiveTools(brain: _sahteBeyin),
  )..addListener(_yenile);
  final _sorular = <String>[];
  var _elsiz = true;

  Future<String> _sahteBeyin(String soru) async {
    _sorular.add(soru);
    _yenile();
    await Future<void>.delayed(const Duration(seconds: 2));
    return 'DENEME CEVABI: Yarın saat 10.30’da İzmir 5. Asliye Hukuk’ta bir '
        'duruşma var, istinaf süresi de 23 Kasım’da doluyor.';
  }

  void _yenile() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    c.dispose();
    super.dispose();
  }

  static const _durum = {
    LiveState.off: 'Kapalı',
    LiveState.waiting: 'Bekliyor: konuşunca başlar (ses dışarı gitmiyor)',
    LiveState.connecting: 'Bağlanıyor…',
    LiveState.listening: 'Dinliyor',
    LiveState.thinking: 'Düşünüyor',
    LiveState.working: 'Beyne sordu, bekliyor',
    LiveState.speaking: 'Konuşuyor',
  };

  @override
  Widget build(BuildContext context) {
    final cost = c.spent;
    return Scaffold(
      appBar: AppBar(
        title: Text('Folio Ajan · ses denemesi (${LiveSession.model})'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FilledButton(
                  onPressed: () =>
                      c.active ? c.stop() : c.start(handsFree: _elsiz),
                  child: Text(c.active ? 'Durdur' : 'Başlat'),
                ),
                FilterChip(
                  label: const Text('Eller serbest (Jarvis)'),
                  selected: _elsiz,
                  onSelected: c.active
                      ? null
                      : (v) => setState(() => _elsiz = v),
                ),
                FilterChip(
                  label: const Text('Kulaklık takılı'),
                  selected: c.headphones,
                  onSelected: (v) => setState(() => c.headphones = v),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              _durum[c.state]!,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            ValueListenableBuilder<double>(
              valueListenable: c.microphone.level,
              builder: (_, v, _) => LinearProgressIndicator(value: v),
            ),
            if (c.error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  c.error!,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              'Bu konuşma: \$${cost.dollars.toStringAsFixed(4)} · son tur '
              '\$${c.lastTurn.dollars.toStringAsFixed(4)} · giriş ${cost.input} '
              '(ses ${cost.audioIn}) · çıkış ${cost.output} (ses ${cost.audioOut}) jeton',
            ),
            if (_sorular.isNotEmpty) Text('Beyne giden: ${_sorular.last}'),
            const Divider(),
            Expanded(
              child: ListView(
                children: [
                  for (final l in c.lines)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        '${l.who == 'avukat'
                            ? 'Siz'
                            : l.who == 'ajan'
                            ? 'Ajan'
                            : 'Bilgi'}: ${l.text}',
                        style: TextStyle(
                          color: l.who == 'bilgi' ? Colors.grey : null,
                          fontWeight: l.who == 'avukat'
                              ? FontWeight.w600
                              : null,
                        ),
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
}
