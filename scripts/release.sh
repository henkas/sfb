#!/usr/bin/env bash

set -euo pipefail

VERSION="${1:-}"
shift || true

SOURCE_REPO="${GITHUB_REPOSITORY:-henkas/sfb}"
FORMULA_PATH="Formula/sfb.rb"

usage() {
  cat <<USAGE
Usage: $0 <vX.Y.Z> [--source-repo owner/repo] [--formula-path path]
USAGE
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --source-repo)
      shift
      SOURCE_REPO="${1:-}"
      ;;
    --formula-path)
      shift
      FORMULA_PATH="${1:-}"
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift || true
done

if [ -z "$VERSION" ]; then
  usage >&2
  exit 2
fi

if [[ ! "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "Version must match vX.Y.Z" >&2
  exit 2
fi

if [ -z "$SOURCE_REPO" ]; then
  echo "--source-repo cannot be empty" >&2
  exit 2
fi

if [ -z "$FORMULA_PATH" ]; then
  echo "--formula-path cannot be empty" >&2
  exit 2
fi

WORKDIR="$(mktemp -d)"
trap 'rm -rf "$WORKDIR"' EXIT

SOURCE_URL="https://github.com/${SOURCE_REPO}/archive/refs/tags/${VERSION}.tar.gz"
ARCHIVE="$WORKDIR/sfb-${VERSION}.tar.gz"

curl --fail --location --silent --show-error "$SOURCE_URL" --output "$ARCHIVE"
SHA256="$(shasum -a 256 "$ARCHIVE" | awk '{print $1}')"

mkdir -p "$(dirname "$FORMULA_PATH")"
cat > "$FORMULA_PATH" <<FORMULA
class Sfb < Formula
  desc "Smart File Browser for macOS terminal with safe guardrails"
  homepage "https://github.com/${SOURCE_REPO}"
  url "${SOURCE_URL}"
  sha256 "${SHA256}"
  license "MIT"

  depends_on "fzf"
  depends_on "trash"

  def install
    bin.install "bin/sfb"
    lib.install Dir["lib/*.sh"]
    bash_completion.install "completions/sfb.bash" => "sfb"
    zsh_completion.install "completions/_sfb"
    prefix.install "README.md"
  end

  test do
    assert_match "Smart File Browser", shell_output("#{bin}/sfb help")
  end
end
FORMULA

echo "Updated formula: $FORMULA_PATH"
echo "Version: $VERSION"
echo "SHA256: $SHA256"
echo "Source URL: $SOURCE_URL"
