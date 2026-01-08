#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ZIP=${1:?
"Usage: $0 MyApp-<ver>.zip"}
FEED_URL=${2:-"https://raw.githubusercontent.com/Dimillian/CodexSkillManager/main/appcast.xml"}
PRIVATE_KEY_FILE=${SPARKLE_PRIVATE_KEY_FILE:-}
if [[ -z "$PRIVATE_KEY_FILE" ]]; then
  echo "Set SPARKLE_PRIVATE_KEY_FILE to your ed25519 private key (Sparkle)." >&2
  exit 1
fi
if [[ ! -f "$ZIP" ]]; then
  echo "Zip not found: $ZIP" >&2
  exit 1
fi

ZIP_DIR=$(cd "$(dirname "$ZIP")" && pwd)
ZIP_NAME=$(basename "$ZIP")
ZIP_BASE="${ZIP_NAME%.zip}"
VERSION=${SPARKLE_RELEASE_VERSION:-}
if [[ -z "$VERSION" ]]; then
  if [[ "$ZIP_NAME" =~ ^[^-]+-([0-9]+(\.[0-9]+){1,2}([-.][^.]*)?)\.zip$ ]]; then
    VERSION="${BASH_REMATCH[1]}"
  else
    echo "Could not infer version from $ZIP_NAME; set SPARKLE_RELEASE_VERSION." >&2
    exit 1
  fi
fi

NOTES_HTML="${ZIP_DIR}/${ZIP_BASE}.html"
KEEP_NOTES=${KEEP_SPARKLE_NOTES:-0}
if [[ -x "$ROOT/Scripts/changelog-to-html.sh" ]]; then
  "$ROOT/Scripts/changelog-to-html.sh" "$VERSION" >"$NOTES_HTML"
elif [[ -n "${SPARKLE_RELEASE_NOTES_FILE:-}" && -f "${SPARKLE_RELEASE_NOTES_FILE:-}" ]]; then
  python3 - <<'PY' "${SPARKLE_RELEASE_NOTES_FILE}" "$NOTES_HTML" "$ZIP_BASE"
import sys
from pathlib import Path

notes_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
title = sys.argv[3]
lines = [line.strip() for line in notes_path.read_text().splitlines()]
items = [line[2:].strip() for line in lines if line.startswith(("- ", "* "))]
paras = [line for line in lines if line and not line.startswith(("- ", "* "))]

body = []
if paras:
  for p in paras:
    body.append(f"<p>{p}</p>")
if items:
  body.append("<ul>")
  for item in items:
    body.append(f"<li>{item}</li>")
  body.append("</ul>")

html = "\n".join([
  "<!doctype html>",
  "<html lang=\"en\">",
  "<meta charset=\"utf-8\">",
  f"<title>{title}</title>",
  "<body>",
  f"<h2>{title}</h2>",
  *body,
  "</body>",
  "</html>",
])
out_path.write_text(html)
PY
elif [[ -f "/tmp/codexskillmanager-release-notes-${VERSION}.md" ]]; then
  python3 - <<'PY' "/tmp/codexskillmanager-release-notes-${VERSION}.md" "$NOTES_HTML" "$ZIP_BASE"
import sys
from pathlib import Path

notes_path = Path(sys.argv[1])
out_path = Path(sys.argv[2])
title = sys.argv[3]
lines = [line.strip() for line in notes_path.read_text().splitlines()]
items = [line[2:].strip() for line in lines if line.startswith(("- ", "* "))]
paras = [line for line in lines if line and not line.startswith(("- ", "* "))]

body = []
if paras:
  for p in paras:
    body.append(f"<p>{p}</p>")
if items:
  body.append("<ul>")
  for item in items:
    body.append(f"<li>{item}</li>")
  body.append("</ul>")

html = "\n".join([
  "<!doctype html>",
  "<html lang=\"en\">",
  "<meta charset=\"utf-8\">",
  f"<title>{title}</title>",
  "<body>",
  f"<h2>{title}</h2>",
  *body,
  "</body>",
  "</html>",
])
out_path.write_text(html)
PY
else
  cat >"$NOTES_HTML" <<HTML
<!doctype html>
<html lang="en">
<meta charset="utf-8">
<title>${ZIP_BASE}</title>
<body>
<h2>${ZIP_BASE}</h2>
<p>Release notes not provided.</p>
</body>
</html>
HTML
fi
cleanup() {
  if [[ -n "${WORK_DIR:-}" ]]; then
    rm -rf "$WORK_DIR"
  fi
  if [[ "$KEEP_NOTES" != "1" ]]; then
    rm -f "$NOTES_HTML"
  fi
}
trap cleanup EXIT

