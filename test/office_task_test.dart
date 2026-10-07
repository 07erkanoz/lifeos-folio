import 'package:evrak_convert/services/office/office_task.dart';
import 'package:flutter_test/flutter_test.dart';

OfficeTask task({DateTime? due, List<TaskCase> cases = const []}) => OfficeTask(
  id: 't1',
  title: 'Bilirkişi raporuna itiraz',
  by: 'giver',
  byName: 'Av. Deniz Kaya',
  assignees: const {'doer': 'Stj. Av. Mert Yıldız'},
  createdAt: DateTime(2026, 10, 7),
  due: due,
  cases: cases,
)..events.add(TaskEvent.create(TaskEventKind.given, 'giver', 'Av. Deniz Kaya'));

TaskEvent ev(
  TaskEventKind k,
  String by, {
  int? percent,
  String? item,
  int min = 1,
}) => TaskEvent(
  id: '$k$by$min$item',
  kind: k,
  by: by,
  byName: by,
  at: DateTime(2026, 10, 7, 10, min),
  percent: percent,
  itemId: item,
);

void main() {
  test('the stage is what happened last; sent back is running again', () {
    final t = task();
    expect(t.stage, TaskStage.given);
    t.events.add(ev(TaskEventKind.accepted, 'doer', min: 2));
    expect(t.stage, TaskStage.running);
    t.events.add(ev(TaskEventKind.delivered, 'doer', min: 3));
    expect(t.stage, TaskStage.review);
    t.events.add(ev(TaskEventKind.returned, 'giver', min: 4));
    expect(t.stage, TaskStage.running);
    expect(t.open, isTrue);
    t.events.add(ev(TaskEventKind.delivered, 'doer', min: 5));
    t.events.add(ev(TaskEventKind.approved, 'giver', min: 6));
    expect(t.stage, TaskStage.done);
    expect(t.percent, 100);
    // Done stays done.
    t.events.add(ev(TaskEventKind.progress, 'doer', min: 7, percent: 10));
    expect(t.stage, TaskStage.done);
  });

  test('how far along: by its items, else by the last progress', () {
    final items = [
      TaskItem.create('Dilekçe'),
      TaskItem.create('Tanık listesi'),
    ];
    final t = task(
      cases: [
        TaskCase(
          caseKey: 'k',
          number: '2024/318',
          court: 'Antalya 3. Asliye',
          items: items,
        ),
      ],
    );
    expect(t.percent, 0);
    t.events.add(
      ev(TaskEventKind.itemDone, 'doer', item: items.first.id, min: 2),
    );
    expect(t.percent, 50);
    t.events.add(
      ev(TaskEventKind.itemOpen, 'doer', item: items.first.id, min: 3),
    );
    expect(t.percent, 0);
    final plain = task()
      ..events.add(ev(TaskEventKind.progress, 'doer', percent: 60, min: 2));
    expect(plain.percent, 60);
  });

  test('days left and late', () {
    final now = DateTime(2026, 10, 8, 15);
    expect(task(due: DateTime(2026, 10, 10)).daysLeft(now), 2);
    expect(task(due: DateTime(2026, 10, 8)).late(now), isFalse);
    expect(task(due: DateTime(2026, 10, 5)).daysLeft(now), -3);
    expect(task(due: DateTime(2026, 10, 5)).late(now), isTrue);
    expect(task().daysLeft(now), isNull);
  });

  test('each may do only their part', () {
    final t = task();
    expect(mayDo(t, TaskEventKind.approved, 'doer'), isFalse);
    expect(mayDo(t, TaskEventKind.delivered, 'giver'), isFalse);
    expect(mayDo(t, TaskEventKind.message, 'doer'), isTrue);
    expect(mayDo(t, TaskEventKind.message, 'stranger'), isFalse);
  });

  test(
    'a copy from another device adds only what its makers may make',
    () async {
      final store = OfficeTasks(
        file: () async => throw UnsupportedError('memory'),
      );
      final mine = task();
      await store.put(mine).catchError((_) {});
      final theirs = OfficeTask.fromJson(mine.toJson())!
        ..events.add(ev(TaskEventKind.accepted, 'doer', min: 2))
        // An approval said to come from the doer is not the giver's.
        ..events.add(ev(TaskEventKind.approved, 'doer', min: 3));
      await store.merge(theirs, from: 'doer').catchError((_) => false);
      expect(store.of('t1')!.stage, TaskStage.running);
      // A task no giver sent is not taken in.
      final stray = OfficeTask.fromJson({...mine.toJson(), 'id': 't2'})!;
      expect(
        await store.merge(stray, from: 'doer').catchError((_) => false),
        isFalse,
      );
      expect(store.of('t2'), isNull);
    },
  );
}
