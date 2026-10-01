#!/bin/bash
# Writes where UYAP's own editor draws every line of a UDF, and its pages.
#
#   xvfb-run -a test/fixtures/pages/capture_pages.sh document.udf out.tsv [probe]
#
# Needs UYAP Editor (/usr/share/UYAPEditor) and its Java 8.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
uyap="${UYAP_HOME:-/usr/share/UYAPEditor}"
java="${UYAP_JAVA:-/usr/lib/jvm/java-8-openjdk/jre/bin/java}"
udf="$(realpath "$1")"; out="$(realpath -m "$2")"; mode="${3:-lines}"
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
home="${XDG_CACHE_HOME:-$HOME/.cache}/folio-uyap-capture"; mkdir -p "$home/.uki"
today="$(date +%m/%d/%Y)"
cat > "$home/.uki/acilisDegerleri.xml" <<XML
<?xml version="1.0" encoding="UTF-8"?>
<properties><propertyGroup description="Açılış Değerleri" name="initValues"><property name="editorVersiyonDailyPrompt">$today</property><property name="editorVersiyonControl">$today</property><property name="whatsNew">2099-01-01</property></propertyGroup></properties>
XML
classpath="$(ls "$uyap"/*.jar | tr '\n' ':')"
javac --release 8 -nowarn -cp "$classpath" -d "$work" "$here/UyapPages.java" 2>/dev/null
"$java" -Duser.home="$home" -cp "$work:$classpath" UyapPages "$udf" "$out" "$mode" >/dev/null 2>&1
