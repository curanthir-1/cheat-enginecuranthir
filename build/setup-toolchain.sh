#!/bin/bash
# Sets up a Linux -> Windows (win64 + win32) cross toolchain for building Cheat Engine.
# Tested on Ubuntu 24.04 (FPC 3.2.2 + Lazarus 3.0 from the distribution). Run as root (or with sudo).
#
# The distribution only ships the native x86_64-linux compiler and units, so this script builds, from the
# distribution's own fpc-source package:
#   - the win64 RTL and packages (using the native ppcx64, which can target win64)
#   - an i386 cross compiler (ppcross386)
#   - the win32 RTL and packages
# and installs them where the stock /etc/fpc.cfg looks for them.
set -euo pipefail

FPCVER=3.2.2
FPCLIB=/usr/lib/x86_64-linux-gnu/fpc/$FPCVER
WORK=${WORK:-/tmp/ce-fpc-cross}

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends fpc fpc-source lcl lcl-utils lazarus-src make zip

if [ -f "$FPCLIB/units/x86_64-win64/rtl/system.ppu" ] && [ -f "$FPCLIB/units/i386-win32/rtl/system.ppu" ] && [ -x "$FPCLIB/ppcross386" ]; then
  echo "Cross toolchain already installed"
  exit 0
fi

rm -rf "$WORK"
mkdir -p "$WORK"
cp -r /usr/share/fpcsrc/$FPCVER "$WORK/src"
cd "$WORK/src"
export FPCDIR="$WORK/src"

# The distribution strips the generated makefiles and a few generated files from fpc-source. Recreate them.
printf 'CPUNAMES=int64p math set setjump setjumph x86_64 cpuh\nCPUINCNAMES=$(addsuffix .inc,$(CPUNAMES))\n' > rtl/x86_64/makefile.cpu
printf 'CPUNAMES=fastmove i386 int64p math set setjump setjumph cpuh\nCPUINCNAMES=$(addsuffix .inc,$(CPUNAMES))\n' > rtl/i386/makefile.cpu

install_units() { # $1 = target (e.g. x86_64-win64)
  local dest="$FPCLIB/units/$1"
  mkdir -p "$dest/rtl"
  cp rtl/units/$1/* "$dest/rtl/"
  for p in packages/*/units/$1; do
    local name
    name=$(echo "$p" | cut -d/ -f2)
    mkdir -p "$dest/$name"
    cp "$p"/* "$dest/$name/"
  done
}

build_target() { # $1 = cpu, $2 = os, $3 = compiler
  local cpu=$1 os=$2 fpc=$3
  (cd rtl/$os && fpcmake -T$cpu-$os -w Makefile.fpc)
  make -C rtl/$os all OS_TARGET=$os CPU_TARGET=$cpu FPC=$fpc
  (cd packages && fpcmake -T$cpu-$os -w Makefile.fpc)
  # The last package (the text mode IDE) needs compiler internals that are not part of fpc-source. It is not needed.
  make -C packages all OS_TARGET=$os CPU_TARGET=$cpu FPC=$fpc || true
  test -f packages/fcl-base/units/$cpu-$os/custapp.ppu
  test -f packages/fcl-xml/units/$cpu-$os/dom.ppu
  install_units $cpu-$os
}

echo "=== win64 RTL and packages ==="
(cd packages/fpmkunit && fpcmake -Tx86_64-linux -w Makefile.fpc)
build_target x86_64 win64 /usr/bin/ppcx64

echo "=== i386 cross compiler ==="
(
  cd compiler
  fpc -FE"$WORK" utils/msg2inc.pp
  mkdir -p msg
  cp "$FPCLIB/msg/errore.msg" msg/
  "$WORK/msg2inc" msg/errore.msg msg msg
  touch msgtxt.inc msgidx.inc
  fpcmake -Tx86_64-linux -w Makefile.fpc
  # builds ./ppc386 (the 'utils' sub target fails afterwards because its makefile is not shipped; that is fine)
  make PPC_TARGET=i386 FPC=/usr/bin/ppcx64 all || true
  test -x ppc386
  cp ppc386 "$FPCLIB/ppcross386"
  ln -sf "$FPCLIB/ppcross386" /usr/bin/ppcross386
)

echo "=== win32 RTL and packages ==="
build_target i386 win32 /usr/bin/ppcross386

echo "Cross toolchain installed"
