# SPDX-License-Identifier: MIT
{
  pkgs,
  impurifier,
  frontend ? "netpkg",
}:
let
  pkgtools = import ./pkgtools.nix { inherit pkgs; };
  sdk = import ./frontend-sdk.nix { inherit pkgs; };
  slackpkgPolicy = pkgs.writeText "slackpkg-fixture-policy" ''
    SLACKKEY="VM Fixture <fixture@localhost>"
    PRIORITY=( slackware64 )
    DIALOG=off
    BATCH=on
    DEFAULT_ANSWER=y
    POSTINST=off
    SPINNING=off
  '';
  tool =
    version:
    pkgs.runCommand "frontend-tool-${version}"
      {
        pname = "frontend-tool";
        inherit version;
      }
      ''
        mkdir -p $out/bin
        printf '#!${pkgs.busybox}/bin/sh\necho ${version}\n' > $out/bin/frontend-tool
        chmod +x $out/bin/frontend-tool
      '';
  repo = version: impurifier.makeRepository { packages = [ (app version) ]; };
  recipe = version: impurifier.makeSlackBuild { package = app version; };
  app =
    version:
    impurifier.makeOfflinePackage {
      pkg = tool version;
      configFiles."/etc/frontend-tool.conf" = pkgs.writeText "frontend-tool.conf" "version=${version}\n";
    };
