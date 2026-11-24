import re
import sys

# codex_launches.py <prefix> <file>...: every Codex launch in shell code and Markdown code must start
# with <prefix>. Prints "file:line: <code>" for each one that does not and exits 1 if any.
prefix = sys.argv[1] + " "
# Only "codex <subcommand or flag>", so finditer finds every launch on a line, not just the first.
LAUNCH = re.compile(r"(?<![\w/.$-])codex (?:exec|resume|login|app-server|mcp|sandbox|review|-p|-s|-a|-c|-C|-m)\b")
# Where one command of a compound shell line ends.
END = re.compile(r"\s*(?:&&|\|\||[;|&)`])")
EXEMPT = {"codex login status", "codex login --with-api-key"}
bad = False

def units(path, text):
    """(line, code, is_shell): joined shell lines, Markdown fenced lines and inline code spans."""
    lines = text.split("\n")
    md = path.endswith(".md")
    fence = None
    i = 0
    while i < len(lines):
        start, line = i + 1, lines[i]
        stripped = line.strip()
        if md and fence is None and re.match(r"(```|~~~)", stripped):
            fence = stripped[:3]
            i += 1
            continue
        if md and fence is not None and stripped.startswith(fence):
            fence = None
            i += 1
            continue
        code = md and fence is not None or not md
        if code:
            while line.endswith("\\") and i + 1 < len(lines):
                i += 1
                line = line[:-1].rstrip() + " " + lines[i].strip()
            if not md and line.lstrip().startswith("#"):
                i += 1
                continue
            yield start, line, not md
        else:
            for span in re.findall(r"`([^`]+)`", line):
                # A span of two words, such as `codex exec`, names a command in prose.
                if len(span.split()) > 2:
                    yield start, span, False
        i += 1

for path in sys.argv[2:]:
    text = open(path, encoding="utf-8").read()
    for line, code, shell in units(path, text):
        for m in LAUNCH.finditer(code):
            # In a script, text inside double quotes is a message, not a command.
            if shell and code[: m.start()].count('"') % 2:
                continue
            launch = END.split(code[m.start():], maxsplit=1)[0]
            if launch.strip() in EXEMPT:
                continue
            if not code[: m.start()].endswith(prefix):
                print(f"{path}:{line}: {code.strip()}")
                bad = True
sys.exit(1 if bad else 0)
