# Testing

QEMU executes upstream Slackware pkgtools scripts with their original bodies and patched interpreter paths. Tests use an initially absent application closure and disable networking, then exercise offline replacement, native .new configuration policy, lifecycle/service intent, cooperating drivers, foreign ROOT safety, removal and GC. The outer OS/init is NixOS. Provider installation and Slackware boot are separate work.
