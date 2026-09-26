#!/usr/bin/env python3
"""Read JSON from stdin, emit Lua table constructor source to stdout."""
import json
import sys


def lua_str(s: str) -> str:
    b = s.encode("utf-8")
    out = ['"']
    for byte in b:
        c = chr(byte)
        if c == '"':
            out.append('\\"')
        elif c == "\\":
            out.append("\\\\")
        elif c == "\n":
            out.append("\\n")
        elif c == "\r":
            out.append("\\r")
        elif c == "\t":
            out.append("\\t")
        elif 32 <= byte <= 126:
            out.append(c)
        else:
            out.append("\\%d" % byte)
    out.append('"')
    return "".join(out)


def emit(v):
    if v is None:
        return "nil"
    if v is True:
        return "true"
    if v is False:
        return "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return lua_str(v)
    if isinstance(v, list):
        return "{" + ",".join(emit(x) for x in v) + "}"
    if isinstance(v, dict):
        return "{" + ",".join(
            "[%s]=%s" % (lua_str(str(k)), emit(x)) for k, x in v.items()
        ) + "}"
    raise ValueError("unserializable: %r" % (v,))


print(emit(json.load(sys.stdin)))
