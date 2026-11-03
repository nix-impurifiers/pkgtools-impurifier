# Testing

QEMU executes upstream Slackware pkgtools scripts with their original bodies and patched interpreter paths. Tests use an initially absent application closure and disable networking, then exercise offline replacement, native .new configuration policy, lifecycle/service intent, cooperating drivers, foreign ROOT safety, removal and GC. The outer OS/init is NixOS. Provider installation and Slackware boot are separate work.

The frontend matrix pins slackpkg 15.0.10, slapt-get 0.11.11, sbopkg 0.38.3 and
Netpkg 12.0. All run their upstream transaction implementations with networking
disabled, two application versions, native pkgtools ownership, edited `.new`
configuration, ordinary-user launch and Nix GC retention/release. sbopkg builds
emitted recipes in its supported local repository. Netpkg uses local archives
and its genuine vfilter comparator. slapt-get and slackpkg use emitted local
repository metadata with actual GPG signatures. slapt-get additionally rejects
tampered signatures and corrupted package downloads before activation.

The SDK provides real FHS tools inside the guest. Netpkg's shell-colors file is
an empty UI configuration; its version marker identifies the VM fixture. The
slapt-get SDK sets its native GPG key directory to `/etc/slapt-get` while
installing build outputs in the Nix store; compiler warnings are nonfatal.
Each repository publication has a distinct metadata modification time because
native clients cache by modification time. Native clients' signature defaults
remain their own policy; these tests configure and verify signed metadata.

Full Slackware/Zenwalk boot, Slackware rc service integration, remote SBo source
fetching, Netpkg's remote dependency database and extra architectures remain
additional compatibility coverage. sbopkg has no removal operation; native
pkgtools handles removal of its built packages. Netpkg local installation uses
its native confirmation prompt. Nix provisioning remains deferred installer work.
