#!/bin/sh

set -eu

# Run the source generator's release-notes flattening against release-body
# shapes the fork and upstream actually publish.
test_repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

python3 -I -B - "$test_repo_root/scripts" <<'EOF'
import re
import sys

sys.path.insert(0, sys.argv[1])
from update_source_json import format_release_notes, markdown_to_plain_text

failures = 0


def check(name, actual, expected):
    global failures
    if actual != expected:
        failures += 1
        print(f"FAIL {name}\n  expected: {expected!r}\n  actual:   {actual!r}")
    else:
        print(f"ok   {name}")


fork_body = (
    "### Features\n\n"
    "- Add **Kagi** to the Search tab ([#1305](https://example.com/1305): @nick)\n\n"
    "### Fixes\n\n"
    "- Keep `media previews` working\n\n\n"
    "### Screenshots\n\n"
    "<table>\n<tr>\n"
    '<td align="center" width="25%" valign="top"><img src="https://example.com/a.png" width="200" />'
    "<br/><b>Search With Kagi</b><br/><sub>A new <code>...</code> entry</sub><br/>"
    '<a href="https://example.com/1305">#1305</a></td>\n'
    "</tr>\n</table>\n"
)
check(
    "fork body drops the Screenshots table",
    markdown_to_plain_text(fork_body),
    "Features\n"
    "- Add Kagi to the Search tab (#1305 (https://example.com/1305): @nick)\n\n"
    "Fixes\n"
    "- Keep media previews working",
)

check(
    "a section after Screenshots survives",
    markdown_to_plain_text("### Screenshots\n\n<table><tr><td>x</td></tr></table>\n\n### Fixes\n\n- Fixed it"),
    "Fixes\n- Fixed it",
)

check(
    "CRLF bodies drop the Screenshots section too",
    markdown_to_plain_text("### Fixes\r\n\r\n- Fixed it\r\n\r\n### Screenshots\r\n\r\n<table>\r\n<tr><td>x</td></tr>\r\n</table>"),
    "Fixes\r\n- Fixed it",
)

check(
    "a trailing empty Screenshots heading is dropped",
    markdown_to_plain_text("### Fixes\n\n- Fixed it\n\n### Screenshots"),
    "Fixes\n- Fixed it",
)

check(
    "stray inline tags keep their text",
    markdown_to_plain_text("- Use <code>apollo://</code> links<br/>now"),
    "- Use apollo:// links\nnow",
)

check(
    "angle brackets that are not tags are kept",
    markdown_to_plain_text("- Load < 5 MB images, I <3 Apollo, 1 > 0"),
    "- Load < 5 MB images, I <3 Apollo, 1 > 0",
)

check(
    "embedded video tags are removed",
    markdown_to_plain_text('- Demo\n\n<video src="https://example.com/a.mp4" controls width="100%"></video>'),
    "- Demo",
)

check(
    "angle-bracket placeholders in code spans are kept",
    markdown_to_plain_text("- Set `<key>` to your token"),
    "- Set <key> to your token",
)

check(
    "Markdown autolinks are kept",
    markdown_to_plain_text("- See <https://example.com/docs> for details"),
    "- See <https://example.com/docs> for details",
)

check(
    "a feature named Screenshots in a bullet is kept",
    markdown_to_plain_text("### Features\n\n- Screenshots now save faster"),
    "Features\n- Screenshots now save faster",
)

check(
    "other inline formatting tags are removed",
    markdown_to_plain_text("- <u>Under</u> <s>struck</s> <small>tiny</small> <mark>hi</mark>"),
    "- Under struck tiny hi",
)

check(
    "tags outside any known list are removed",
    markdown_to_plain_text("- <section><figure>Fig</figure></section> <dl><dt>t</dt></dl> <blink>b</blink>"),
    "- Fig t b",
)

check(
    "tags inside code spans are kept",
    markdown_to_plain_text("- Wrap it in `<details>` or `<br/>` blocks"),
    "- Wrap it in <details> or <br/> blocks",
)

notes = format_release_notes(fork_body, "Liquid Glass build.")
check("variant label is still prepended", notes.split("\n\n", 1)[0], "Liquid Glass build.")
check("no tags reach the variant notes", re.findall(r"</?[A-Za-z][^<>]*>", notes), [])

if failures:
    print(f"{failures} release-notes check(s) failed")
    sys.exit(1)
print("All release-notes checks passed")
EOF
