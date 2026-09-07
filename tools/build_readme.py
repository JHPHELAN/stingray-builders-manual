#!/usr/bin/env python3
"""Regenerate README.md from Stingray_Builders_Manual.txt.

Stingray_Builders_Manual.txt is the source of truth.  Edit it first,
then run:

    python3 tools/build_readme.py

to regenerate README.md.  No third-party dependencies.

What the script does:
  * Skips the plain-text doc header + table of contents at the top of
    the .txt (regenerated in Markdown below).
  * Converts each divider-wrapped chapter/appendix heading to `##`.
  * Converts each divider-wrapped section heading (`N.M  Title` --
    including Appendix G's `G.N  filename`) to `###`.
  * Emits a linked Markdown TOC using GitHub's auto-slug rules.
  * After each Appendix G `G.N` heading, embeds the referenced image
    inline via `![alt](images/<file>)`.
  * Leaves everything else (prose, indented data blocks, code) alone.
"""

from __future__ import annotations

import re
import urllib.parse
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
TXT = REPO / "Stingray_Builders_Manual.txt"
MD = REPO / "README.md"

# Skip the .txt's own header + plain-text TOC (regenerated below).
# 1-based line 78 is the opening `====` of Chapter 0; index 77 in 0-based.
SKIP_LINES_BEFORE = 77

# GitHub auto-slug (approximation of github-slugger v2):
#   1) lowercase
#   2) drop every char that isn't [a-z0-9_-] or whitespace
#   3) replace each whitespace char with a single '-' (runs are preserved
#      as multi-dashes to match GitHub's behavior)
_SLUG_STRIP = re.compile(r"[^a-z0-9_\-\s]")


def slugify(text: str) -> str:
    s = text.lower()
    s = _SLUG_STRIP.sub("", s)
    s = re.sub(r"\s", "-", s)
    return s


CHAPTER_RE = re.compile(r"^(CHAPTER\s+\d+|APPENDIX\s+[A-Z])\s+-\s+.+$")
# Sections: `N.M  Title`, `G.1  file.png`, or `20.3a  Hank Rearden...`.
SECTION_RE = re.compile(r"^([A-Z0-9]+\.\d+[a-z]?)\s+(.+)$")
# Sub-section labels like `Section A - Weekly backup`, used inside a
# chapter section to organize an alternative-branches recipe.  Emitted
# as H4 (below the H3 section they live under) and kept out of the TOC.
SUBSECTION_RE = re.compile(r"^Section\s+[A-Z]\s+-\s+.+$")
DIVIDER_RE = re.compile(r"^[=\-]{40,}\s*$")


FRONT_MATTER = """\
# Stormy the Stingray - Builder's Manual

Version 1.0 - Compiled 2026-07-20.

If the SD card dies tomorrow, this document is how Stormy gets rebuilt.
Present-tense, imperative, subsystem-oriented.  Every procedure is one
that has been executed successfully on the real robot.

- **Owner:** James H Phelan, MD (Humble, TX).
- **Status:** Private for now; will be made public once presentable.
- **License:** CC BY 4.0 (see [License](#license) at the bottom).

## Companion files in this repo

| File | Purpose |
| --- | --- |
| [`Stingray_Builders_Manual.txt`](Stingray_Builders_Manual.txt) | **Source of truth.** Plain-text master copy of this document.  All edits go here first; `README.md` is regenerated from it (see [Regenerating this README](#regenerating-this-readme)). |
| [`Stingray_Field_Notes.txt`](Stingray_Field_Notes.txt) | 104 numbered lessons + indexes distilled from the source log.  Cited throughout the Manual by item number. |
| [`Stingray_Curation_Notes.txt`](Stingray_Curation_Notes.txt) | 17 chunks of raw stardated distillate from the source log.  Background material for the Manual. |
| [`kicad/Stingray/`](kicad/Stingray/) | KiCad 10.0 project - schematic, custom symbol library, PCB stub.  Source for Appendix [G.9](#g9--stormy-schematic-2026-08-12png). |
| [`images/`](images/) | Diagrams and photos catalogued in [Appendix G](#appendix-g---diagrams-and-photos). |
| [`tools/build_readme.py`](tools/build_readme.py) | Regenerates this `README.md` from the `.txt`. |
| [`LICENSE`](LICENSE) | CC BY 4.0 legal text. |

The source log (`Stingray Experience.wpd`, 832 pp WordPerfect) is
**not** in this repo -- it is the private working diary this Manual
and the two companion `.txt` files were distilled from.

## Companion repositories

The Manual references code and configuration living in these repos:

- **Build descriptor:** <https://github.com/JHPHELAN/stingray>
- **Software (main):** <https://github.com/JHPHELAN/articubot_one>
    - `jp` branch -- main software (fork of slgrobotics's fork of
      Articulated Robotics' `articubot_one`)
    - `exploration` branch -- house exploration + mapping code
      (currently running on Stormy; not yet merged to `jp`)
- **Motor driver:** <https://github.com/JHPHELAN/roboclaw_driver>
    (fork of wimblerobotics/roboclaw_driver)
- **Dotfiles (private):** <https://github.com/JHPHELAN/stingray-dotfiles>

## Regenerating this README

`Stingray_Builders_Manual.txt` is the source of truth.  `README.md`
is mechanically generated from it by
[`tools/build_readme.py`](tools/build_readme.py).  To port a `.txt`
edit into the rendered manual:

```bash
python3 tools/build_readme.py
```

Then commit both files together.

"""


