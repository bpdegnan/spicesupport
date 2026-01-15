#!/usr/bin/env zsh
set -e

echo "Select ngspice version to download:"
echo "  1) 44.2"
echo "  2) 45.2"
read -r "CHOICE?Enter choice [1-2]: "

case "$CHOICE" in
  1) VERSION="44.2" ;;
  2) VERSION="45.2" ;;
  *) echo "Invalid selection. Exiting."; exit 1 ;;
esac

echo "Selected ngspice version: $VERSION"

# Prefer old-releases, fall back to top-level
URL_OLD="https://sourceforge.net/projects/ngspice/files/ng-spice-rework/old-releases/${VERSION}/ngspice-${VERSION}.tar.gz/download"
URL_NEW="https://sourceforge.net/projects/ngspice/files/ng-spice-rework/${VERSION}/ngspice-${VERSION}.tar.gz/download"

echo "Checking SourceForge location..."
if curl -fsIL "$URL_OLD" >/dev/null; then
  SRC_URL="$URL_OLD"
elif curl -fsIL "$URL_NEW" >/dev/null; then
  SRC_URL="$URL_NEW"
else
  echo "Could not find ngspice-${VERSION}.tar.gz in either SourceForge location."
  echo "Tried:"
  echo "  $URL_OLD"
  echo "  $URL_NEW"
  exit 1
fi

echo "Using: $SRC_URL"


SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_DIR="${SCRIPT_DIR}/ngspice-${VERSION}"
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"

TARBALL="ngspice-${VERSION}.tar.gz"

# Download (or re-download if corrupted)
if [[ -f "$TARBALL" ]]; then
  echo "Found existing $TARBALL, verifying integrity..."
  if ! gzip -t "$TARBALL" 2>/dev/null; then
    echo "Existing tarball is corrupted, re-downloading..."
    rm -f "$TARBALL"
    wget "$SRC_URL" -O "$TARBALL"
  else
    echo "Existing tarball is valid, skipping download."
  fi
else
  echo "Downloading ngspice version ${VERSION}..."
  wget "$SRC_URL" -O "$TARBALL"
fi

# Extract cleanly
if [[ -d "ngspice-${VERSION}" ]]; then
  echo "Removing existing extracted directory..."
  rm -rf "ngspice-${VERSION}"
fi

echo "Extracting $TARBALL..."
tar xvf "$TARBALL"

cd "ngspice-${VERSION}"

# Configure flags (translated from your dh_auto_configure override)
CONFIGURE_ARGS=(
  --enable-capbypass
  --enable-xspice
  --enable-cider
  --enable-pss
  --enable-relpath
  --disable-openmp
  --enable-readline=yes
  --disable-cluster
)

echo "Running ./configure with:"
printf '  %s\n' "${CONFIGURE_ARGS[@]}"

./configure "${CONFIGURE_ARGS[@]}"

echo "Configure complete."
echo "Next steps:"
echo "  cd into the directory and run the appropraite compile script.  You'll have to find where ngspice binary is."


