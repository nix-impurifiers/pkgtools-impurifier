# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  coreSrc,
}:
let
  package = impurifier.makeOfflinePackage { pkg = pkgs.hello; };
  closure = pkgs.closureInfo { rootPaths = [ package ]; };
in
{
  unit = impurifier.unit;
  emitter =
    pkgs.runCommand "pkgtools-contract"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.xz
        ];
      }
      ''
        test "$(wc -l < ${closure}/store-paths)" = 1
        tar -tJf ${package}/*.txz | grep '^install/douninst.sh$'
        tar -tJf ${package}/*.txz | grep '^usr/share/nix-profile.d/hello.json$'
        touch $out
      '';
  vm = import ./vm.nix {
    inherit pkgs impurifier;
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
}
