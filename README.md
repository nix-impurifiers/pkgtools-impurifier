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
the application outside Nix. `OUTPUT` selects the archive destination.

`buildPackage` accepts a raw payload, script bodies and advisory dependencies;
it does not automatically activate raw packages.

`nix flake check -L` uses actual pinned Slackware pkgtools scripts inside a
QEMU NixOS VM. This tests native archive inventory and transactions; it does
not establish a full Slackware boot or repository frontend compatibility.
