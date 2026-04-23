#!/usr/bin/env bash

set -euo pipefail

if [[ "${1:-}" != "--syms" || $# -lt 2 ]]; then
  echo "readelf-compat only supports: readelf --syms <object>" >&2
  exit 2
fi

OBJECT_PATH="${@: -1}"
LLVM_OBJDUMP="${LLVM_OBJDUMP:-$(xcrun -f llvm-objdump 2>/dev/null || command -v objdump)}"

"${LLVM_OBJDUMP}" --syms "${OBJECT_PATH}" | perl -ne '
  BEGIN {
    print "Symbol table '\''.symtab'\'' contains synthetic entries:\n";
    print "   Num:    Value          Size Type    Bind   Vis      Ndx Name\n";
    $index = 0;
  }

  next if /^\s*$/;
  next if /file format/;
  next if /SYMBOL TABLE/;

  @fields = grep { length($_) } split /\s+/, $_;
  next if @fields < 4;

  $name = $fields[-1];
  $size_hex = $fields[-2];
  next unless $size_hex =~ /\A[0-9A-Fa-f]+\z/;

  printf "%6d: %016x %5d OBJECT  GLOBAL DEFAULT  COM %s\n",
    ++$index,
    0,
    hex($size_hex),
    $name;
'
