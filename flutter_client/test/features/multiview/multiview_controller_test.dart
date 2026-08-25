import 'package:flutter_test/flutter_test.dart';
import 'package:m3u_tv/features/multiview/multiview_controller.dart';
import 'package:m3u_tv/services/domain_models.dart';

Channel _channel(int id) => Channel(
  id: id,
  name: 'Channel $id',
  streamUrl: 'http://example.com/$id.m3u8',
);

void main() {
  group('MultiviewController', () {
    test('toggle adds and then removes a channel', () {
      final controller = MultiviewController();
      final channel = _channel(1);

      final added = controller.toggle(channel);

      expect(added, isTrue);
      expect(controller.channels, [channel]);
      expect(controller.contains(1), isTrue);

      final addedAgain = controller.toggle(channel);

      expect(addedAgain, isFalse);
      expect(controller.channels, isEmpty);
      expect(controller.contains(1), isFalse);
    });

    test('notifies listeners on toggle', () {
      var notifications = 0;
      final controller = MultiviewController()
        ..addListener(() => notifications++)
        ..toggle(_channel(1))
        ..toggle(_channel(1));

      expect(notifications, 2);
      expect(controller.channels, isEmpty);
    });

    test('refuses to add past maxStreams', () {
      final controller = MultiviewController();
      for (var i = 0; i < MultiviewController.maxStreams; i++) {
        expect(controller.toggle(_channel(i)), isTrue);
      }

      expect(controller.isFull, isTrue);
      expect(controller.toggle(_channel(99)), isFalse);
      expect(controller.channels.length, MultiviewController.maxStreams);
    });

    test('reorder moves a channel to its new index', () {
      final controller = MultiviewController()
        ..toggle(_channel(1))
        ..toggle(_channel(2))
        ..toggle(_channel(3))
        ..reorder(0, 2);

      expect(controller.channels.map((c) => c.id), [2, 3, 1]);
    });

    test('reorder ignores out-of-range indices', () {
      final controller = MultiviewController()
        ..toggle(_channel(1))
        ..reorder(0, 5);

      expect(controller.channels.map((c) => c.id), [1]);
    });

    test('remove drops a channel by id and notifies listeners', () {
      var notifications = 0;
      final controller = MultiviewController()
        ..toggle(_channel(1))
        ..toggle(_channel(2))
        ..addListener(() => notifications++)
        ..remove(1);

      expect(controller.channels.map((c) => c.id), [2]);
      expect(notifications, 1);
    });

    test('remove is a no-op for an id that is not queued', () {
      var notifications = 0;
      final controller = MultiviewController()
        ..toggle(_channel(1))
        ..addListener(() => notifications++)
        ..remove(99);

      expect(controller.channels.map((c) => c.id), [1]);
      expect(notifications, 0);
    });

    test('clear empties the selection', () {
      final controller = MultiviewController()
        ..toggle(_channel(1))
        ..toggle(_channel(2))
        ..clear();

      expect(controller.channels, isEmpty);
    });
  });
}
