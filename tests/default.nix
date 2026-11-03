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
  native-vm = import ./native-vm.nix { inherit pkgs impurifier; };
  bundled-vm = import ./vm.nix {
    inherit pkgs;
    bundled = true;
    impurifier = impurifier // {
      runtimePackage = impurifier.makeRuntimePackage {
        bundledNixStore = "${import (coreSrc + "/tests/static-nix.nix") { inherit pkgs; }}/bin/nix-store";
        bundledNixNotices = [ "${pkgs.nix.src}/COPYING" ];
      };
    };
    hardwareFixture = import (coreSrc + "/tests/hardware-fixture.nix") { inherit pkgs; };
  };
  unit = impurifier.unit;
  slackpkg-vm = import ./frontend-vm.nix {
    inherit pkgs impurifier;
    frontend = "slackpkg";
  };
  slapt-get-vm = import ./frontend-vm.nix {
    inherit pkgs impurifier;
    frontend = "slapt-get";
  };
  sbopkg-vm = import ./frontend-vm.nix {
    inherit pkgs impurifier;
    frontend = "sbopkg";
  };
  netpkg-vm = import ./frontend-vm.nix { inherit pkgs impurifier; };
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
