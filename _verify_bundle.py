"""Quick verification that all scm_bi_* references in the bundle are defined."""
import re
from pathlib import Path

b = Path("gml_scheme/build/scm_bundle.gml").read_text(encoding="utf-8")
defs = set(re.findall(r"function (scm_bi_\w+)", b))
refs = set(re.findall(r"scm_fn\([^,]+,\s*(scm_bi_\w+)\)", b))
print(f"Defined: {len(defs)}, Referenced: {len(refs)}")

missing = refs - defs
if missing:
    print("MISSING:", sorted(missing))
else:
    print("All references resolved!")

orphans = defs - refs
if orphans:
    print("Orphan defs (not registered):", sorted(orphans))

# Also verify scm_register_* calls in scm_init
reg_defs = set(re.findall(r"function (scm_register_\w+)", b))
print(f"\nRegister functions defined: {sorted(reg_defs)}")
reg_calls = re.findall(r"(scm_register_\w+)\(global", b)
print(f"Register calls in scm_init: {sorted(reg_calls)}")

# Verify prelude aliases reference registered names
names = set(re.findall(r'scm_env_set\(_env,\s*"([^"]+)"', b))
prelude = Path("gml_scheme/src/prelude.scm").read_text(encoding="utf-8")
aliases = re.findall(r"\(define\s+\S+\s+(gml:[a-z:-]+)", prelude)
gml_names = [n for n in names if n.startswith("gml:")]
print(f"\nPrelude gml: aliases: {len(aliases)}, registered gml: names: {len(gml_names)}")
alias_missing = [a for a in aliases if a not in names]
if alias_missing:
    print("MISSING prelude aliases:", alias_missing)
else:
    print("All prelude aliases resolve!")
