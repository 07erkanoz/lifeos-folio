#!/bin/bash
# Saves what UYAP's own editor puts on the clipboard when a UDF is copied.
#
#   xvfb-run -a test/fixtures/clipboard/capture_uyap.sh document.udf out.bin [start:end]
#
# Needs UYAP Editor (/usr/share/UYAPEditor) and its Java 8. Without a range
# the whole document is selected, as Ctrl+A does.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
uyap="${UYAP_HOME:-/usr/share/UYAPEditor}"
java="${UYAP_JAVA:-/usr/lib/jvm/java-8-openjdk/jre/bin/java}"
udf="$(realpath "$1")"; out="$2"; range="${3:-all}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
# UYAP keeps its settings and backups in the home it is given: one of its
# own, kept between runs, rather than the user's.
home="${XDG_CACHE_HOME:-$HOME/.cache}/folio-uyap-capture"; mkdir -p "$home/.uki"
# Without today's date here UYAP opens with its "what's new" and version
# prompts, and a selection made under them throws.
today="$(date +%m/%d/%Y)"
cat > "$home/.uki/acilisDegerleri.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<properties><propertyGroup description="Açılış Değerleri" name="initValues"><property name="editorVersiyonDailyPrompt">$today</property><property name="editorVersiyonControl">$today</property><property name="whatsNew">2099-01-01</property></propertyGroup></properties>
XML
classpath="$(ls "$uyap"/*.jar | tr '\n' ':')"
javac --release 8 -nowarn -cp "$classpath" -d "$work" "$here/UyapCopy.java" 2>/dev/null
"$java" -Duser.home="$home" -cp "$work:$classpath" UyapCopy "$udf" "$work/ready" "$work/done" "$range" >/dev/null 2>&1 &
for _ in $(seq 1 1200); do [ -f "$work/ready" ] && break; sleep 0.1; done
target="$(xclip -selection clipboard -t TARGETS -o | grep EditorDataFlavor | head -1)"
xclip -selection clipboard -t "$target" -o > "$out"
touch "$work/done"
wait
