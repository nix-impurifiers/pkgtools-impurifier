# SPDX-License-Identifier: MIT
{ pkgs, impurifier }:
let
  client = import ./pkgtools.nix { inherit pkgs; };
  app =
    version:
    impurifier.makeNativePackage {
      name = "native-proof";
      inherit version;
      payload = pkgs.runCommand "native-proof-tree-${version}" { } ''
        mkdir -p $out/usr/bin $out/etc
        cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/usr/bin/busybox
        echo ${version} > $out/etc/native-proof-version
      '';
    };
in
pkgs.testers.runNixOSTest {
  name = "pkgtools-native-payload";
  requiredFeatures.kvm = false;
  requiredFeatures.devnet = false;
  nodes.machine = { lib, ... }: {
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    systemd.tmpfiles.rules = [
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
      "L+ /bin/du - - - - ${pkgs.coreutils}/bin/du"
      "L+ /sbin/installpkg - - - - ${client}/sbin/installpkg"
      "L+ /sbin/removepkg - - - - ${client}/sbin/removepkg"
      "L+ /sbin/upgradepkg - - - - ${client}/sbin/upgradepkg"
    ];
    environment.systemPackages = [
      client
      pkgs.xz
      pkgs.gnutar
    ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /srv/native")
    machine.succeed("${client}/sbin/installpkg --root /srv/native ${app "1"}/*.txz")
    machine.succeed("chroot /srv/native /usr/bin/busybox echo native-execution | grep native-execution")
    machine.succeed("test ! -e /srv/native/nix; grep '^1$' /srv/native/etc/native-proof-version")
    machine.succeed("ROOT=/srv/native ${client}/sbin/upgradepkg ${app "2"}/*.txz")
    machine.succeed("grep '^2$' /srv/native/etc/native-proof-version")
    machine.succeed("ROOT=/srv/native ${client}/sbin/removepkg native-proof")
    machine.succeed("test ! -e /srv/native/usr/bin/busybox; test ! -e /srv/native/etc/native-proof-version; test ! -e /srv/native/nix")
  '';
}
