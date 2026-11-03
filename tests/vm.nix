# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  hardwareFixture,
  bundled ? false,
}:
let
  pkgtools = import ./pkgtools.nix { inherit pkgs; };
  tool =
    version:
    pkgs.runCommand "pkgtools-tool-${version}"
      {
        pname = "pkgtools-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/pkgtools-tool
        chmod +x $out/bin/pkgtools-tool
      '';
  app =
    offline: version:
    impurifier.makePackage {
      pkg = tool version;
      inherit offline;
      configFiles."/etc/pkgtools-tool.conf" = pkgs.writeText "pkgtools-config" "version=${version}\n";
    };
  daemon =
    version:
    pkgs.runCommand "pkgtools-service-${version}"
      {
        pname = "pkgtools-service";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        cat > $out/bin/pkgtools-service <<'SCRIPT'
        #!${pkgs.busybox}/bin/sh
        echo ${version} > /var/lib/pkgtools-service/version
        exec ${pkgs.busybox}/bin/sleep infinity
        SCRIPT
        chmod +x $out/bin/pkgtools-service
      '';
  service =
    version:
    impurifier.makeOfflinePackage {
      pkg = daemon version;
      users.pkgtools-service = { };
      directories."/var/lib/pkgtools-service" = {
        owner = "pkgtools-service:pkgtools-service";
        mode = "0750";
      };
      lifecycle = {
        onInstall = ''
          /usr/bin/python3 -c "import pwd; pwd.getpwnam('pkgtools-service')"
          test -x /opt/nix/profile/bin/pkgtools-service
          echo initialized > /var/lib/pkgtools-service/initialized
        '';
        onUpgrade = "echo ${version} > /var/lib/pkgtools-service/migrated";
      };
      systemd.unit = pkgs.writeText "pkgtools-service.service" ''
        [Service]
        Type=exec
        User=pkgtools-service
        ExecStart=/opt/nix/profile/bin/pkgtools-service
        [Install]
        WantedBy=multi-user.target
      '';
    };
  hostDriver =
    version:
    impurifier.buildPackage {
      name = "impurifier-host-driver";
      inherit version;
      architecture = "x86_64";
      payload = hardwareFixture.driver version;
      postInstall = "/usr/sbin/pkgtools-impurifier-activate";
    };
  hardware = impurifier.makeOfflinePackage {
    hostDependencies = [ "impurifier-host-driver" ];
    pkg = hardwareFixture.tool;
    inherit (hardwareFixture) hardware;
  };
in
pkgs.testers.runNixOSTest {
  name = "pkgtools-impurifier";
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 2048;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgtools
      pkgs.gnutar
      pkgs.xz
      pkgs.gzip
      pkgs.bzip2
      pkgs.file
      pkgs.util-linux
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.which
      pkgs.nix
      pkgs.python3
    ];
    systemd.tmpfiles.rules = [
      "d /usr/bin 0755 root root -"
      "d /bin 0755 root root -"
      "d /sbin 0755 root root -"
      "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
      "L+ /bin/du - - - - ${pkgs.coreutils}/bin/du"
      "L+ /sbin/installpkg - - - - ${pkgtools}/sbin/installpkg"
      "L+ /sbin/removepkg - - - - ${pkgtools}/sbin/removepkg"
      "L+ /sbin/makepkg - - - - ${pkgtools}/sbin/makepkg"
      "L+ /sbin/upgradepkg - - - - ${pkgtools}/sbin/upgradepkg"
      "L+ /usr/bin/python3 - - - - ${pkgs.python3}/bin/python3"
      "L+ /usr/bin/nix-store - - - - ${
        if bundled then
          pkgs.writeShellScript "incompatible-nix-store" "echo incompatible; exit 1"
        else
          "${pkgs.nix}/bin/nix-store"
      }"
      "L+ /usr/bin/systemctl - - - - ${pkgs.systemd}/bin/systemctl"
      "L+ /usr/bin/systemd-sysusers - - - - ${pkgs.systemd}/bin/systemd-sysusers"
      "L+ /usr/bin/systemd-tmpfiles - - - - ${pkgs.systemd}/bin/systemd-tmpfiles"
    ];
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /tmp/packages")
    machine.succeed("cp ${app false "1"}/*.txz ${app true "1"}/*.txz ${app true "2"}/*.txz ${service "1"}/*.txz ${service "2"}/*.txz ${hostDriver "1"}/*.txz ${hostDriver "2"}/*.txz ${hardware}/*.txz /tmp/packages/")
    machine.succeed("cp -rL /etc/systemd/system /tmp/systemd-system; chmod -R u+w /tmp/systemd-system; rm /etc/systemd/system; mv /tmp/systemd-system /etc/systemd/system; systemctl daemon-reload")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    install = "/sbin/upgradepkg --install-new --reinstall "
    print(machine.succeed(install + "${impurifier.runtimePackage}/*.txz"))
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    with subtest("SlackBuild repacks with actual native makepkg"):
        machine.succeed("OUTPUT=/tmp/slackbuild sh ${
          impurifier.makeSlackBuild { package = app true "1"; }
        }/impurifier.SlackBuild")
        machine.succeed("tar -tJf /tmp/slackbuild/*.txz | grep '^install/doinst.sh$'")
        machine.succeed("cp /tmp/slackbuild/*.txz /tmp/packages/")
    with subtest("native script failure preserves the published profile"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute(install + "/tmp/packages/pkgtools-tool-1-*_net.txz 2>&1")
        assert "nix-profile-engine:" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("offline upgrade and Slackware .new configuration policy"):
        machine.succeed(install + "/tmp/packages/pkgtools-tool-1-*_offline.txz")
        machine.succeed("test $(/opt/nix/profile/bin/pkgtools-tool) = 1")
        machine.succeed("echo local > /etc/pkgtools-tool.conf")
        machine.succeed(install + "/tmp/packages/pkgtools-tool-1-*_net.txz")
        machine.succeed(install + "/tmp/packages/pkgtools-tool-2-*_offline.txz")
        machine.succeed("grep local /etc/pkgtools-tool.conf; grep version=2 /etc/pkgtools-tool.conf.new; test $(/opt/nix/profile/bin/pkgtools-tool) = 2")
    with subtest("native upgrades preserve service admin intent"):
        machine.succeed(install + "/tmp/packages/pkgtools-service-1-*.txz")
        machine.wait_for_unit("pkgtools-service.service")
        machine.wait_until_succeeds("grep '^1$' /var/lib/pkgtools-service/version")
        machine.succeed("grep initialized /var/lib/pkgtools-service/initialized; test $(stat -c %U /var/lib/pkgtools-service) = pkgtools-service")
        output = machine.succeed(install + "/tmp/packages/pkgtools-service-2-*.txz")
        assert output.count("activated ") == 1, output
        machine.wait_until_succeeds("grep '^2$' /var/lib/pkgtools-service/version")
        machine.succeed("grep '^2$' /var/lib/pkgtools-service/migrated")
        machine.succeed("systemctl disable --now pkgtools-service.service")
        machine.succeed(install + "/tmp/packages/pkgtools-service-1-*.txz")
        machine.fail("systemctl is-active --quiet pkgtools-service.service")
        machine.fail("systemctl is-enabled --quiet pkgtools-service.service")
        machine.succeed("systemctl enable --now pkgtools-service.service")
        machine.succeed("/sbin/removepkg pkgtools-service")
        machine.fail("systemctl is-active --quiet pkgtools-service.service")
    with subtest("cooperating driver hooks refresh immutable bindings"):
        machine.succeed(install + "/tmp/packages/impurifier-host-driver-1-*.txz /tmp/packages/hardware-tool-*.txz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^1$'")
        machine.succeed(install + "/tmp/packages/impurifier-host-driver-2-*.txz")
        machine.succeed("/opt/nix/profile/bin/hardware-tool | grep '^2$'")
        machine.succeed("/sbin/removepkg hardware-tool; /sbin/removepkg impurifier-host-driver")
    with subtest("foreign ROOT scripts cannot activate the host"):
        before = machine.succeed("readlink /opt/nix/profile").strip()
        code, output = machine.execute("/sbin/installpkg --root /tmp/foreign-root /tmp/packages/pkgtools-tool-1-*_offline.txz 2>&1")
        assert "refusing host activation for a foreign ROOT" in output, output
        assert machine.succeed("readlink /opt/nix/profile").strip() == before
    with subtest("native removal and GC preserve edited configuration"):
        machine.succeed("nix-store --gc; test $(/opt/nix/profile/bin/pkgtools-tool) = 2")
        machine.succeed("/sbin/removepkg pkgtools-tool")
        machine.fail("test -e /opt/nix/profile/bin/pkgtools-tool")
        machine.succeed("grep local /etc/pkgtools-tool.conf")
        machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc; test -d /opt/nix/profile")
  '';
}
