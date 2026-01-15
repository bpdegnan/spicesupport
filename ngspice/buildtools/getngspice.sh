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

SRC_URL="https://sourceforge.net/projects/ngspice/files/ng-spice-rework/${VERSION}/ngspice-${VERSION}.tar.gz"

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
  --disable-debug
  --disable-verilog
  --enable-pss
  --enable-relpath
  --disable-openmp
  --enable-readline
  --with-lapack=no
  --with-blas=no
  --disable-cluster
  --disable-compiler-warnings
  --disable-plot
)

echo "Running ./configure with:"
printf '  %s\n' "${CONFIGURE_ARGS[@]}"

./configure "${CONFIGURE_ARGS[@]}"

echo "Configure complete."
echo "Next steps:"
echo "  cd into the directory and run the appropraite compile script.  You'll have to find where ngspice binary is."


