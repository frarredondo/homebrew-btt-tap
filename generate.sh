#!/usr/bin/env bash
#
# generate.sh — add a specific BetterTouchTool version to this Homebrew tap as a cask.
#
# It looks the requested version up in the LIVE folivora.ai release index (constructed
# URLs are not trusted — some 404), verifies the file exists with a ranged request,
# downloads it once to compute a real sha256, and writes Casks/btt@<short>.rb.
#
# Usage:
#   ./generate.sh <version>     e.g. ./generate.sh 4.363   (or the full 4.363-43630)
#   ./generate.sh --latest      newest version in the upstream index
#   ./generate.sh --list        print the parsed {version, date, build, token} table (no writes)
#
# Flags:
#   --force        regenerate even if an up-to-date cask already exists
#   -h, --help     show this help

set -euo pipefail

RELEASES_URL="https://folivora.ai/releases/"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASKS_DIR="$SCRIPT_DIR/Casks"
FORCE=0
TMP_ZIP=""
SEP=$'\037'   # internal field separator (ASCII Unit Separator): non-whitespace, so
              # `read` preserves empty fields (e.g. the blank build of legacy releases)

die()  { printf 'error: %s\n' "$*" >&2; exit 1; }
info() { printf '%s\n' "$*" >&2; }

cleanup() {
  local rc=$?
  [[ -n "$TMP_ZIP" && -f "$TMP_ZIP" ]] && rm -f "$TMP_ZIP"
  exit "$rc"   # preserve the real exit status (a trap's last command would otherwise set it)
}
trap cleanup EXIT

usage() {
  cat >&2 <<'EOF'
generate.sh — add a specific BetterTouchTool version to this tap as a cask.

Usage:
  ./generate.sh <version>     e.g. ./generate.sh 4.363   (or the full 4.363-43630)
  ./generate.sh --latest      newest version in the upstream index
  ./generate.sh --list        print the parsed {version, date, build, token} table (no writes)

Flags:
  --force        regenerate even if an up-to-date cask already exists
  -h, --help     show this help
EOF
}

# Fetch the release index and emit TSV records: short<TAB>build<TAB>filename<TAB>date
# `build` is empty for legacy (no-build) filenames; `date` is the upstream release
# (last-modified) date as YYYY-MM-DD, pulled from the autoindex "indexcollastmod"
# column. awk does the HTML scrape (portable: BSD sed won't emit \t). Junk/variant
# filenames are skipped:
#   - URL-encoded names and "... copy.zip"     (contain % or "copy")
#   - underscore variants (btt_setapp_..., btt_2.428_recovery_mojave.zip)
#   - letter-suffixed betas (btt5.662b-..., btt3.211b.zip) fail the numeric regexes
parse_index() {
  curl -fsSL --max-time 60 "$RELEASES_URL" \
    | awk '
        /href="btt[^"]+\.zip"/ {
          if (match($0, /href="btt[^"]+\.zip"/)) {
            fn = substr($0, RSTART + 6, RLENGTH - 7)   # strip href=" and trailing "
            d = ""
            if (match($0, /indexcollastmod">[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]/))
              d = substr($0, RSTART + 17, 10)          # the YYYY-MM-DD after the tag
            print fn "\t" d
          }
        }' \
    | while IFS=$'\t' read -r fn reldate; do
        case "$fn" in
          *%*|*_*|*'$'*|*copy*) continue ;;
        esac
        if [[ "$fn" =~ ^btt([0-9]+\.[0-9]+)-([0-9]+)\.zip$ ]]; then
          printf "%s${SEP}%s${SEP}%s${SEP}%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}" "$fn" "$reldate"
        elif [[ "$fn" =~ ^btt([0-9]+\.[0-9]+)\.zip$ ]]; then
          printf "%s${SEP}%s${SEP}%s${SEP}%s\n" "${BASH_REMATCH[1]}" "" "$fn" "$reldate"
        fi
      done
}

# Concrete download URL for a (short, build) pair.
build_url() {
  local short="$1" build="$2"
  if [[ -n "$build" ]]; then
    printf '%sbtt%s-%s.zip' "$RELEASES_URL" "$short" "$build"
  else
    printf '%sbtt%s.zip' "$RELEASES_URL" "$short"
  fi
}

# Read the app's real minimum macOS (LSMinimumSystemVersion, e.g. "10.15") from a
# downloaded zip. Prints the raw version string, or nothing if unavailable.
min_macos() {
  local zip="$1" plist
  plist="$(mktemp "${TMPDIR:-/tmp}/btt-plist.XXXXXX")"
  if unzip -p "$zip" 'BetterTouchTool.app/Contents/Info.plist' > "$plist" 2>/dev/null; then
    /usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plist" 2>/dev/null || true
  fi
  rm -f "$plist"
}

# Map an LSMinimumSystemVersion (e.g. "10.15", "11.0", "13.3") to a Homebrew macOS
# symbol. Prints nothing for versions it doesn't know (caller then omits depends_on).
macos_symbol() {
  local v="$1" major minor
  major="${v%%.*}"
  minor="${v#*.}"; minor="${minor%%.*}"
  case "$major" in
    10) case "$minor" in
          11) echo "el_capitan" ;; 12) echo "sierra" ;; 13) echo "high_sierra" ;;
          14) echo "mojave" ;;     15) echo "catalina" ;;
        esac ;;
    11) echo "big_sur" ;;  12) echo "monterey" ;; 13) echo "ventura" ;;
    14) echo "sonoma" ;;   15) echo "sequoia" ;;  26) echo "tahoe" ;;
  esac
}

