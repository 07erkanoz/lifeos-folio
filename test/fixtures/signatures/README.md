# Synthetic CMS fixtures

Generated locally using OpenSSL `req -x509 -newkey ec` and `cms -sign -binary`.
All names, identifiers and certificates are test data. No private keys are stored;
temporary generation keys were removed. `content.xml` is the detached payload.

- `multiple.sgn`: two signers plus an unrelated self-signed CA certificate.
- `keyid.sgn`: SignerIdentifier uses subjectKeyIdentifier (`-keyid`).
- `missing-certificate.sgn`: certificate omitted (`-nocerts`).
- `unrelated-ca.der`: used to place the unrelated CA first in certificate-order tests.
- `rsa-valid.sgn`: detached RSA signature over `content.xml`, generated from
  a temporary test key. The private key was discarded; this fixture exercises
  cryptographic verification at the UYAP send gate.

OpenSSL `cms -verify -binary -inform DER -noverify` was used to check the
multiple-signature fixture against content.xml. This checks fixture signatures,
not CA trust. Application metadata display does not perform that verification.
