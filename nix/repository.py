# SPDX-License-Identifier: MIT
"""Write Slackware repository metadata from native package contents."""
import bz2
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile

packages, output = Path(sys.argv[1]), Path(sys.argv[2])
location = "slackware64/impurifiers"
(output / location).mkdir(parents=True)
entries, manifest = [], []
seen = set()
for source in map(Path, json.loads(packages.read_text())):
    if source.name in seen:
        raise ValueError(f"duplicate package filename: {source.name}")
    seen.add(source.name)
    target = output / location / source.name
    shutil.copyfile(source, target)
    with tarfile.open(source) as archive:
        members = {member.name.removeprefix("./"): member for member in archive}
        description = archive.extractfile(members["install/slack-desc"]).read().decode()
        dependencies = ""
        if "install/slack-required" in members:
            dependencies = ",".join(archive.extractfile(members["install/slack-required"]).read().decode().splitlines())
        size = sum(member.size for member in members.values())
    digest = hashlib.file_digest(source.open("rb"), "md5").hexdigest()
    entries.append(f"PACKAGE NAME:  {source.name}\nPACKAGE LOCATION:  ./{location}\n"
                   f"PACKAGE SIZE (compressed):  {(source.stat().st_size + 1023) // 1024} K\n"
                   f"PACKAGE SIZE (uncompressed):  {(size + 1023) // 1024} K\n"
                   f"PACKAGE REQUIRED:  {dependencies}\nPACKAGE CONFLICTS:  \nPACKAGE SUGGESTS:  \n"
                   f"PACKAGE MD5SUM:  {digest}\nPACKAGE DESCRIPTION:\n{description}\n")
    manifest.append(f"||   Package:  ./{location}/{source.name}\n" + subprocess.check_output(["tar", "-tvJf", str(source)], text=True))
index = "\n".join(entries)
(output / "PACKAGES.TXT").write_text(index)
(output / "slackware64/PACKAGES.TXT").write_text(index)
(output / "slackware64/MANIFEST.bz2").write_bytes(bz2.compress("\n".join(manifest).encode()))
(output / "ChangeLog.txt").write_text("Impurifier package repository\n")
shutil.copyfile(sys.argv[4], output / "sign-repository")
(output / "sign-repository").chmod(0o755)
files = sorted(path for path in output.rglob("*") if path.is_file())
(output / "FILELIST.TXT").write_text(datetime.fromtimestamp(int(sys.argv[3]), timezone.utc).strftime("%a %b %d %H:%M:%S UTC %Y\n") + "\n".join("./" + str(path.relative_to(output)) for path in files) + "\n")
files.append(output / "FILELIST.TXT")
(output / "CHECKSUMS.md5").write_text("".join(hashlib.file_digest(path.open("rb"), "md5").hexdigest() + "  ./" + str(path.relative_to(output)) + "\n" for path in files))