FOOTER_LICENSE = """\

---

## License

Licensed under the **Creative Commons Attribution 4.0 International
License** (CC BY 4.0).  See [`LICENSE`](LICENSE) for the full text, or
<https://creativecommons.org/licenses/by/4.0/> for the human-readable
summary.

Attribution: James H Phelan, MD, *Stormy the Stingray - Builder's
Manual*, <https://github.com/JHPHELAN/stingray-builders-manual>.
"""


def convert_body(body_lines: list[str]) -> tuple[list[str], list[tuple[int, str, str]]]:
    """Walk the body and rewrite headings.  Returns (out_lines, toc)."""
    out: list[str] = []
    toc: list[tuple[int, str, str]] = []  # (level, text, slug)
    i = 0
    n = len(body_lines)
    while i < n:
        line = body_lines[i].rstrip()

        # Chapter / Appendix heading: divider, TEXT, divider
        if (
            DIVIDER_RE.match(line)
            and i + 2 < n
            and CHAPTER_RE.match(body_lines[i + 1].strip())
            and DIVIDER_RE.match(body_lines[i + 2].strip())
        ):
            heading_text = body_lines[i + 1].strip()
            slug = slugify(heading_text)
            toc.append((2, heading_text, slug))
            if out and out[-1] != "":
                out.append("")
            out.append(f"## {heading_text}")
            out.append("")
            i += 3
            continue

        # Section heading: divider, N.M or G.N text, divider
        if (
            DIVIDER_RE.match(line)
            and i + 2 < n
            and SECTION_RE.match(body_lines[i + 1].strip())
            and DIVIDER_RE.match(body_lines[i + 2].strip())
        ):
            heading_text = body_lines[i + 1].strip()
            slug = slugify(heading_text)
            toc.append((3, heading_text, slug))
            if out and out[-1] != "":
                out.append("")
            out.append(f"### {heading_text}")
            out.append("")
            m = SECTION_RE.match(heading_text)
            if m and m.group(1).startswith("G."):
                fname = m.group(2).strip()
                url = "images/" + urllib.parse.quote(fname)
                out.append(f"![{fname}]({url})")
                out.append("")
            i += 3
            continue

        # Sub-section heading: divider, `Section X - ...`, divider.
        # Emit as H4 and skip the TOC.
        if (
            DIVIDER_RE.match(line)
            and i + 2 < n
            and SUBSECTION_RE.match(body_lines[i + 1].strip())
            and DIVIDER_RE.match(body_lines[i + 2].strip())
        ):
            heading_text = body_lines[i + 1].strip()
            if out and out[-1] != "":
                out.append("")
            out.append(f"#### {heading_text}")
            out.append("")
            i += 3
            continue

        # Divider-wrapped text that isn't a chapter or section (e.g., the
        # `END OF STORMY THE STINGRAY - BUILDER'S MANUAL` colophon).
        # Emit as a plain level-2 heading; do NOT add to the TOC.
        if (
            DIVIDER_RE.match(line)
            and i + 2 < n
            and body_lines[i + 1].strip()
            and DIVIDER_RE.match(body_lines[i + 2].strip())
        ):
            heading_text = body_lines[i + 1].strip()
            if out and out[-1] != "":
                out.append("")
            out.append(f"## {heading_text}")
            out.append("")
            i += 3
            continue

        # Drop any orphan divider lines (trailing `====` at the very end,
        # etc.).  Setext-heading behavior of a bare `----` under a text
        # line would otherwise silently promote that text to an H2.
        if DIVIDER_RE.match(line):
            i += 1
            continue

        out.append(line)
        i += 1

    # Trim trailing blank lines
    while out and out[-1] == "":
        out.pop()
    return out, toc


def build_toc(toc: list[tuple[int, str, str]]) -> str:
    lines = ["## Table of contents", ""]
    for level, text, slug in toc:
        indent = "" if level == 2 else "  "
        lines.append(f"{indent}- [{text}](#{slug})")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    raw = TXT.read_text(encoding="utf-8", errors="strict").splitlines()
    body_lines = raw[SKIP_LINES_BEFORE:]
    body_out, toc = convert_body(body_lines)

    parts = [
        FRONT_MATTER,
        build_toc(toc),
        "",
        "\n".join(body_out),
        "",
        FOOTER_LICENSE,
    ]
    with open(MD, "w", encoding="utf-8", newline="\n") as fh:
        fh.write("\n".join(parts))
    size = MD.stat().st_size
    print(f"wrote {MD.name} ({size:,} bytes, {len(toc)} TOC entries)")


if __name__ == "__main__":
    main()
