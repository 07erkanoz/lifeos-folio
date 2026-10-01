import 'package:flutter/foundation.dart';

/// Signing with an e-signature card is a desktop action: it needs the card's
/// PKCS#11 driver. Reading signatures and editing stay available on phones
/// and tablets independently of this capability.
bool get desktopSigningAvailable =>
    !kIsWeb &&
    switch (defaultTargetPlatform) {
      TargetPlatform.linux ||
      TargetPlatform.windows ||
      TargetPlatform.macOS => true,
      _ => false,
    };

/// Signing with a mobile signature needs no card, only the network and the
/// phone the signature is on: it is offered on Android as on a desktop.
bool get mobileSigningAvailable =>
    desktopSigningAvailable ||
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

/// Whether a document can be signed here in any way at all.
bool get signingAvailable => desktopSigningAvailable || mobileSigningAvailable;
