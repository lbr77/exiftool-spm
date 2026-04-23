#!/usr/bin/env bash

set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

PERL_VERSION="${PERL_VERSION:-5.40.3}"
PERL_ARCHIVE="${CACHE_DIR}/perl-${PERL_VERSION}.tar.gz"
PERL_SOURCE_DIR="${BUILD_DIR}/toolchains/perl-host-src-${PERL_VERSION}"
PERL_PREFIX="${BUILD_DIR}/toolchains/perl-host-${PERL_VERSION}"
FLAGS_OUTPUT="${ROOT_DIR}/BuildSupport/perl-embed-flags.json"
JOBS="$(host_jobs)"

mkdir -p "$(dirname "${FLAGS_OUTPUT}")"

download_if_missing \
  "https://www.cpan.org/src/5.0/perl-${PERL_VERSION}.tar.gz" \
  "${PERL_ARCHIVE}"

extract_tarball "${PERL_ARCHIVE}" "${PERL_SOURCE_DIR}"

pushd "${PERL_SOURCE_DIR}" >/dev/null

if [[ ! -x "${PERL_PREFIX}/bin/perl" ]]; then
  sh Configure \
    -des \
    -Dprefix="${PERL_PREFIX}" \
    -Dman1dir=none \
    -Dman3dir=none \
    -Duseshrplib=false

  make -j"${JOBS}"
  make install
fi

CCOPTS="$("${PERL_PREFIX}/bin/perl" -MExtUtils::Embed -e ccopts)"
LDOPTS="$("${PERL_PREFIX}/bin/perl" -MExtUtils::Embed -e ldopts)"

CCOPTS="${CCOPTS}" LDOPTS="${LDOPTS}" "${PERL_PREFIX}/bin/perl" \
  -MJSON::PP \
  -MText::ParseWords=shellwords \
  -e '
    my @c_flags = grep { $_ !~ /^-mmacosx-version-min=/ } shellwords($ENV{CCOPTS});
    my @linker_flags = grep { $_ =~ /^-L/ || $_ =~ /^-l/ || $_ =~ /^-Wl,/ || $_ eq q{-framework} } shellwords($ENV{LDOPTS});
    print JSON::PP->new->canonical->pretty->encode({
      cFlags => \@c_flags,
      linkerFlags => \@linker_flags,
    });
  ' > "${FLAGS_OUTPUT}"

popd >/dev/null
