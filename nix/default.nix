# SPDX-License-Identifier: MIT
{
  pkgs,
  coreSrc,
  sourceInfo ? { },
}:
let
  inherit (pkgs) lib;
  core = import (coreSrc + "/nix") {
    inherit pkgs;
    sourceInfo = {
      # Native updates must include adapter-only releases, not just engine pins.
      lastModified = pkgs.lib.max (if builtins.isAttrs coreSrc then coreSrc.lastModified or 0 else 0) (
        if builtins.isAttrs sourceInfo then sourceInfo.lastModified or 0 else 0
      );
    };
    namespace = "pkgtools-impurifier";
  };
  architecture =
    if pkgs.stdenv.hostPlatform.isx86_64 then
      "x86_64"
    else if pkgs.stdenv.hostPlatform.isAarch64 then
      "aarch64"
    else
      throw "unsupported pkgtools architecture";
  guard = ''
    if [ "$(pwd -P)" != / ] || { [ -n "''${ROOT:-}" ] && [ "$ROOT" != / ]; }; then
      echo 'pkgtools-impurifier: refusing host activation for a foreign ROOT' >&2
      exit 1
    fi
  '';
  activate = pkgs.writeText "pkgtools-impurifier-activate" ''
    #!/bin/sh
    set -eu
    if [ -n "''${ROOT:-}" ] && [ "$ROOT" != / ]; then
      echo 'pkgtools-impurifier: refusing host activation for a foreign ROOT' >&2
      exit 1
    fi
    exec /usr/sbin/nix-profile-engine reconcile
  '';
  buildPackage =
    {
      name,
      version,
      payload,
      architecture ? "noarch",
      build ? "1",
      description ? "Impurified Nix application",
      configPaths ? [ ],
      postInstall ? "",
      hostActivation ? true,
      postRemove ? "",
      dependencies ? [ ],
    }:
    assert lib.assertMsg (
      builtins.match "[a-z0-9][a-z0-9+_.-]*" name != null
      && lib.all (v: builtins.match "[A-Za-z0-9_.+]+" v != null) [
        version
        architecture
        build
      ]
    ) "invalid pkgtools filename metadata";
    assert lib.assertMsg (builtins.match "[^\n\r]+" description != null) "invalid description";
    assert lib.assertMsg (lib.all (
      path:
      builtins.match "/etc/[A-Za-z0-9/_.+-]+" path != null
      && lib.all (part: part != "." && part != "..") (lib.splitString "/" path)
    ) configPaths) "invalid protected config path";
    assert lib.assertMsg (lib.all (
      value: builtins.match "[A-Za-z0-9 .,+|():<>=~_-]+" value != null
    ) dependencies) "invalid advisory dependency";
    pkgs.runCommand "${name}-${version}-${architecture}-${build}-pkgtools"
      {
        nativeBuildInputs = [
          pkgs.gnutar
          pkgs.xz
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        passthru.filename = "${name}-${version}-${architecture}-${build}.txz";
      }
      ''
        mkdir -p root/install $out
        cp -r ${payload}/. root/
        chmod -R u+w root
        ${lib.concatMapStringsSep "\n" (path: ''
          mv root${lib.escapeShellArg path} root${lib.escapeShellArg "${path}.new"}
        '') configPaths}
        cat > root/install/slack-desc <<'DESC'
        ${lib.concatStringsSep "\n" (
          [ "${name}: ${name} (${description})" ] ++ lib.replicate 10 "${name}:"
        )}
        DESC
        cat > root/install/doinst.sh <<'SCRIPT'
        #!/bin/sh
        # SPDX-License-Identifier: MIT
        set -eu
        ${lib.optionalString hostActivation guard}
        config() {
          new="$1"
          old="''${new%.new}"
          if [ ! -e "$old" ] && [ ! -L "$old" ]; then
            mv "$new" "$old"
          elif cmp -s "$new" "$old"; then
            rm "$new"
          fi
        }
        ${lib.concatMapStringsSep "\n" (
          path: "config ${lib.escapeShellArg "${lib.removePrefix "/" path}.new"}"
        ) configPaths}
        ${postInstall}
        SCRIPT
        cat > root/install/douninst.sh <<'SCRIPT'
        #!/bin/sh
        # SPDX-License-Identifier: MIT
        set -eu
        ${lib.optionalString hostActivation guard}
        # upgradepkg removes the old native inventory before its final install
        # pass processes .new files and activates the replacement.
        case "$0" in *-upgraded-????-??-??,??:??:??) exit 0 ;; esac
        ${postRemove}
        SCRIPT
        ${lib.optionalString (dependencies != [ ]) ''
          cat > root/install/slack-required <<'DEPS'
          ${lib.concatStringsSep "\n" dependencies}
          DEPS
        ''}
        tar -C root --transform='flags=r;s,^\./\(.\),\1,' --sort=name --mtime=@1 --owner=0 --group=0 --numeric-owner -cJf $out/${name}-${version}-${architecture}-${build}.txz .
      '';
  makePackage =
    args@{
      pkg,
      build ? "1",
      hostDependencies ? [ ],
      ...
    }:
    let
      payload = core.makePayload (
        builtins.removeAttrs args [
          "build"
          "hostDependencies"
        ]
      );
      required = core.runtimeVersion;
    in
    buildPackage {
      name = payload.name;
      inherit (payload) version description configPaths;
      inherit payload architecture;
      build = "${build}_${if payload.offline then "offline" else "net"}";
      dependencies = [ "pkgtools-impurifier >= ${required}" ] ++ hostDependencies;
      postInstall = ''
        /usr/bin/python3 - <<'PYTHON'
        from pathlib import Path
        import sys
        actual = tuple(map(int, Path('/usr/share/pkgtools-impurifier/runtime-version').read_text().strip().split('.')))
        if actual < tuple(map(int, '${required}'.split('.'))):
            sys.exit('pkgtools-impurifier: upgrade the native runtime first')
        PYTHON
        /usr/sbin/pkgtools-impurifier-activate
      '';
      postRemove = "[ ! -x /usr/sbin/pkgtools-impurifier-activate ] || /usr/sbin/pkgtools-impurifier-activate";
    };
  makeRuntimePackage =
    {
      bundledNixStore ? null,
      bundledNixNotices ? [ ],
      nixDependency ? (if bundledNixStore == null then "nix" else null),
      pythonDependency ? "python3",
    }:
    buildPackage {
      name = "pkgtools-impurifier";
      version = core.runtimeVersion;
      dependencies = lib.optional (nixDependency != null) nixDependency ++ [ pythonDependency ];
      architecture = if bundledNixStore == null then "noarch" else architecture;
      payload = pkgs.runCommand "pkgtools-impurifier-runtime-payload" { } ''
        mkdir -p $out
        cp -r ${core.makeRuntimeTree { inherit bundledNixStore bundledNixNotices; }}/. $out/
        chmod -R u+w $out
        install -Dm755 ${activate} $out/usr/sbin/pkgtools-impurifier-activate
        mkdir -p $out/usr/share/pkgtools-impurifier
        echo ${core.runtimeVersion} > $out/usr/share/pkgtools-impurifier/runtime-version
      '';
      postInstall = "/usr/sbin/pkgtools-impurifier-activate";
    };
  makeRepository =
    {
      packages,
      timestamp ? sourceInfo.lastModified or 0,
    }:
    pkgs.runCommand "pkgtools-impurifier-repository"
      {
        nativeBuildInputs = [
          pkgs.python3
          pkgs.gnutar
          pkgs.xz
        ];
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
        packageList = pkgs.writeText "repository-packages.json" (
          builtins.toJSON (map (package: "${package}/${package.filename}") packages)
        );
      }
      ''
        python3 ${./repository.py} "$packageList" "$out" ${toString timestamp} ${./sign-repository.sh}
      '';
  makeSlackBuild =
    { package }:
    pkgs.runCommand "${package.name}-SlackBuild"
      {
        __structuredAttrs = true;
        unsafeDiscardReferences.out = true;
      }
      ''
        mkdir -p $out
        cp ${package}/${package.filename} $out/payload.txz
        cat > $out/impurifier.SlackBuild <<'SCRIPT'
        #!/bin/sh
        # SPDX-License-Identifier: MIT
        set -eu
        CWD="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
        OUTPUT="''${OUTPUT:-/tmp}"
        mkdir -p "$OUTPUT"
        OUTPUT="$(CDPATH= cd -- "$OUTPUT" && pwd)"
        PKG="$(mktemp -d "''${TMPDIR:-/tmp}/impurifier-pkg.XXXXXXXX")"
        trap 'rm -rf "$PKG"' EXIT HUP INT TERM
        test "$(sha256sum "$CWD/payload.txz" | cut -d' ' -f1)" = @payloadHash@
        tar -xJf "$CWD/payload.txz" -C "$PKG"
        cd "$PKG"
        /sbin/makepkg -l n -c n "$OUTPUT/${package.filename}"
        SCRIPT
        payloadHash=$(sha256sum "$out/payload.txz" | cut -d' ' -f1)
        substituteInPlace $out/impurifier.SlackBuild --replace-fail @payloadHash@ "$payloadHash"
        chmod 755 $out/impurifier.SlackBuild
        metadata=${lib.escapeShellArg package.filename}
        metadata="''${metadata%.txz}"
        metadata="''${metadata%-*}"
        metadata="''${metadata%-*}"
        version="''${metadata##*-}"
        name="''${metadata%-*}"
        requires=""
        if tar -tJf "$out/payload.txz" | grep -x install/slack-required >/dev/null; then
          requires=$(tar -xJOf "$out/payload.txz" install/slack-required | awk '{print $1}' | xargs)
        fi
        cp $out/impurifier.SlackBuild "$out/$name.SlackBuild"
        tar -xJOf "$out/payload.txz" install/slack-desc > "$out/slack-desc"
        printf 'Prebuilt Nix closure repacked with native Slackware makepkg.\n' > "$out/README"
        cat > "$out/$name.info" <<INFO
        PRGNAM="$name"
        VERSION="$version"
        HOMEPAGE="https://github.com/nix-impurifiers/pkgtools-impurifier"
        DOWNLOAD=""
        MD5SUM=""
        DOWNLOAD_x86_64=""
        MD5SUM_x86_64=""
        REQUIRES="$requires"
        MAINTAINER="Nix Impurifiers"
        EMAIL=""
        INFO
      '';
in
{
  inherit (core)
    engine
    offlineCache
    unit
    runtimeVersion
    ;
  inherit
    buildPackage
    makePackage
    makeRuntimePackage
    makeSlackBuild
    makeRepository
    ;
  makeNativePackage =
    args:
    buildPackage (
      args
      // {
        architecture = args.architecture or architecture;
        hostActivation = false;
      }
    );
  runtimePackage = makeRuntimePackage { };
  makeNetPackage = args: makePackage (args // { offline = false; });
  makeOfflinePackage = args: makePackage (args // { offline = true; });
}
