import 'dart:async';

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../services/speech/speech_session.dart';
import 'speech_actions.dart';

/// Use the app's Flutter Material toolbar. The viewer's default toolbar uses
/// material_ui localizations, which are absent from our Flutter MaterialApp.
/// In release that missing localization renders a grey ErrorWidget over the PDF.
Widget? buildPreviewContextMenu(
  BuildContext context,
  PdfViewerContextMenuBuilderParams params,
) {
  final selection = params.textSelectionDelegate;
  final items = <ContextMenuButtonItem>[
    if (params.isTextSelectionEnabled &&
        selection.isCopyAllowed &&
        selection.hasSelectedText)
      ContextMenuButtonItem(
        label: 'Kopyala',
        type: ContextMenuButtonType.copy,
        onPressed: () {
          params.dismissContextMenu();
          selection.copyTextSelection();
        },
      ),
    // Only the selection, read aloud: the whole document is the button's.
    // A PDF that forbids copying its text is not read out either.
    if (speechAvailable &&
        params.isTextSelectionEnabled &&
        selection.isCopyAllowed &&
        selection.hasSelectedText)
      ContextMenuButtonItem(
        label: 'Sesli oku',
        onPressed: () {
          params.dismissContextMenu();
          unawaited(
            readAloud(
              context,
              owner: previewSpeech,
              text: selection.getSelectedText,
            ),
          );
        },
      ),
    if (params.isTextSelectionEnabled && !selection.isSelectingAllText)
      ContextMenuButtonItem(
        label: 'Tümünü seç',
        type: ContextMenuButtonType.selectAll,
        onPressed: () {
          params.dismissContextMenu();
          selection.selectAllText();
        },
      ),
  ];
  if (items.isEmpty) return null;
  return Align(
    alignment: Alignment.topLeft,
    child: AdaptiveTextSelectionToolbar.buttonItems(
      anchors: TextSelectionToolbarAnchors(
        primaryAnchor: params.anchorA,
        secondaryAnchor: params.anchorB,
      ),
      buttonItems: items,
    ),
  );
}
