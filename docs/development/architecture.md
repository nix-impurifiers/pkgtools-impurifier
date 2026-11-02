# Architecture

Correctly named txz archives carry native install/removal scripts and package-owned caches. Upgrade callbacks defer old removal activation until the final install/configuration pass. Dependencies are advisory because pkgtools has no solver. Failed script activation can coexist with native success; inspect diagnostics and reconcile after repair. No arbitrary file trigger or default Slackware init ownership is invented.
