# SPDX-License-Identifier: MIT
{ pkgs }:
{
  slackpkg = pkgs.fetchurl {
    url = "https://slackware.osuosl.org/slackware64/slackware64/ap/slackpkg-15.0.10-noarch-1.txz";
    hash = "sha256-gXvYyvuScZqCxHVH1GHvyo2uBDZAo9QxqOiVOFUK5B8=";
  };
  slapt-get = pkgs.stdenv.mkDerivation {
    pname = "slapt-get";
    version = "0.11.11";
    src = pkgs.fetchzip {
      url = "https://github.com/jaos/slapt-get/archive/refs/tags/0.11.11.tar.gz";
      hash = "sha256-UdbgRkZc14VRzWve79VBYn+e0qvfPRSuX0/4MVAE41M=";
    };
    nativeBuildInputs = [
      pkgs.meson
      pkgs.ninja
      pkgs.pkg-config
      pkgs.gettext
    ];
    postPatch = ''
      substituteInPlace src/slaptgpgme.c --replace-fail 'NULL, RC_DIR' 'NULL, "/etc/slapt-get"'
    '';
    buildInputs = [
      pkgs.curl
      pkgs.zlib
      pkgs.openssl
      pkgs.gpgme
    ];
    mesonFlags = [
      "--sysconfdir=${placeholder "out"}/etc"
      "-Dwerror=false"
    ];
    meta.license = pkgs.lib.licenses.gpl2Plus;
  };
  sbopkg = pkgs.fetchzip {
    url = "https://github.com/sbopkg/sbopkg/archive/refs/tags/0.38.3.tar.gz";
    hash = "sha256-5qbAF4JF0EjE/c7KSWuWgBO5xrQst3gQccWiAmcI+1U=";
  };
  netpkg = pkgs.stdenv.mkDerivation {
    pname = "netpkg";
    version = "12.0";
    src = pkgs.fetchzip {
      url = "https://github.com/JPGuillemin/Netpkg/archive/b2b5c866cc409f8722c36407767acecbaa2d5740.tar.gz";
      hash = "sha256-zPVQe945GYf7zJRlZdBaK7350DE0JL/fIoFZG91sX80=";
    };
    installPhase = ''
      mkdir -p $out/bin $out/share/licenses/netpkg
      cp netpkg vfilter $out/bin/
      cp LICENSE vfilter.c $out/share/licenses/netpkg/
      chmod +x $out/bin/netpkg
      patchShebangs $out/bin/netpkg
    '';
    meta.license = pkgs.lib.licenses.gpl2Plus;
  };
}
