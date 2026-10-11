#!/usr/bin/env python3
"""Allowlist sanitizer for CV HTML: lint-cv-html.py <in.html> <out.html>

CV text may derive from untrusted job descriptions. This does not try to spot
bad markup in the input. It parses the input, accepts only a small allowlist of
static tags and attributes, and WRITES A CANONICAL RE-SERIALIZATION. The
renderer loads only that output, so the browser never sees input bytes and a
parser differential between this script and the browser cannot matter. The CSP
meta is emitted by this script as the first element of <head>.

Exit 0 on success, 3 (with reasons on stderr, no output file) on rejection.
"""
import html
import re
import sys
from html.parser import HTMLParser

BODY_TAGS = {"h1", "h2", "h3", "div", "p", "ul", "ol", "li", "b", "strong",
             "i", "em", "span", "br"}
VOID = {"br"}
ATTRS = {"class", "lang"}
VALUE = re.compile(r"^[A-Za-z0-9 _\-]{0,80}$")
CSP = ("default-src 'none'; style-src 'unsafe-inline'; img-src data:; "
       "base-uri 'none'; form-action 'none'")
ENT = re.compile(r"^(#[0-9]{1,7}|#[xX][0-9A-Fa-f]{1,6}|[A-Za-z][A-Za-z0-9]{1,31})$")


class Sanitize(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.errors = []
        self.title = []
        self.style = []
        self.body = []
        self.where = "top"      # top | head | title | style | body
        self.stack = []

    def err(self, msg):
        self.errors.append(f"line {self.getpos()[0]}: {msg}")

    def handle_decl(self, decl):
        if decl.strip().lower() != "doctype html":
            self.err("only <!DOCTYPE html> is allowed")

    def handle_pi(self, data):
        self.err("processing instruction not allowed")

    def unknown_decl(self, data):
        self.err("CDATA/conditional section not allowed")

    def handle_comment(self, data):
        pass  # dropped, never serialized

    def _attrs_ok(self, tag, attrs):
        out = []
        for k, v in attrs:
            if k not in ATTRS:
                self.err(f"attribute {k!r} on <{tag}> not allowed")
            elif v is None or not VALUE.match(v):
                self.err(f"attribute {k!r} value not allowed")
            else:
                out.append(f' {k}="{v}"')
        return "".join(out)

    def handle_starttag(self, tag, attrs):
        w = self.where
        if tag in ("html", "head"):
            if w in ("top", "head") or (tag == "html" and w == "top"):
                self.where = "head" if tag == "head" else self.where
            else:
                self.err(f"<{tag}> in unexpected place")
            return
        if tag == "meta":
            if not (len(attrs) == 1 and attrs[0][0] == "charset"
                    and (attrs[0][1] or "").lower() == "utf-8"):
                self.err('only <meta charset="utf-8"> is allowed')
            return
        if tag == "title" and w in ("top", "head"):
            self.where = "title"
            return
        if tag == "style" and w in ("top", "head"):
            self.where = "style"
            return
        if tag == "body" and w in ("top", "head"):
            self.where = "body"
            return
        if w == "body" and tag in BODY_TAGS:
            a = self._attrs_ok(tag, attrs)
            self.body.append(f"<{tag}{a}>")
            if tag not in VOID:
                self.stack.append(tag)
            return
        self.err(f"tag <{tag}> not allowed here")

    def handle_startendtag(self, tag, attrs):
        if tag in VOID:
            self.handle_starttag(tag, attrs)
        else:
            self.err(f"self-closing <{tag}/> not allowed")

    def handle_endtag(self, tag):
        if tag in ("html", "head", "body") or (tag == "title" and self.where == "title") \
                or (tag == "style" and self.where == "style"):
            if tag in ("title", "style"):
                self.where = "head"
            return
        if self.where == "body" and tag in BODY_TAGS and tag not in VOID:
            if self.stack and self.stack[-1] == tag:
                self.stack.pop()
                self.body.append(f"</{tag}>")
                return
            self.err(f"unbalanced </{tag}>")
            return
        self.err(f"closing tag </{tag}> not allowed")

    def _text(self, s):
        w = self.where
        if w == "title":
            self.title.append(s)
        elif w == "style":
            self.style.append(s)
        elif w == "body":
            self.body.append(s)
        elif s.strip():
            self.err("text outside body")

    def handle_data(self, data):
        if self.where == "style":
            if "<" in data or re.search(r"@import|url\s*\(|expression\s*\(|javascript:", data, re.I):
                self.err("style contains markup, import or url()")
            self._text(data)
        else:
            if "<" in data:
                self.err("stray '<' in text")
                return
            self._text(html.escape(data, quote=False))

    def handle_entityref(self, name):
        if self.where == "style" or not ENT.match(name):
            return self.err(f"entity &{name}; not allowed")
        self._text(f"&{name};")

    def handle_charref(self, name):
        if self.where == "style" or not ENT.match("#" + name):
            return self.err(f"character reference &#{name}; not allowed")
        self._text(f"&#{name};")


def main(src, dst):
    raw = open(src, "rb").read()
    if b"\x00" in raw:
        print("NUL byte in input", file=sys.stderr)
        return 3
    p = Sanitize()
    p.feed(raw.decode("utf-8", errors="strict"))
    p.close()
    if p.stack:
        p.errors.append(f"unclosed tags: {p.stack}")
    if p.where not in ("body",):
        p.errors.append("no <body> found")
    if p.errors:
        for e in p.errors[:10]:
            print(f"lint: {e}", file=sys.stderr)
        return 3
    title = "".join(p.title)
    out = (
        "<!DOCTYPE html>\n<html><head>"
        f'<meta http-equiv="Content-Security-Policy" content="{CSP}">'
        '<meta charset="utf-8">'
        f"<title>{title}</title>"
        f"<style>{''.join(p.style)}</style>"
        "</head><body>" + "".join(p.body) + "</body></html>\n"
    )
    with open(dst, "w", encoding="utf-8") as f:
        f.write(out)
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 3:
        print("usage: lint-cv-html.py <in.html> <out.html>", file=sys.stderr)
        sys.exit(2)
    sys.exit(main(sys.argv[1], sys.argv[2]))
