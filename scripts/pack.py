import hashlib
import json
from pathlib import Path
import sys
import zipfile


app, dist = (Path(arg) for arg in sys.argv[1:])
manifest = json.loads((app / "manifest.json").read_text(encoding="utf-8"))
output = dist / "{id}-{version}-{target}-{tier}.gzl".format(**manifest)
checksums = []
with zipfile.ZipFile(output, "w", zipfile.ZIP_STORED, allowZip64=False) as archive:
    for path in sorted(app.rglob("*")):
        if not path.is_file():
            continue
        relative = path.relative_to(app).as_posix()
        with path.open("rb") as source:
            checksums.append(f"{hashlib.file_digest(source, 'sha256').hexdigest()}  {relative}\n")
        archive.write(path, relative)
    archive.writestr("CHECKSUMS", "".join(checksums))