# Cheap existence check via a 1-byte ranged request (expect HTTP 206, or 200).
remote_exists() {
  local code
  code="$(curl -fsS -o /dev/null -w '%{http_code}' --max-time 30 -r 0-0 "$1" 2>/dev/null || echo 000)"
  [[ "$code" == "206" || "$code" == "200" ]]
}

# Download the zip once into $TMP_ZIP (a parent-scope global, so callers can both
# hash it and read its Info.plist). Must NOT run inside $(...) or the assignment
# would be lost to a subshell. Guards against HTML error pages saved as ".zip".
download() {
  local url="$1" size
  TMP_ZIP="$(mktemp "${TMPDIR:-/tmp}/btt-cask.XXXXXX")"
  info "downloading $url ..."
  curl -fL --retry 3 --retry-delay 2 --max-time 1800 -o "$TMP_ZIP" "$url" \
    || die "download failed: $url"
  size="$(stat -f%z "$TMP_ZIP" 2>/dev/null || stat -c%s "$TMP_ZIP" 2>/dev/null || echo 0)"
  [[ "$size" -gt 1000000 ]] || die "downloaded file is only ${size} bytes — not a real zip? $url"
}

# Render Casks/<token>.rb. has_build=1 → CSV version + interpolated build URL.
render_cask() {
  local token="$1" vcsv="$2" has_build="$3" sha="$4" depends_line="$5"
  local out="$CASKS_DIR/$token.rb" url_line mid
  if [[ "$has_build" == "1" ]]; then
    url_line='  url "https://folivora.ai/releases/btt#{version.csv.first}-#{version.csv.second}.zip"'
  else
    url_line='  url "https://folivora.ai/releases/btt#{version}.zip"'
  fi
  mid='  auto_updates true
  conflicts_with cask: "bettertouchtool"'
  [[ -n "$depends_line" ]] && mid="$mid
$depends_line"
  mkdir -p "$CASKS_DIR"
  cat > "$out" <<EOF
cask "$token" do
  version "$vcsv"
  sha256 "$sha"

$url_line
  name "BetterTouchTool"
  desc "Tool to customise input devices and automate computer systems"
  homepage "https://folivora.ai/"

  livecheck do
    skip "Pinned historical version"
  end

$mid

  app "BetterTouchTool.app"

  uninstall quit: "com.hegenberg.BetterTouchTool"

  zap trash: [
    "~/Library/Application Support/BetterTouchTool",
    "~/Library/Caches/com.hegenberg.BetterTouchTool",
    "~/Library/Preferences/com.hegenberg.BetterTouchTool.plist",
  ]
end
EOF
  info "wrote ${out#"$SCRIPT_DIR"/}"
}

# A published build is immutable, so an existing cask is skipped unless --force.
should_generate() {
  [[ "$FORCE" == "1" ]] && return 0
  [[ -f "$CASKS_DIR/$1.rb" ]] && return 1
  return 0
}

gen_one() {
  local short="$1" build="$2" token vcsv url sha has_build minos sym depends_line=""
  token="btt@$short"
  if ! should_generate "$token"; then
    info "skip: $token already exists (use --force to regenerate)"
    return 0
  fi
  if [[ -n "$build" ]]; then vcsv="$short,$build"; has_build=1; else vcsv="$short"; has_build=0; fi
  url="$(build_url "$short" "$build")"
  remote_exists "$url" || die "upstream file not reachable (404?): $url"
  download "$url"                              # sets $TMP_ZIP in this (parent) scope
  sha="$(shasum -a 256 "$TMP_ZIP" | awk '{print $1}')"
  minos="$(min_macos "$TMP_ZIP")"              # real minimum macOS from the app bundle
  sym="$(macos_symbol "$minos")"
  # A bare symbol means ">= that version" (the string ">= :sym" form is deprecated).
  [[ -n "$sym" ]] && depends_line="  depends_on macos: :$sym"
  render_cask "$token" "$vcsv" "$has_build" "$sha" "$depends_line"
  info "done: $token  (sha256 $sha; min macOS ${minos:-unknown})"
}

main() {
  local mode="" target="" index match s b fn reldate
  [[ $# -eq 0 ]] && { usage; exit 2; }
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --latest) mode="latest" ;;
      --list)   mode="list" ;;
      --force)  FORCE=1 ;;
      -h|--help) usage; exit 0 ;;
      --*) die "unknown flag: $1 (see --help)" ;;
      *) mode="one"; target="$1" ;;
    esac
    shift
  done
  [[ -z "$mode" ]] && { usage; exit 2; }

  index="$(parse_index)" || die "failed to fetch release index from $RELEASES_URL"
  [[ -n "$index" ]] || die "release index is empty — network issue or upstream layout changed"

  case "$mode" in
    list)
      printf '%-10s %-12s %-12s %s\n' "VERSION" "DATE" "BUILD" "TOKEN"
      printf '%s\n' "$index" | sort -t"$SEP" -k1,1V -k2,2V | while IFS="$SEP" read -r s b fn reldate; do
        printf '%-10s %-12s %-12s %s\n' "$s" "${reldate:-—}" "${b:-—}" "btt@$s"
      done
      ;;
    latest)
      match="$(printf '%s\n' "$index" | sort -t"$SEP" -k1,1V -k2,2V | tail -1)"
      IFS="$SEP" read -r s b fn reldate <<< "$match"
      info "latest upstream version: $s${b:+-$b}${reldate:+  ($reldate)}"
      gen_one "$s" "$b"
      ;;
    one)
      match="$(printf '%s\n' "$index" | awk -F"$SEP" -v v="$target" '$1==v || ($1"-"$2)==v {print; exit}')"
      [[ -n "$match" ]] || die "version '$target' not found upstream (try: ./generate.sh --list)"
      IFS="$SEP" read -r s b fn reldate <<< "$match"
      gen_one "$s" "$b"
      ;;
  esac
}

main "$@"
