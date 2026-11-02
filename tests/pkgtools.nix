# SPDX-License-Identifier: MIT
{ pkgs }:
pkgs.stdenvNoCC.mkDerivation {
  pname = "slackware-pkgtools";
  version = "15.0-44";
  src = pkgs.fetchurl {
    url = "https://slackware.osuosl.org/slackware64/patches/packages/pkgtools-15.0-noarch-44_slack15.0.txz";
    hash = "sha256-5RYTePc7ahOO/yYYcBeMu6MfBsf5nTa55LYq2yiGA4o=";
  };
  unpackPhase = "mkdir source; tar -xJf $src -C source";
  installPhase = ''
    mkdir -p $out/sbin
    cp source/sbin/{installpkg,removepkg,upgradepkg,makepkg} $out/sbin/
    patchShebangs $out/sbin
  '';
  dontFixup = true;
}
