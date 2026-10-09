import 'dart:io';

import 'client.dart';
import 'client_accounts.dart';

/// How a client is written to: each opens the lawyer's own program with
/// the message written, and the lawyer sends it.
enum MessageChannel {
  whatsapp('WhatsApp'),
  sms('SMS'),
  email('E-posta');

  const MessageChannel(this.label);
  final String label;
}

/// What a message tells the client.
enum MessageKind {
  hearing('Duruşma hatırlatma'),
  result('Duruşma sonucu'),
  instalment('Taksit hatırlatma'),
  receipt('Ödeme alındı'),
  free('Serbest');

  const MessageKind(this.label);
  final String label;
}

const _days = [
  'Pazartesi',
  'Salı',
  'Çarşamba',
  'Perşembe',
  'Cuma',
  'Cumartesi',
  'Pazar',
];
const _months = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];

String _two(int v) => v.toString().padLeft(2, '0');

/// "22 Ekim 2026 Perşembe saat 10:30".
String longDay(DateTime t, {bool time = true}) =>
    '${t.day} ${_months[t.month - 1]} ${t.year} ${_days[t.weekday - 1]}'
    '${time ? ' saat ${_two(t.hour)}:${_two(t.minute)}' : ''}';

/// The message's words, to be read over before it goes: the court named,
/// never the case's number nor the other side (it goes through others'
/// servers). [court] the case's court; [at] the hearing's time or the
/// instalment's day; [amount] in kuruş.
({String subject, String body}) messageText(
  MessageKind kind, {
  required String client,
  required String lawyer,
  String court = '',
  DateTime? at,
  int amount = 0,
  String result = '',
}) {
  final hello = 'Sayın $client,';
  final where = court.isEmpty ? 'davanızın' : "$court'ndeki davanızın";
  final body = switch (kind) {
    MessageKind.hearing =>
      '$where duruşması '
          '${at == null ? 'yaklaşmaktadır' : '${longDay(at)}\'dadır'}. '
          'Duruşmadan önce görüşmemiz gereken bir konu olursa bana '
          'ulaşabilirsiniz.',
    MessageKind.result =>
      '$where ${at == null ? '' : '${longDay(at, time: false)} günkü '}'
          'duruşması yapıldı.'
          '${result.isEmpty ? '' : ' Sonuç: $result.'} '
          'Ayrıntıları görüşmek için bana ulaşabilirsiniz.',
    MessageKind.instalment =>
      'avukatlık ücretinin ${lira(amount)} tutarındaki taksidinin ödeme '
          'günü ${at == null ? 'yaklaşmaktadır' : '${longDay(at, time: false)}\'dir'}. '
          'Bilginize sunarım.',
    MessageKind.receipt =>
      '${at == null ? '' : '${longDay(at)} tarihinde '}'
          'yaptığınız ${lira(amount)} tutarındaki ödeme alınmıştır. '
          'Teşekkür ederim.',
    MessageKind.free => '',
  };
  final subject = switch (kind) {
    MessageKind.hearing =>
      'Duruşma hatırlatması${at == null ? '' : ' · ${_two(at.day)}.${_two(at.month)}.${at.year}'}',
    MessageKind.result => 'Duruşma sonucu',
    MessageKind.instalment => 'Taksit hatırlatması',
    MessageKind.receipt => 'Ödemeniz alındı',
    MessageKind.free => '',
  };
  final text = body.isEmpty
      ? '$hello\n\n\n\n$lawyer'
      : '$hello\n${body[0].toUpperCase()}${body.substring(1)}\n\n$lawyer';
  return (subject: subject, body: text);
}

/// The number as WhatsApp and SMS take it: digits, the country's code
/// before ("0532 000 00 41" → "905320000041"); empty when it is no number.
String phoneDigits(String phone) {
  var d = phone.replaceAll(RegExp(r'\D'), '');
  if (d.startsWith('00')) d = d.substring(2);
  if (d.length == 11 && d.startsWith('0')) d = '90${d.substring(1)}';
  if (d.length == 10 && d.startsWith('5')) d = '90$d';
  return d.length < 10 ? '' : d;
}

/// The ways [text] may open, in the order to try them: WhatsApp's own
/// program on a computer (WhatsApp on Windows, WhatSie on Linux), else
/// its page; on a phone the link that opens the app where it is. With no
/// number or address on the card, the message opens all the same and the
/// lawyer picks who it goes to there.
List<Uri> messageLinks(
  MessageChannel channel, {
  required String phone,
  required String email,
  required String subject,
  required String text,
}) {
  final digits = phoneDigits(phone);
  String enc(String s) => Uri.encodeComponent(s);
  return switch (channel) {
    MessageChannel.whatsapp =>
      Platform.isAndroid || Platform.isIOS
          ? [Uri.parse('https://wa.me/$digits?text=${enc(text)}')]
          : [
              Uri.parse(
                'whatsapp://send?${digits.isEmpty ? '' : 'phone=$digits&'}'
                'text=${enc(text)}',
              ),
              Uri.parse(
                'https://web.whatsapp.com/send?'
                '${digits.isEmpty ? '' : 'phone=$digits&'}text=${enc(text)}',
              ),
            ],
    MessageChannel.sms => [
      Uri.parse(
        'sms:${digits.isEmpty ? '' : '+$digits'}'
        '${Platform.isIOS ? '&' : '?'}body=${enc(text)}',
      ),
    ],
    MessageChannel.email => [
      Uri.parse(
        'mailto:${email.trim()}?subject=${enc(subject)}'
        '&body=${enc(text)}',
      ),
    ],
  };
}

/// A message sent, kept on the client's timeline: what, by which way,
/// and of what ([about]: a hearing's or an instalment's key), so that the
/// day's list does not ask for it again.
ClientRecord messageRecord({
  required String clientId,
  required MessageChannel channel,
  required MessageKind kind,
  required String text,
  required String lawyer,
  String caseKey = '',
  String about = '',
  String person = '',
}) {
  final now = DateTime.now();
  return ClientRecord(
    id: Client.newId(),
    clientId: clientId,
    kind: ClientRecordKind.message,
    data: {
      'kanal': channel.name,
      'tur': kind.name,
      'metin': text,
      'dosya': caseKey,
      'konu': about,
    },
    created: now,
    by: lawyer,
    updated: now,
    locked: true,
    person: person,
  );
}

/// One message the day asks for: to whom, of what.
class DueMessage {
  const DueMessage({
    required this.client,
    required this.kind,
    required this.at,
    required this.about,
    this.caseKey = '',
    this.court = '',
    this.amount = 0,
    this.daysLeft = 0,
  });
  final Client client;
  final MessageKind kind;
  final DateTime at;
  final String about, caseKey, court;
  final int amount, daysLeft;
}
