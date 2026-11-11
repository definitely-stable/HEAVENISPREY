#!/usr/bin/env python3
"""Audit the exact source-to-section v6 migration and canonical Markdown links."""
from pathlib import Path
from urllib.parse import unquote
import json, posixpath, re, sys
ROOT=Path(__file__).resolve().parents[1]
WORK=ROOT/".work"
errors=[]
warnings=[]
def fail(s): errors.append(s)
def fix(body,current,paths,refs):
    def anchor(m):
        key=m.group(1)
        if key not in paths:
            fail("unknown anchor "+key)
            return m.group(0)
        return "]("+posixpath.relpath(paths[key],posixpath.dirname(current))+")"
    body=re.sub(r"\]\(#(s\d\d|v5_[\w-]+|v6_[\w-]+)\)",anchor,body)
    return re.sub(r"\[(R\d{2})\](?![:(])",
                  lambda m: "[%s](%s)"%(m.group(1),refs[m.group(1)]) if m.group(1) in refs else m.group(0),body)
def check_links(file,strict):
    data=file.read_text(encoding="utf-8")
    tick=chr(96)*3
    data=re.sub(r"(?ms)^\s*"+tick+r"[^\n]*\n.*?^\s*"+tick+r"[^\n]*$","",data)
    for m in re.finditer(r"\]\(([^)\n]+)\)",data):
        raw=m.group(1).strip()
        if not raw or raw.startswith("#") or re.match(r"^(?:[a-z][a-z0-9+.-]*:|//)",raw,re.I):continue
        raw=unquote(raw.split(' "')[0].split("#")[0].split("?")[0])
        if not raw:continue
        target=(file.parent/raw).resolve()
        if not target.is_relative_to(ROOT.resolve()) or not target.is_file():
            (errors if strict else warnings).append(str(file.relative_to(ROOT))+" -> "+raw)
def audit():
    mf=json.loads((WORK/"MANIFEST.json").read_text(encoding="utf-8"))
    source=(WORK/"archive/architecture-v6-original.md").read_text(encoding="utf-8")
    anchors=list(re.finditer(r'<a id="([^"]+)"></a>',source))
    items=mf["sections"]
    lookup={x["id"]:x for x in items}
    paths={x["id"]:x["path"] for x in items}
    refs=dict(re.findall(r"^\[(R\d{2})\]:\s*(https?://\S+)",source,re.M))
    if (len(anchors),len(items),len(lookup),len(refs))!=(63,63,63,85):
        fail("source/manifest count mismatch")
    exact=adapted=0
    for i,m in enumerate(anchors):
        key=m.group(1)
        if key not in lookup:
            fail("unindexed source anchor "+key);continue
        e=lookup[key];p=ROOT/e["path"]
        if not p.is_file():
            fail("missing file for "+key);continue
        content=p.read_text(encoding="utf-8")
        end=anchors[i+1].start() if i+1<len(anchors) else len(source)
        expected=fix(source[m.start():end].rstrip()+"\n",e["path"],paths,refs)
        if e["status"]=="adapted-role-neutral":
            adapted+=1
            if "адаптац" not in content.lower() or not e.get("superseded_by"):
                fail("adaptation provenance missing "+key)
        elif content.endswith(expected):
            exact+=1
        else:
            fail("migrated content differs from v6 "+key)
    if exact+adapted!=63:fail("section coverage incomplete")
    active=[ROOT/"README.md",ROOT/"AGENTS.md",WORK/"INDEX.md",WORK/"README.md",WORK/"CURRENT_STATE.md"]
    for sub in ("guides","templates","indexes","decisions","spec/v7","config/v7","roadmap"):
        active.extend((WORK/sub).glob("*.md"))
    for page in active:
        check_links(page,True)
        if re.search(r"(?m)^\|\s*(?:Codex|Claude(?: Code)?|Opus|OpenCode(?: Go)?)\s*\|",
                     page.read_text(encoding="utf-8")):
            fail("Model-specific assignment in active docs "+str(page.relative_to(ROOT)))
    for sub in ("spec/core","spec/v5","spec/v6"):
        for page in (WORK/sub).glob("*.md"):check_links(page,False)
    print("Source migration:",exact,"exact;",adapted,"explicitly adapted; 85 source references")
    print("Canonical pages checked:",len(active),"historic link warnings:",len(warnings))
    for warning in warnings[:20]:print("WARN:",warning)
    for issue in errors:print("FAIL:",issue,file=sys.stderr)
    if errors:raise SystemExit(1)
    print("PASS: role-neutral canonical docs, migration traceability and relative links")
if __name__=="__main__":audit()
