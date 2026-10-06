import 'package:evrak_convert/services/portal/portal_channel.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const web = PortalChannel.uyapWeb;
  const mobile = PortalChannel.uyapMobile;
  const both = {web, mobile};

  test('where both can answer, the web comes first and the mobile fills', () {
    expect(ChannelTable.channels(UyapOp.parties, both), [web, mobile]);
    expect(ChannelTable.channels(UyapOp.documentDownload, both), [web, mobile]);
    expect(ChannelTable.channels(UyapOp.documentList, {mobile}), [mobile]);
  });

  test('the case list and the hearings are asked of both and merged', () {
    for (final op in [UyapOp.caseList, UyapOp.hearings]) {
      expect(ChannelTable.rule(op).merged, isTrue);
      expect(ChannelTable.channels(op, both), [web, mobile]);
    }
  });

  test('the Court of Cassation and the prosecutors are the web’s alone', () {
    for (final family in [CaseFamily.yargitay, CaseFamily.prosecutor]) {
      for (final op in [
        UyapOp.caseList,
        UyapOp.parties,
        UyapOp.documentList,
        UyapOp.documentDownload,
      ]) {
        expect(ChannelTable.channels(op, {mobile}, family), isEmpty);
        expect(ChannelTable.channels(op, both, family), [web]);
      }
    }
  });

  test('a write goes to its own channel only, never to the other', () {
    expect(ChannelTable.channels(UyapOp.send, {mobile}), isEmpty);
    expect(ChannelTable.channels(UyapOp.send, both), [web]);
    expect(ChannelTable.channels(UyapOp.excuse, {web}), isEmpty);
    expect(ChannelTable.channels(UyapOp.eHearing, both), [mobile]);
    expect(ChannelTable.rule(UyapOp.send).writes, isTrue);
  });

  test('proceedings and money come from the web only', () {
    expect(ChannelTable.channels(UyapOp.proceedings, {mobile}), isEmpty);
    expect(ChannelTable.channels(UyapOp.money, both), [web]);
  });

  test('UETS answers no UYAP operation', () {
    for (final op in UyapOp.values) {
      expect(ChannelTable.channels(op, {PortalChannel.uets}), isEmpty);
    }
  });
}
