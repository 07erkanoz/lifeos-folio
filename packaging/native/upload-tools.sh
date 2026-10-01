#!/usr/bin/env bash
# Deliver a rebuilt tool set for review. Actions artifact storage is a small
# shared quota that the app's test packages already outgrew, so the same route
# they take is used here: a prerelease, which does not consume that quota.
# This is still not a push. The binaries reach the repository only when a
# maintainer downloads this archive, runs the smoke test on the target OS and
# commits the result.
set -euo pipefail
: "${GITHUB_REPOSITORY:?}" "${GITHUB_SHA:?}" "${GITHUB_RUN_ID:?}" "${GITHUB_RUN_ATTEMPT:?}" "${RUNNER_TEMP:?}"
target="${1:?target required}"
# The folder the tools were built into: <target>-x64, or macos-universal.
name="${2:-${target}-x64}"
cd "$(dirname "$0")/../.."
dir="native_tools/${name}"
test -d "$dir" || { echo "Missing tool directory: $dir" >&2; exit 1; }
archive="${RUNNER_TEMP}/folio-native-tools-${name}.tar.gz"
# Tar rather than loose assets: it keeps bin/ and tessdata/ apart and carries
# the executable bit, which a release asset download would otherwise drop.
tar -czf "$archive" -C native_tools "${name}"
# A Mac has shasum where Linux has sha256sum; the line they write is the same.
sum() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }
(cd "$RUNNER_TEMP" && sum "$(basename "$archive")" > "${archive}.sha256")
tag="native-tools-${target}-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
notes="${RUNNER_TEMP}/folio-native-tools-notes.md"
cat > "$notes" <<EOF
Yeniden derlenen paketlenmiş belge araçları: ${name}.

Kaynak commit: ${GITHUB_SHA}
Derleme: https://github.com/${GITHUB_REPOSITORY}/actions/runs/${GITHUB_RUN_ID}

Arşiv \`native_tools/${name}/\` klasörünün tamamını içerir: ikili dosyalar,
OCR modelleri ve yeniden üretilen checksums dosyaları.

Bu paket depoya kendiliğinden girmez. İncelenip hedef işletim sisteminde
\`verify.py ${name} --smoke\` ile sınandıktan sonra elle commit edilir.
EOF
gh release create "$tag" "$archive" "${archive}.sha256" \
  --repo "$GITHUB_REPOSITORY" --target "$GITHUB_SHA" --prerelease --latest=false \
  --title "Folio native tools - ${name} - ${GITHUB_RUN_ID}" --notes-file "$notes"
url="$(gh release view "$tag" --repo "$GITHUB_REPOSITORY" --json url --jq .url)"
test -n "$url"
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  printf 'Araçlar hazır: [İncelemek için indir](%s).\n' "$url" >> "$GITHUB_STEP_SUMMARY"
fi
printf 'Native tools uploaded: %s\n' "$url"
