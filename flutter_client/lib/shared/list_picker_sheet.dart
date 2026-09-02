import 'package:dpad/dpad.dart';
import 'package:flutter/material.dart';

import 'package:m3u_tv/shared/app_button.dart';

/// Generic bottom-sheet picker for "show all X" overflow scenarios on
/// the narrow breakpoint. Mirrors the season picker's mobile form
/// (one [DpadRegion] containing a title row + capped ListView, sheet
/// anchored at the bottom with a drag handle).
///
/// Used by the cast "Show all" overflow tile on VOD and Series detail
/// screens; also a natural fit for any future "more items" affordance
/// that needs a scrollable mobile sheet. The picker's contents are
/// caller-supplied via [children] — this widget owns only the modal
/// chrome.
///
/// Focus lands on the [autofocusIndex] child (default 0) so the list is
/// immediately drivable by D-pad. The list is height-capped with a
/// [ConstrainedBox] (not a [Flexible]) so the layout stays
/// deterministic inside the modal's intrinsic sizing — a Flexible
/// there lets rows overflow the sheet's clip and drop out of
/// hit-testing.
class ListPickerSheet extends StatelessWidget {
  const ListPickerSheet({
    super.key,
    required this.title,
    required this.children,
    this.autofocusIndex = 0,
    this.cancelLabel,
  });

  /// Header text in the sheet's title row.
  final String title;

  /// Scrollable row widgets. Caller owns their layout — typically one
  /// ListTile or DpadInkWell per item.
  final List<Widget> children;

  /// Index of the child that receives initial focus when the sheet
  /// opens. Pass -1 to disable autofocus.
  final int autofocusIndex;

  /// Tooltip / semantics label for the close icon button. Falls back
  /// to "Cancel" if null (callers should localize).
  final String? cancelLabel;

  /// Show the sheet. Convenience wrapper that opens a drag-handle
  /// bottom sheet (modally, anchored to the root navigator) sized to
  /// the supplied [children]. The inner list caps at 70% of the
  /// viewport so long lists scroll inside the sheet instead of
  /// pushing it off-screen.
  static Future<void> show(
    BuildContext context, {
    required String title,
    required List<Widget> children,
    int autofocusIndex = 0,
    String? cancelLabel,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ListPickerSheet(
          title: title,
          autofocusIndex: autofocusIndex,
          cancelLabel: cancelLabel,
          children: children,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewportHeight = MediaQuery.sizeOf(context).height;
    final scheme = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleLarge?.copyWith(
          color: scheme.onSurface,
        );
    final maxListHeight = viewportHeight * 0.7;

    return DpadRegion(
      verticalEdge: DpadEdgeBehavior.stop,
      horizontalEdge: DpadEdgeBehavior.stop,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 12, 4),
            child: Row(
              children: [
                Expanded(child: Text(title, style: titleStyle)),
                AppIconButton(
                  icon: Icons.close,
                  dense: true,
                  tooltip: cancelLabel ?? 'Cancel',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxListHeight),
            child: Scrollbar(
              child: ListView(
                shrinkWrap: true,
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                children: [
                  for (var i = 0; i < children.length; i++)
                    if (i == autofocusIndex)
                      Focus(autofocus: true, child: children[i])
                    else
                      children[i],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
