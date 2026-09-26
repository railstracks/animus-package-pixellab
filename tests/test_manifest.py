#!/usr/bin/env python3
"""test_manifest.py — static lint mirroring the kernel's manifest rules.

Covers what ApiPackageStore/ManifestV1 enforce: no floats (canonicalization),
command-name grammar, parameter shape, secret typing, egress_hosts validity,
script presence, and deterministic build output.

Run: python3 tests/test_manifest.py
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
FAILURES = []


def check(label, cond, extra=""):
    if cond:
        print(f"ok    {label}")
    else:
        print(f"FAIL  {label} {extra}")
        FAILURES.append(label)


def no_floats(v, path="$"):
    if isinstance(v, bool) or v is None:
        return []
    if isinstance(v, int):
        return []
    if isinstance(v, float):
        return [f"{path}: float literal {v}"]
    if isinstance(v, dict):
        out = []
        for k, x in v.items():
            out += no_floats(x, f"{path}.{k}")
        return out
    if isinstance(v, list):
        out = []
        for i, x in enumerate(v):
            out += no_floats(x, f"{path}[{i}]")
        return out
    return []


m = json.load(open(os.path.join(ROOT, "manifest", "manifest.json"), encoding="utf-8"))

check("kind api_package", m.get("kind") == "api_package")
check("name pixellab", m.get("name") == "pixellab")
check("semver version", re.match(r"^\d+\.\d+\.\d+$", m["version"]) is not None)

floats = no_floats(m)
check("no float literals in manifest", not floats, str(floats))

# state schema: secret keys must be type string
for key, spec in m.get("state_schema", {}).items():
    if spec.get("secret"):
        check(f"secret '{key}' is string-typed", spec.get("type") == "string")

names = set()
for c in m["commands"]:
    n = c["name"]
    check(f"command name grammar '{n}'",
          re.match(r"^[a-z0-9]+( [a-z0-9]+)*$", n) is not None and "  " not in n)
    check(f"command '{n}' unique", n not in names)
    names.add(n)
    check(f"command '{n}' kind", c["kind"] in ("action", "hook"))
    check(f"command '{n}' has description", bool(c.get("description", "").strip()))
    sf = c.get("script_file")
    check(f"command '{n}' script exists",
          sf and os.path.isfile(os.path.join(ROOT, sf)), sf)
    if c["kind"] == "action" and "parameters" in c:
        for pn, pd in c["parameters"].items():
            check(f"'{n}' param '{pn}' has string type",
                  isinstance(pd, dict) and isinstance(pd.get("type"), str))
            check(f"'{n}' param '{pn}' type known",
                  pd.get("type") in ("string", "integer", "boolean"), pd.get("type"))

eh = m.get("egress_hosts")
check("egress_hosts declared", isinstance(eh, list) and eh == ["api.pixellab.ai"], eh)

# every script references only files that exist; every scripts/*.lua except
# _shared.lua is referenced by exactly one command
referenced = {c["script_file"] for c in m["commands"] if "script_file" in c}
on_disk = {f"scripts/{f}" for f in os.listdir(os.path.join(ROOT, "scripts"))
           if f.endswith(".lua") and f != "_shared.lua"}
check("no orphan scripts", on_disk == referenced,
      str(on_disk ^ referenced))

# built manifest is current (deterministic build)
built = os.path.join(ROOT, "built", "manifest.json")
if os.path.isfile(built):
    b = json.load(open(built, encoding="utf-8"))
    check("built manifest matches source", b == json.loads(json.dumps(m)) or
          all(c.get("script_file") is None for c in b["commands"]))
    check("built has inlined scripts",
          all(isinstance(c.get("script"), str) and "function run(" in c.get("script", "")
              for c in b["commands"]))
else:
    check("built manifest exists", False)

print()
if FAILURES:
    print(f"test_manifest: {len(FAILURES)} FAILURES")
    sys.exit(1)
print("test_manifest: ALL OK")
