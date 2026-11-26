import json
from pathlib import Path
import shutil
import sys
import tomllib


source, output = (Path(arg) for arg in sys.argv[1:])
gizlet = tomllib.loads(source.read_text(encoding="utf-8"))
packages = gizlet["packages"]
if len(packages) != 1:
    sys.exit(f"{source}: expected one [[packages]] entry, found {len(packages)}")

manifest = {"schema": 1}
for key in ("id", "name", "names", "version", "description", "descriptions", "color"):
    if key in gizlet:
        manifest[key] = gizlet[key]
manifest["runtime"] = gizlet.get("runtime", 1)
for key in ("target", "tier", "entry"):
    manifest[key] = packages[0][key]
if "icon" in gizlet:
    icon = source.parent / gizlet["icon"]
    manifest["icon"] = f"icon{icon.suffix}"
    shutil.copyfile(icon, output.parent / manifest["icon"])
output.write_text(json.dumps(manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
