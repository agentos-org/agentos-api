import 'package:agentos_api/agentos_api.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

void main() {
  late DateTime now;
  late NotifyKitService service;

  setUp(() {
    now = DateTime.utc(2026, 9, 23, 12);
    service = NotifyKitService(clock: () => now);
  });

  tearDown(() => service.dispose());

  test('deduplicates repeated App events without an App-owned key', () {
    final first = service.publishApp(
      bundleId: 'com.example.mail',
      event: const NotifyKitAppEvent(
        eventType: 'sync.completed',
        title: 'Sync complete',
        message: 'Inbox is up to date.',
      ),
    );
    final second = service.publishApp(
      bundleId: 'com.example.mail',
      event: const NotifyKitAppEvent(
        eventType: 'sync.completed',
        title: 'Sync complete',
        message: 'Inbox is up to date.',
      ),
    );

    expect(second.id, first.id);
    expect(second.count, 2);
    expect(second.level, NotifyKitLevel.success);
    expect(service.snapshot().groups.single.itemCount, 1);
    expect(service.snapshot().groups.single.eventCount, 2);
  });

  test('keeps grouping, severity and priority under platform control', () {
    final notification = service.publishApp(
      bundleId: 'com.example.app',
      event: const NotifyKitAppEvent(
        eventType: 'task.failed',
        title: 'Task failed',
        message: 'The task could not be completed.',
      ),
    );

    expect(notification.category, 'task');
    expect(notification.level, NotifyKitLevel.warning);
    expect(notification.sourceType, 'app');

    final arbitrary = service.publishApp(
      bundleId: 'com.example.app',
      event: const NotifyKitAppEvent(
        eventType: 'vendor.error',
        title: 'Vendor error',
        message: 'The vendor reported an error.',
      ),
    );
    expect(arbitrary.level, NotifyKitLevel.info);
  });

  test('collapses unknown and overflow categories into other', () {
    service = NotifyKitService(clock: () => now, maxGroupsPerSource: 3);

    for (final type in const <String>[
      'auth.signed-in',
      'chat.message',
      'download.finished',
    ]) {
      service.publishApp(
        bundleId: 'com.example.app',
        event: NotifyKitAppEvent(eventType: type, title: type, message: type),
      );
    }
    service.publishApp(
      bundleId: 'com.example.app',
      event: const NotifyKitAppEvent(
        eventType: 'vendor.custom',
        title: 'Custom',
        message: 'Custom event',
      ),
    );

    final groups = service.snapshot().groups;
    expect(groups, hasLength(3));
    expect(
      groups.map((group) => group.category),
      containsAll(<String>['auth', 'chat', 'other']),
    );
    expect(groups.where((group) => group.category == 'other'), hasLength(1));
  });

  test('rate limits an App source independently of notification content', () {
    service = NotifyKitService(
      clock: () => now,
      maxEventsPerSourcePerMinute: 2,
    );
    for (var index = 0; index < 2; index++) {
      service.publishApp(
        bundleId: 'com.example.app',
        event: NotifyKitAppEvent(
          eventType: 'task.started',
          title: 'Task $index',
          message: 'Started',
        ),
      );
    }

    expect(
      () => service.publishApp(
        bundleId: 'com.example.app',
        event: const NotifyKitAppEvent(
          eventType: 'task.started',
          title: 'Another task',
          message: 'Started',
        ),
      ),
      throwsA(isA<NotifyKitRateLimitException>()),
    );
  });

  test('markSeen clears the unread state until a newer event arrives', () {
    service.publishApp(
      bundleId: 'com.example.app',
      event: const NotifyKitAppEvent(
        eventType: 'update.available',
        title: 'Update available',
        message: 'A new version is ready.',
      ),
    );
    expect(service.snapshot().hasUnread, isTrue);

    service.markSeen();
    expect(service.snapshot().hasUnread, isFalse);

    now = now.add(const Duration(seconds: 1));
    service.publishApp(
      bundleId: 'com.example.app',
      event: const NotifyKitAppEvent(
        eventType: 'update.available',
        title: 'Update available',
        message: 'A new version is ready.',
      ),
    );
    expect(service.snapshot().hasUnread, isTrue);
  });

  test(
    'NotifyKit controller derives the App source from its AppKit token',
    () async {
      final appKit = AppKitService();
      final token = appKit
          .registerBundle(AppBundleDto(bundleId: 'com.example.app'))
          .token;
      final controller = NotifyKitController(
        service: service,
        appKitService: appKit,
      );

      final unauthorized = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/notifications'),
          body: '{}',
        ),
      );
      expect(unauthorized.statusCode, 401);

      final response = await controller.router.call(
        Request(
          'POST',
          Uri.parse('http://localhost/notifications'),
          headers: {'authorization': 'Bearer $token'},
          body:
              '{"eventType":"task.failed","title":"Failed","message":"Nope","priority":"critical","group":"marketing"}',
        ),
      );
      final body = await response.readAsString();

      expect(response.statusCode, 200);
      expect(body, contains('"source":"com.example.app"'));
      expect(body, contains('"level":"warning"'));
      expect(body, isNot(contains('critical')));
      expect(body, isNot(contains('marketing')));
    },
  );
}