in
pkgs.testers.runNixOSTest {
  name = "pkgtools-impurifier-${frontend}";
  globalTimeout = 180;
  requiredFeatures = {
    kvm = false;
    devnet = false;
  };
  nodes.machine = { lib, ... }: {
    virtualisation.memorySize = 1024;
    virtualisation.useNixStoreImage = true;
    virtualisation.writableStore = true;
    virtualisation.qemu.package = lib.mkForce pkgs.qemu;
    virtualisation.qemu.forceAccel = false;
    environment.systemPackages = [
      pkgtools
      sdk.netpkg
      sdk.slapt-get
      pkgs.bash
      pkgs.coreutils
      pkgs.gnutar
      pkgs.xz
      pkgs.gzip
      pkgs.bzip2
      pkgs.file
      pkgs.util-linux
      pkgs.gnused
      pkgs.gnugrep
      pkgs.findutils
      pkgs.gawk
      pkgs.which
      pkgs.nix
      pkgs.python3
      pkgs.wget
      pkgs.gnupg
      pkgs.dialog
      pkgs.gettext
      pkgs.diffutils
      pkgs.rsync
      pkgs.ncurses
    ];
    environment.etc."slapt-getrc".text = ''
      WORKINGDIR=/var/cache/slapt-get
      SOURCE=file:///packages/repo/:OFFICIAL
    '';
    environment.etc."shell-colors".text = "";
    environment.etc."zenwalk-version".text = "Impurifier VM fixture\n";
    environment.etc."slackware-version".text = "Slackware 15.0\n";
    environment.etc."netpkg.conf".text = ''
      Netpkg_dir=/var/netpkg
      Remotes_dir=/etc/netpkg.d
      Local_repository=/packages
      Package_logs=/var/log/packages
      Handle_dependencies=no
      Keep_packages=yes
      Protected_files=
      Logfile=/var/log/netpkg.log
    '';
    environment.etc."sbopkg/sbopkg.conf".source = "${sdk.sbopkg}/src/etc/sbopkg/sbopkg.conf";
    environment.etc."sbopkg/repos.d/50-local.repo".source =
      "${sdk.sbopkg}/src/etc/sbopkg/repos.d/50-local.repo";
    environment.etc."sbopkg/renames.d/50-default.renames".source =
      "${sdk.sbopkg}/src/etc/sbopkg/renames.d/50-default.renames";
    environment.etc."sbopkg/blacklist".source = "${sdk.sbopkg}/src/etc/sbopkg/blacklist";
    nix.settings.substituters = lib.mkForce [ ];
  };
  testScript = ''
    start_all()
    machine.wait_for_unit("multi-user.target")
    machine.succeed("mkdir -p /usr/bin /usr/sbin /sbin /bin /etc/netpkg.d /var/netpkg /packages/v1 /packages/v2 /usr/libexec")
    machine.succeed("for program in /run/current-system/sw/bin/* /run/current-system/sw/sbin/*; do test -e $program || continue; name=$(basename $program); test -e /usr/bin/$name || ln -s $program /usr/bin/$name; done; for name in bash du; do test -e /bin/$name || ln -s /usr/bin/$name /bin/$name; done; for name in installpkg removepkg upgradepkg makepkg; do ln -s ${pkgtools}/sbin/$name /sbin/$name; done")
    machine.succeed("ln -sf ${pkgs.python3}/bin/python3 /usr/bin/python3; ln -sf ${pkgs.nix}/bin/nix-store /usr/bin/nix-store; ln -s ${sdk.netpkg}/bin/vfilter /usr/libexec/vfilter")
    machine.succeed("cp ${app "1"}/*.txz /packages/v1/; cp ${app "2"}/*.txz /packages/v2/; /sbin/installpkg ${impurifier.runtimePackage}/*.txz")
    machine.succeed("cp ${sdk.sbopkg}/src/usr/sbin/sbopkg /usr/sbin/sbopkg; chmod +x /usr/sbin/sbopkg; mkdir -p /packages/recipes/v1/local/local/category/frontend-tool /packages/recipes/v2/local/local/category/frontend-tool; cp -r ${recipe "1"}/. /packages/recipes/v1/local/local/category/frontend-tool/; cp -r ${recipe "2"}/. /packages/recipes/v2/local/local/category/frontend-tool/; chmod -R u+w /packages/recipes")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "1"))}")
    machine.succeed("cp -r ${repo "1"} /packages/repo1; cp -r ${repo "2"} /packages/repo2; chmod -R u+w /packages/repo1 /packages/repo2; touch -d @2 /packages/repo1/PACKAGES.TXT /packages/repo1/CHECKSUMS.md5; touch -d @3 /packages/repo2/PACKAGES.TXT /packages/repo2/CHECKSUMS.md5; ln -s /packages/repo1 /packages/repo; mkdir -p /etc/slapt-get /root/.gnupg; chmod 700 /root/.gnupg; gpg --batch --pinentry-mode loopback --passphrase-fd 0 --quick-generate-key 'VM Fixture <fixture@localhost>' ed25519 sign 0 </dev/null; gpg --export > /packages/key.gpg; gpg --homedir /etc/slapt-get --import /packages/key.gpg; for dir in /packages/repo1 /packages/repo2; do $dir/sign-repository; done; find /packages/repo1 -type f -exec touch -d @10 {} +; find /packages/repo2 -type f -exec touch -d @20 {} +")
    if "${frontend}" == "slackpkg":
        machine.succeed("/sbin/installpkg ${sdk.slackpkg}; echo file:///packages/repo/ > /etc/slackpkg/mirrors; cat ${slackpkgPolicy} >> /etc/slackpkg/slackpkg.conf")
    machine.succeed("systemctl stop dhcpcd; ip link set eth0 down")
    if "${frontend}" == "slapt-get":
        with subtest("native checksum signature rejection"):
            machine.succeed("cp /packages/repo1/CHECKSUMS.md5 /packages/checksums.good; echo tampered >> /packages/repo1/CHECKSUMS.md5; touch -d @11 /packages/repo1/CHECKSUMS.md5")
            code, output = machine.execute("slapt-get --config /etc/slapt-getrc --update 2>&1")
            assert code != 0 and "Checksums signature could not be verified" in output, output
            machine.succeed("cp /packages/checksums.good /packages/repo1/CHECKSUMS.md5; touch -d @12 /packages/repo1/CHECKSUMS.md5")
    for version in [1, 2]:
        with subtest("native ${frontend} installation version " + str(version)):
            if "${frontend}" == "slapt-get":
                output = machine.succeed("ln -sfn /packages/repo" + str(version) + " /packages/repo; slapt-get --config /etc/slapt-getrc --update")
                assert "Verifying checksum signature" in output and "Verified" in output, output
                if version == 1:
                    with subtest("native package checksum rejection"):
                        machine.succeed("cp /packages/repo1/slackware64/impurifiers/*.txz /packages/package.good; echo tampered >> /packages/repo1/slackware64/impurifiers/*.txz")
                        code, output = machine.execute("slapt-get --config /etc/slapt-getrc --no-prompt --install frontend-tool 2>&1")
                        assert code != 0 and "checksum" in output.lower(), output
                        machine.fail("test -e /opt/nix/profile/bin/frontend-tool")
                        machine.succeed("cp /packages/package.good /packages/repo1/slackware64/impurifiers/$(basename /packages/v1/*.txz); slapt-get --config /etc/slapt-getrc --clean")
            if "${frontend}" == "slackpkg":
                print(machine.succeed("ln -sfn /packages/repo" + str(version) + " /packages/repo; systemd-run --pipe --wait --collect --setenv=PATH=/usr/bin:/usr/sbin:/bin:/sbin --setenv=TERM=dumb --setenv=HOME=/root --setenv=GNUPGHOME=/root/.gnupg -p RuntimeMaxSec=45s -p TimeoutStopSec=2s ${pkgs.util-linux}/bin/setsid --wait /usr/sbin/slackpkg update"))
            command = {
                "slackpkg": "/usr/sbin/slackpkg " + ("install" if version == 1 else "upgrade") + " frontend-tool",
                "netpkg": "netpkg install /packages/v" + str(version) + "/*.txz",
                "sbopkg": "/usr/sbin/sbopkg -V local/local -B -e stop -D /packages/recipes/v" + str(version) + " -i frontend-tool",
                "slapt-get": "slapt-get --config /etc/slapt-getrc --no-prompt --install frontend-tool",
            }["${frontend}"]
            answer = "echo 1 | " if "${frontend}" == "netpkg" else ""
            bound = "systemd-run --pipe --wait --collect --setenv=PATH=/usr/bin:/usr/sbin:/bin:/sbin --setenv=TERM=dumb --setenv=HOME=/root --setenv=GNUPGHOME=/root/.gnupg -p RuntimeMaxSec=45s -p TimeoutStopSec=2s ${pkgs.util-linux}/bin/setsid --wait " if "${frontend}" == "slackpkg" else "setsid --wait timeout --foreground -k 2s 60s "
            machine.succeed(answer + bound + command, timeout=90)
            machine.succeed("test $(/opt/nix/profile/bin/frontend-tool) = " + str(version))
            machine.succeed("test -f /var/log/packages/$(basename /packages/v" + str(version) + "/*.txz .txz)")
            if version == 1:
                machine.succeed("echo administrator > /etc/frontend-tool.conf")
    machine.succeed("grep administrator /etc/frontend-tool.conf; grep version=2 /etc/frontend-tool.conf.new")
    machine.succeed("su -s /bin/sh nobody -c /opt/nix/profile/bin/frontend-tool | grep '^2$'; nix-store --gc; test $(/opt/nix/profile/bin/frontend-tool) = 2")
    remove = "slapt-get --config /etc/slapt-getrc --no-prompt --remove frontend-tool" if "${frontend}" == "slapt-get" else ("/usr/sbin/slackpkg remove frontend-tool" if "${frontend}" == "slackpkg" else "/sbin/removepkg frontend-tool")
    if "${frontend}" == "netpkg":
        remove = "echo 1 | setsid --wait timeout --foreground -k 2s 60s netpkg remove frontend-tool"
    if "${frontend}" == "slackpkg":
        remove = "systemd-run --pipe --wait --collect --setenv=PATH=/usr/bin:/usr/sbin:/bin:/sbin --setenv=HOME=/root --setenv=GNUPGHOME=/root/.gnupg -p RuntimeMaxSec=45s -p TimeoutStopSec=2s ${pkgs.util-linux}/bin/setsid --wait " + remove
    machine.succeed(remove)
    machine.succeed("/usr/sbin/nix-profile-engine prune --keep 0; nix-store --gc")
    machine.fail("test -e /opt/nix/profile/bin/frontend-tool")
    machine.fail("test -e ${builtins.unsafeDiscardStringContext (toString (tool "2"))}")
  '';
}
