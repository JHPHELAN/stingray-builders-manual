# Stormy the Stingray - Builder's Manual

This repository is the canonical documentation set for **Stormy**, a
Raspberry Pi 5 + ROS 2 Jazzy rebuild of the 2010-era Parallax Stingray
robotics platform.

Owner: James H Phelan, MD (Humble, TX).
Status: **Private** — internal use and invited collaborators only for now.

## Contents

| File | Purpose |
| --- | --- |
| [`Stingray_Builders_Manual.txt`](Stingray_Builders_Manual.txt) | Version 1.0 build/rebuild reference. 22 chapters + 7 appendices. If the SD card dies tomorrow, this is how Stormy gets rebuilt. |
| [`Stingray_Field_Notes.txt`](Stingray_Field_Notes.txt) | 103 numbered lessons + indexes distilled from the source log. Cited throughout the Manual by item number. |
| [`Stingray_Curation_Notes.txt`](Stingray_Curation_Notes.txt) | 17 chunks of raw stardated distillate from the source log. Background material for the Manual. |

Read the Manual first. Start at Chapter 0 ("How to use this manual").
Everything else is reference.

## Companion repositories

The Manual references code and configuration living in these repos:

- **Build descriptor:** https://github.com/JHPHELAN/stingray
- **Software (main):** https://github.com/JHPHELAN/articubot_one
    - `jp` branch: main software (fork of slgrobotics's fork of
      Articulated Robotics' `articubot_one`)
    - `exploration` branch: house exploration + mapping code
- **Motor driver:** https://github.com/JHPHELAN/roboclaw_driver
    (fork of wimblerobotics/roboclaw_driver)
- **Dotfiles (private):** https://github.com/JHPHELAN/stingray-dotfiles

The source log (`Stingray Experience.wpd`, 832 pp WordPerfect) is NOT
in this repo. It is the private working diary the Manual and companions
were distilled from.

## Style and format

Plain text throughout. `====` dividers between chapters, `----` between
sections, command blocks indented. No Markdown inside the `.txt` files
themselves so they read cleanly in any terminal or editor.

## License

TBD. Currently all-rights-reserved by the owner. A permissive docs
license (probably CC BY 4.0 or similar) will be chosen before any
public release.

## Version

Manual: 1.0, compiled 2026-07-20, ongoing edits.
Repo: initial commit 2026-08-08.
