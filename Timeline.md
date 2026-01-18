# Project Timeline and Evolution

This timeline exists so future readers (and future me) can see how these projects fit together, what I was trying to solve at each step, and why I changed direction instead of pretending everything was linear and intentional.

---

## 1. [Kali Bitpixie Project][bitpixie] – Targeted Offensive Environment

**Status:** Active concept, patch-style contribution for Kali  
**Files:** `README.md` (Kali Bitpixie)

**What it was**

- A curated Kali package set and chroot/live-build patch aimed at BitLocker/Bitpixie style attacks: firmware analysis, memory forensics, PXE tricks, and recovery-environment abuse. 
- Designed to be submitted as a patch to Kali’s live-build infrastructure to **extend** Kali rather than fork it.

**Why it mattered**

- First serious attempt to design a **minimal, purpose-built offensive environment** rather than just “install Kali and add tools.”  
- Forced explicit thinking about: what belongs in the image, what doesn’t, and how to justify each tool to upstream maintainers.

**What I learned**

- Tooling is the easy part; reasoning and documentation are the hard part.  
- Working *with* Kali’s centralized model is possible, but it doesn’t solve reproducibility or base-system integrity on its own.

---

## 2. [Security-Lab-Infrastructure][sec-lab] – Small-Scale Lab Experiments

**Status:** Archived, superseded  
**Files:** `README.md` (Security-Lab-Infrastructure)

**What it was**

- A grab bag of scripts and configs exploring how to build **small, repeatable security labs** for people without enterprise resources. 
- Focused on local VMs, convenience shell scripts, and early attempts at organizing lab workflows.

**Why it mattered**

- Surface-level goal: make it easier for new Kali users to actually run labs instead of just having tools installed.  
- Deeper goal: start capturing *why* certain choices were made—tool chains, topologies, and workflows.

**What I learned**

- “Just scripts” isn’t enough; without explicit philosophy and constraints, everything turns into unmaintainable glue.  
- This repo became the **exploratory phase** that led directly to more systematic documentation in the next project. 

---

## 3. [Kali-Bootstrap-Project][kali-bootstrap] – Systematic Documentation and Install Logic

**Status:** Superseded for implementation, still valuable as documentation  
**Files:** Long-form `README.md` and docs around Kali install internals

**What it was**

- A deep dive into **Kali/Debian installation internals**: partitioning, crypto, Btrfs, initramfs, and threat modeling. 
- Emphasis on epistemology: no cargo-culting, every decision explained, alternatives documented, and mistakes recorded in `corrections/`.

**Why it mattered**

- Turned “I should automate my Kali install” into a documentation-first project:  
  - Explain *why* before scripting *how*.  
  - Make assumptions explicit.  
  - Treat the base system as something to be understood, not just booted.
  - That even in technical documentation, I swear like a school kid trying to impress his friends.

**What I learned**

- Debian’s installer and ecosystem fight complex, multi-encrypted, non-LVM, Btrfs-heavy layouts.  
- systemd + dracut’s dynamic behavior made deterministic, multi-device boot fragile in ways that documentation alone could not fix. 

---

## 4. Systemd Escape Attempts – Kali → SysV/OpenRC

**Status:** Experiment, not a permanent solution  
**Artifacts:** Notes, partial configs, dpkg surgery patterns (described in docs)

**What it was**

- An attempt to move a Kali CLI system from systemd to sysv/OpenRC to regain **predictable init and mount behavior**.  
- Involved:  
  - `dpkg -r --force-all` to evict systemd components.  
  - Manual installation of alternative init packages.  
  - Wrestling with Debian’s special-cased “virtual dependency” rules and GRUB changes that privilege systemd. 
  
**Why it mattered**

- Demonstrated that the problem was not just configuration, but **ecosystem-level hostility** to alternative inits.  
- Showed how much modern desktop stacks (GNOME, etc.) assume systemd as non-optional.

**What I learned**

- You can bend Kali/Debian away from systemd at the CLI level, but you hit a wall quickly at the desktop and packaging layers.  
- At some point, “fix” becomes “fork or switch base.” This fed directly into the next step.

---

## 5. Devuan Bootstrap – [Quine-Installer][quine] Phase 1

**Status:** Active; current foundation  
**Files:** `Quine-Installer.sh`, `README.md`, `Philosphy.md` 

**What it is**

- A **Devuan-based bootstrap installer** that:  
  - Securely erases disks using appropriate tools.  
  - Sets up multi-device, multi-encrypted Btrfs with explicit subvolume strategies.  
  - Enforces XDG Base Directory semantics with visible, capitalized config/data dirs.  
  - Debootstraps a base system and generates a chroot finishing script.  
  - Copies itself into `/etc/skel` so future users inherit the bootstrap tooling (the “quine” behavior). 

**Why it matters**

- This is the systemd-free, reproducible research base **I wanted Kali to be**, but under a distro that doesn’t fight alternative init and explicit mount/crypto choices. 
- It encodes threat models, drive layouts, and security decisions directly into the script and its documentation.

**What I learned**

- Automation is only worth doing after you’ve fully understood and documented the manual process.  
- Under pressure (housing instability, limited hardware), it is still possible to produce **auditable, reproducible infrastructure**, not just ad-hoc hacks. 

---

## 6. Meta: Use of AI and Documentation Philosophy

Across these phases:

- AI was used as a **research assistant and writing aid**, not a source of truth:  
  - Organizing thoughts, structuring Markdown, maintaining voice.  
  - All technical decisions, tradeoffs, and corrections come from direct experimentation and verification.

- Core principles that emerged and now guide the work:  
  - **No cargo-culting.** Explain why, not just what. 
  - **Epistemological transparency.** Make assumptions and tradeoffs explicit.  
  - **Reproducibility over convenience.** If it can’t be rebuilt and understood, it’s not done.   
  - **No gatekeeping.** Make deep systems work accessible without dumbing it down. 

---

## Why this timeline exists

- For readers: to see how the pieces fit together and decide which layer they care about.  
- For reviewers and hiring managers: to understand that this is not “random tinkering,” but an evolving, coherent attempt to build secure, reproducible systems under real-world constraints.  
- For me: to have a written record that I can point to instead of re-explaining everything from scratch every time.

Sometimes the work looks messy or “cringe” in hindsight. That’s fine. The point is not to hide the path, but to make it visible so others can learn from both the dead ends and the breakthroughs.


## Links
[bitpixie]: https://github.com/howweland/Kali-Bitpixie-Project
[sec-lab]: https://github.com/howweland/Security-Lab-Infrastructure
[kali-bootstrap]: https://github.com/howweland/Kali-Bootstrap-Project
[quine]: https://github.com/howweland/Devuan-Quine-Installer


*This documentation is licensed under [CC-BY-SA-4.0](https://creativecommons.org/licenses/by-sa/4.0/). You are free to remix, correct, and make it your own with attribution.*