DOWNLOAD_URL_PREFIX=${SPARKLE_DOWNLOAD_URL_PREFIX:-"https://github.com/Dimillian/CodexSkillManager/releases/download/v${VERSION}/"}

GEN_APPCAST=$(command -v generate_appcast || true)
SIGN_UPDATE=$(command -v sign_update || true)
TEMP_DIR=""
cleanup_tools() {
  if [[ -n "$TEMP_DIR" ]]; then
    rm -rf "$TEMP_DIR"
  fi
}
trap cleanup_tools EXIT

if [[ -z "$GEN_APPCAST" ]]; then
  TEMP_DIR=$(mktemp -d /tmp/sparkle-appcast.XXXXXX)
  curl -sL -o "$TEMP_DIR/sparkle.tar.xz" \
    "https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz"
  tar -xf "$TEMP_DIR/sparkle.tar.xz" -C "$TEMP_DIR" ./bin/generate_appcast
  GEN_APPCAST="$TEMP_DIR/bin/generate_appcast"
fi
if [[ -z "$SIGN_UPDATE" ]]; then
  if [[ -z "$TEMP_DIR" ]]; then
    TEMP_DIR=$(mktemp -d /tmp/sparkle-appcast.XXXXXX)
    curl -sL -o "$TEMP_DIR/sparkle.tar.xz" \
      "https://github.com/sparkle-project/Sparkle/releases/download/2.8.1/Sparkle-2.8.1.tar.xz"
  fi
  tar -xf "$TEMP_DIR/sparkle.tar.xz" -C "$TEMP_DIR" ./bin/sign_update
  SIGN_UPDATE="$TEMP_DIR/bin/sign_update"
fi

WORK_DIR=$(mktemp -d /tmp/appcast.XXXXXX)

cp "$ROOT/appcast.xml" "$WORK_DIR/appcast.xml"
cp "$ZIP" "$WORK_DIR/$ZIP_NAME"
cp "$NOTES_HTML" "$WORK_DIR/$ZIP_BASE.html"

pushd "$WORK_DIR" >/dev/null
"$GEN_APPCAST" \
  --ed-key-file "$PRIVATE_KEY_FILE" \
  --download-url-prefix "$DOWNLOAD_URL_PREFIX" \
  --embed-release-notes \
  --link "$FEED_URL" \
  "$WORK_DIR"
popd >/dev/null

cp "$WORK_DIR/appcast.xml" "$ROOT/appcast.xml"

# Ensure the enclosure is signed (sparkle:edSignature) for the current version.
SIG_OUTPUT=$("$SIGN_UPDATE" --ed-key-file "$PRIVATE_KEY_FILE" "$ZIP")
SIG=$(echo "$SIG_OUTPUT" | sed -n 's/.*sparkle:edSignature="\\([^"]*\\)".*/\\1/p')
LEN=$(echo "$SIG_OUTPUT" | sed -n 's/.*length="\\([0-9]*\\)".*/\\1/p')
if [[ -n "$SIG" && -n "$LEN" ]]; then
  SPARKLE_VERSION="$VERSION" SPARKLE_EDSIG="$SIG" SPARKLE_LEN="$LEN" perl -0pi -e '
    my $ver = $ENV{SPARKLE_VERSION};
    my $sig = $ENV{SPARKLE_EDSIG};
    my $len = $ENV{SPARKLE_LEN};
    s{(<item>.*?<sparkle:shortVersionString>\Q$ver\E</sparkle:shortVersionString>.*?<enclosure\s+)([^>]+?)(/?>)}{
      my ($pre,$attrs,$end)=($1,$2,$3);
      $attrs =~ s/\blength=\"[^\"]*\"/length=\"$len\"/;
      if ($attrs !~ /sparkle:edSignature=/) { $attrs .= " sparkle:edSignature=\"$sig\""; }
      "$pre$attrs$end";
    }esg;
  ' "$ROOT/appcast.xml"
fi

# Ensure the appcast item title matches the short version string.
perl -0pi -e '
  if (m{<item>.*?</item>}s) {
    my $item = $&;
    if ($item =~ m{<sparkle:shortVersionString>([^<]+)</sparkle:shortVersionString>}s) {
      my $ver = $1;
      $item =~ s{<title>.*?</title>}{<title>$ver</title>}s;
      s{<item>.*?</item>}{$item}s;
    }
  }
' "$ROOT/appcast.xml"

echo "Appcast generated (appcast.xml). Upload alongside $ZIP at $FEED_URL"
