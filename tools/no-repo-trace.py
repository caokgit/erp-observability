#!/usr/bin/env python3
"""Fail when text bound for Azure or Postgres names the GitHub repo (AGENTS.md, "Nothing in Azure names the repo").

Reads JSON (a `terraform show -json` plan, `az ... -o json` output) or plain text on stdin, and lists every string that
holds the GitHub account, a repo name, or a path inside the repo, with where it sits; prints only the matched words.

    terraform show -json plan.tfplan | python3 tools/no-repo-trace.py
    az resource list -g erp-mgmt-obs-rg -o json | python3 tools/no-repo-trace.py
"""
import json
import re
import sys

TRACE = re.compile(r"caokgit|github|erp-observability|ocr-platform|AGENTS\.md|\.md#|"
                   r"\b(?:docs|kql|job|sql|tools|terraform|method|apps)/", re.I)


def walk(node, path="$"):
    if isinstance(node, dict):
        for k, v in node.items():
            yield from walk(k, f"{path}.<key>")
            yield from walk(v, f"{path}.{k}")
    elif isinstance(node, list):
        for i, v in enumerate(node):
            yield from walk(v, f"{path}[{i}]")
    elif isinstance(node, str):
        yield path, node


def main() -> int:
    text = sys.stdin.read()
    try:
        doc = json.loads(text)
        if isinstance(doc, dict) and "resource_changes" in doc:
            # a plan: only the resources' values reach Azure; variable and output descriptions stay on the laptop
            doc = {"resource_changes": [{"address": rc.get("address"), "after": rc.get("change", {}).get("after")}
                                        for rc in doc["resource_changes"]]}
        strings = list(walk(doc))
    except ValueError:
        strings = [(f"line {i}", line) for i, line in enumerate(text.splitlines(), 1)]
    hits = [(where, sorted(set(m.group(0) for m in TRACE.finditer(s)))) for where, s in strings if TRACE.search(s)]
    for where, words in hits:
        print(f"trace: {where}: {', '.join(words)}")
    print(f"{len(strings)} string(s) scanned, {len(hits)} with a trace of the repo")
    return 1 if hits else 0


if __name__ == "__main__":
    sys.exit(main())
