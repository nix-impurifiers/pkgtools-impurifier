# pkgtools-impurifier

Emit native Slackware pkgtools `.txz` archives from Nix applications. Original
code is MIT licensed. Upstream pkgtools retains its own copyright notices.

```nix
let impurifier = inputs.pkgtools-impurifier.lib.pkgtools-impurifier { inherit pkgs; };
in impurifier.makeOfflinePackage { pkg = pkgs.hello; }
```

Build `runtime-package` and your application, then use
`upgradepkg --install-new --reinstall /path/to/output/*.txz`. Output directories
preserve the native filename: pkgtools derives package identity from that name.
`makeNetPackage` retains an installable; `makeOfflinePackage` embeds its complete
closure. Native package name stays stable across flavors; the native build tag
contains `net` or `offline`. Use upgradepkg for replacement: installpkg alone
allows multiple versions to coexist in its inventory.

Nix and Python must already exist. `makeRuntimePackage` accepts `nixDependency`
and `pythonDependency`. The eventual native Nix provider/installer is deferred.
Runtime versions derive from the pinned core source timestamp, independently of
application versions. Application install scripts check that minimum runtime.

Pkgtools has no native dependency solver. `hostDependencies` and runtime
requirements appear in advisory `install/slack-required`; operators or repository
frontends must provide them. No enforced dependency claim is made. Missing
runtime/providers produce script diagnostics; native pkgtools may still report
success. After repair, run `/usr/sbin/nix-profile-engine reconcile`. Engine
failure keeps the previous profile published.

Shared configuration, account/directory, lifecycle, service and explicit
hardware arguments are supported. Select an explicit systemd, OpenRC or runit
protocol when using service integration; this does not implement Slackware's
rc.local boot policy. Native install/doinst.sh activates after configuration;
install/douninst.sh reconciles removal. Upgrade removal callbacks defer until
the final native install pass. Configuration follows Slackware `.new` policy:
new defaults replace absent/identical files; modified configuration stays, with
the new default beside it as `.new`. Edited active files remain on removal.

Foreign ROOT scripts reject activation. General driver file triggers do not
exist: cooperating native driver scripts call
`/usr/sbin/pkgtools-impurifier-activate`, or operators reconcile explicitly.
`makeSlackBuild { package = artifact; }` emits a portable source bundle whose
SlackBuild repacks the prebuilt payload using native makepkg. It does not rebuild
the application outside Nix. `OUTPUT` selects the archive destination. It also
emits `<name>.SlackBuild`, `<name>.info`, README and slack-desc for a local
sbopkg repository. The bundled payload is verified by SHA256 before extraction;
`.info` lists advisory dependency names from the native package.

`buildPackage` accepts a raw payload, script bodies and advisory dependencies;
it does not automatically activate raw packages.

`makeRepository { packages = [ runtime app ]; }` emits a Slackware repository
with PACKAGES.TXT, FILELIST.TXT, MANIFEST.bz2 and CHECKSUMS.md5. Its optional
`timestamp` defaults to the adapter source timestamp and controls FILELIST's
publication date. Copy the output to a writable publication directory, then run
`./sign-repository --local-user <key-id>` there with your existing GPG keyring.
The helper signs each `.txz`, includes those signatures in CHECKSUMS.md5, then
signs CHECKSUMS.md5.
Publish metadata and signatures together with distinct modification times for
successive publications so native clients refresh their caches.

`nix flake check -L --max-jobs 2` exercises actual upstream pkgtools, slackpkg,
slapt-get, sbopkg and Netpkg in isolated NixOS VMs. See
[testing](docs/development/testing.md) for coverage and remaining limitations.

## Native payloads and bundled Nix

`makeNativePackage { name; version; payload; architecture?; configPaths?; ... }`
accepts a producer-prepared filesystem tree. It adds no engine dependency or
activation callbacks. Native `.new` configuration handling remains available,
including installation into a foreign root. The producer supplies a working
target layout; binaries are not relocated. Dependency metadata is advisory, as
with ordinary pkgtools archives. The native VM executes a static payload in a
root without `/nix`, upgrades it and removes it with upstream pkgtools.

`makeRuntimePackage` accepts `bundledNixStore` and `bundledNixNotices` for a static
ELF client and upstream notices. Bundling drops the default native Nix requirement
and uses a machine architecture; Python remains required. Compatible external
clients take precedence, explicit `IMPURIFIER_NIX_STORE` disables fallback, and
a failed mutation is never retried through another client. A bundled-client VM
repeats the lifecycle suite with an incompatible external candidate. Bundling is
not a Nix provider/installer.
