#!/usr/bin/env python3
"""Allowlist lint for CV HTML. Exit 0 if clean, 3 with reasons on stderr.

CV text may derive from untrusted job descriptions. Rather than denylisting
bad constructs, only a small set of static tags and attributes is accepted,
and any stray '<' in text or an unparsed construct is rejected.
"""
import re
import sys
from html.parser import HTMLParser

TAGS = {"html", "head", "meta", "title", "style", "body", "h1", "h2", "h3",
        "div", "p", "ul", "ol", "li", "b", "strong", "i", "em", "span", "br"}
ATTRS = {"class", "lang"}
VOID = {"meta", "br"}


class Lint(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=False)
        self.errors = []
        self.in_style = False

    def err(self, msg):
        self.errors.append(f"line {self.getpos()[0]}: {msg}")

    def handle_starttag(self, tag, attrs):
        if tag not in TAGS:
            return self.err(f"tag <{tag}> not allowed")
        if tag == "meta":
            if not (len(attrs) == 1 and attrs[0][0] == "charset"
                    and (attrs[0][1] or "").lower() == "utf-8"):
                self.err("only <meta charset=\"utf-8\"> is allowed")
            return
        for k, _ in attrs:
            if k not in ATTRS:
                self.err(f"attribute {k!r} on <{tag}> not allowed")
        self.in_style = tag == "style"

    def handle_startendtag(self, tag, attrs):
        self.handle_starttag(tag, attrs)

    def handle_endtag(self, tag):
        if tag not in TAGS:
            self.err(f"closing tag </{tag}> not allowed")
        if tag == "style":
            self.in_style = False

    def handle_data(self, data):
        if self.in_style:
            if re.search(r"@import|url\s*\(|expression\s*\(|</|<!|javascript:",
                         data, re.I):
                self.err("style contains import/url()/markup")
        elif "<" in data:
            self.err("stray '<' in text (malformed or smuggled markup)")

    def handle_decl(self, decl):
        if decl.strip().lower() != "doctype html":
            self.err("only <!DOCTYPE html> is allowed")

    def handle_pi(self, data):
        self.err("processing instruction not allowed")

    def unknown_decl(self, data):
        self.err("CDATA/conditional section not allowed")

    def handle_comment(self, data):
        if re.search(r"\[if|<|>", data, re.I):
            self.err("comment with markup or conditional")


def main(path):
    raw = open(path, "rb").read()
    if b"\x00" in raw:
        print("NUL byte in input", file=sys.stderr)
        return 3
    text = raw.decode("utf-8", errors="strict")
    p = Lint()
    p.feed(text)
    p.close()
    if p.errors:
        for e in p.errors[:10]:
            print(f"lint: {e}", file=sys.stderr)
        return 3
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1]))
