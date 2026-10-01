#!/usr/bin/env bash
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${RUNNER_TEMP:?}"
cd "$(dirname "$0")/../.."
for abi in arm64-v8a armeabi-v7a x86_64; do
  test -s "artifacts/LifeOS-Folio-Android-${abi}.apk" || {
    echo "Missing or empty APK: ${abi}" >&2
    exit 1
  }
done
(cd artifacts && sha256sum ./*.apk > SHA256SUMS.txt)
tag="android-test-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
notes_file="${RUNNER_TEMP}/folio-android-release-notes.md"
cat > "$notes_file" <<EOF
Android test APK paketleri: arm64-v8a, armeabi-v7a ve x86_64.
Güncel telefonların çoğunda arm64-v8a paketini kullanın.

Kaynak commit: ${GITHUB_SHA}
Derleme: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}

APK dosyaları release modunda, geliştirme anahtarıyla imzalanmıştır; mağaza yayını değildir.
SHA-256 sağlama değerleri SHA256SUMS.txt dosyasındadır.
EOF
gh release create "$tag" artifacts/*.apk artifacts/SHA256SUMS.txt \
  --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" --prerelease --latest=false \
  --title "LifeOS Folio Android APK - test ${GITHUB_RUN_ID}" --notes-file "$notes_file"
url="$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json url --jq .url)"
test -n "$url"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Android APK hazır: [Test sürümünden indir](%s).\n' "$url" >> "$GITHUB_STEP_SUMMARY"
fi
printf 'Android APK packages uploaded: %s\n' "$url"
