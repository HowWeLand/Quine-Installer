#!/bin/bash
# phase1-automated-install-updated.sh
# Devuan Bootstrap: Phase 1 - Destructive Operations to Bootable System
#
# ═══════════════════════════════════════════════════════════════════════════
# THE QUINE PROTOCOL: SELF-REPLICATING INSTALLATION AUTOMATION
# ═══════════════════════════════════════════════════════════════════════════
#
# "A quine is a non-empty computer program which takes no input and produces 
#  a copy of its own source code as its only output."
#
# While not a true quine (it doesn't print itself to stdout), this script 
# achieves something more useful: it copies itself into the target system's
# skeleton directory, ensuring every user created has access to the bootstrap
# tooling that created the system. The installation becomes self-documenting
# and self-replicating.
#
# PHILOSOPHY:
#   - Systems should be reproducible
#   - Configuration should be transparent
#   - Automation should be auditable
#   - The bootstrap process should survive into the installed system
#
# ═══════════════════════════════════════════════════════════════════════════
# WARNING: THIS SCRIPT DESTROYS DATA
# ═══════════════════════════════════════════════════════════════════════════
#
# This script performs DESTRUCTIVE operations:
#   - Secure erase of entire drives (cryptographic or physical)
#   - Creation of new partition tables (GPT)
#   - Formatting of filesystems
#   - LUKS encryption of partitions
#
# There is NO UNDO. Backup critical data before running.
#
# ═══════════════════════════════════════════════════════════════════════════
# PRE-FLIGHT CHECKLIST
# ═══════════════════════════════════════════════════════════════════════════
#
# 1. Boot from Devuan Live USB (or any Debian-based live environment)
# 2. Connect to network (for debootstrap package downloads)
# 3. Run `lsblk -o NAME,SIZE,MODEL,SERIAL` to identify your drives
# 4. Edit the CONFIGURATION VARIABLES section below
# 5. Triple-check drive paths (wrong path = destroyed data)
# 6. Ensure you have a spare USB drive for the LUKS keyfile
# 7. Read this entire header before proceeding
#
# ═══════════════════════════════════════════════════════════════════════════
# WHAT THIS SCRIPT DOES
# ═══════════════════════════════════════════════════════════════════════════
#
# Phase 1 (This Script - Runs on Live USB):
#   1.1 - Secure Erase: Cryptographic wipe of NVMe, ATA wipe of SATA
#   1.2 - Partitioning: GPT tables, EFI/boot/encrypted partitions
#   1.3 - Encryption: LUKS2 with USB keyfile, Argon2id KDF
#   1.4 - Filesystems: BTRFS with compression, subvolume strategy
#   1.5 - Bootstrap: Debootstrap Devuan base system
#   1.6 - Configuration: fstab, crypttab, apt sources, GRUB prep
#
# Phase 2 (Generated Script - Runs in Chroot):
#   2.1 - Locale/Timezone: Generate locales, set timezone
#   2.2 - Packages: Kernel, firmware, bootloader, desktop environment
#   2.3 - Users: Create user account, configure sudo
#   2.4 - Bootloader: Install GRUB to EFI, generate config
#   2.5 - Initramfs: Embed USB drivers and cryptsetup
#   2.6 - Services: Configure SysVinit services
#
# ═══════════════════════════════════════════════════════════════════════════
# ARCHITECTURE OVERVIEW
# ═══════════════════════════════════════════════════════════════════════════
#
# Drive Layout:
#   /dev/nvme0n1 (Fast NVMe - System)
#     ├─ p1: 512M   EFI System Partition (FAT32)
#     ├─ p2: 10G    /boot (ext4, unencrypted for GRUB)
#     └─ p3: Rest   LUKS2 → BTRFS (root filesystem + subvolumes)
#
#   /dev/sda (SATA SSD - User Data)
#     └─ p1: All    LUKS2 → BTRFS (/home + VM/container storage)
#
#   /dev/sdc (USB Drive - Boot Key)
#     └─ p1: All    ext4 with /keyfile (4096 bytes random data)
#
# BTRFS Subvolume Strategy:
#   Root Drive (@subvol):
#     @ (/)                    - Root filesystem (CoW + compression)
#     @opt (/opt)              - Optional packages (CoW + compression)
#     @srv (/srv)              - Server data (CoW + compression)
#     @usr@local (/usr/local)  - Local binaries (CoW + compression)
#     @var@log (/var/log)      - System logs (CoW + compression)
#     @var@cache (/var/cache)  - Package cache (nodatacow, performance)
#     @var@tmp (/var/tmp)      - Temp files (nodatacow, performance)
#     @swap (/swap)            - Swap container (nodatacow, optional)
#
#   Home Drive (@subvol):
#     @home (/home)            - User home directories (CoW + compression)
#     @var@lib@libvirt@images  - VM disk images (nodatacow, performance)
#     @var@lib@containers      - Container storage (nodatacow, performance)
#
# Subvolume Naming Convention:
#   - '@' prefix identifies BTRFS subvolumes
#   - '@' alone is root subvolume
#   - Path separators '/' become '@' (/@var/log → @var@log)
#   - This prevents mount path conflicts and enables clean snapshots
#
# Why BTRFS?
#   - Subvolumes allow independent mount options per directory
#   - Transparent compression saves disk space
#   - CoW enables instant snapshots for backups
#   - nodatacow for databases/VMs prevents fragmentation
#   - Built-in checksumming detects silent data corruption
#
# Why Separate Drives?
#   - Fast NVMe for system (IOPS-heavy workloads)
#   - Large SATA for data (capacity over speed)
#   - Failure isolation (system crash ≠ data loss)
#   - Independent encryption (home remains locked if system compromised)
#
# ═══════════════════════════════════════════════════════════════════════════
# SECURITY MODEL
# ═══════════════════════════════════════════════════════════════════════════
#
# Threat Model:
#   - Physical theft of laptop
#   - Forensic analysis of drives
#   - Evil maid attacks (limited mitigation)
#   - Cold boot attacks (not mitigated - use secure boot for that)
#
# Mitigations:
#   1. Full-disk encryption (LUKS2) on all partitions except /boot
#   2. USB keyfile required to boot (not just a passphrase)
#   3. Argon2id KDF with 4-second iteration time (anti-bruteforce)
#   4. AES-XTS-PLAIN64 cipher with 512-bit keys
#   5. Separate encrypted home drive (defense in depth)
#   6. Optional backup passphrase (stored in LUKS header, not on USB)
#
# Attack Vectors:
#   - /boot is unencrypted (required for GRUB to load kernel)
#     - Mitigation: Use secure boot + signed kernels (not implemented here)
#   - USB keyfile is single point of failure
#     - Mitigation: Add backup passphrase after installation
#   - Cold boot attacks can extract keys from RAM
#     - Mitigation: Requires secure boot + measured boot (complex)
#
# Key Management:
#   - USB keyfile is 4096 bytes of /dev/urandom
#   - Created with umask 077 (no race condition, permissions correct at birth)
#   - USB drive is ext4 (reliable, universally supported)
#   - Keyfile path: /keyfile (root of USB filesystem)
#   - LUKS header stores encrypted master key (decrypted by USB keyfile)
#   - Master key never leaves encrypted volume
#
# Boot Process:
#   1. UEFI loads GRUB from unencrypted /boot/efi
#   2. GRUB loads kernel + initramfs from unencrypted /boot
#   3. Initramfs detects USB drive by partition label
#   4. cryptsetup reads keyfile from USB, unlocks root partition
#   5. cryptsetup reads same keyfile, unlocks home partition
#   6. System mounts BTRFS subvolumes, continues boot
#   7. User removes USB keyfile after boot (optional security measure)
#
# ═══════════════════════════════════════════════════════════════════════════
# XDG BASE DIRECTORY SPECIFICATION ENFORCEMENT
# ═══════════════════════════════════════════════════════════════════════════
#
# The Problem:
#   By default, Unix systems pollute $HOME with hundreds of dotfiles.
#   ~/.config, ~/.cache, ~/.local, ~/.zshrc, ~/.bashrc, ~/.vimrc, etc.
#   This is a mess. The XDG Base Directory spec provides a solution, but
#   most distros don't enforce it. We do.
#
# Our Solution:
#   Force ALL configuration into visible, capitalized directories:
#     $HOME/Config  (XDG_CONFIG_HOME) - Application configuration
#     $HOME/Data    (XDG_DATA_HOME)   - Application data
#     $HOME/State   (XDG_STATE_HOME)  - Logs, history, recently-used
#     $HOME/Cache   (XDG_CACHE_HOME)  - Temporary cache files
#
# Why Capitalized?
#   - Visible at a glance (no hidden dotfiles)
#   - Sorts to top in ls output
#   - Clear distinction from system directories
#   - Easier to backup (just tar Config/ and Data/)
#
# Enforcement Strategy (Multi-Layer Defense):
#   Layer 1: /etc/profile.d/00-xdg-custom.sh
#     - Sets XDG_* for ALL shells at login
#     - Runs before user shell config
#   Layer 2: /etc/zsh/zshenv
#     - Forces ZDOTDIR for zsh config location
#     - Sourced by ALL zsh instances (even non-interactive)
#   Layer 3: /etc/bash.bashrc
#     - Sets XDG_* for bash users
#     - Includes HISTFILE redirect
#   Layer 4: /etc/skel/
#     - Pre-creates Config/, Data/, State/, Cache/ for new users
#     - Includes pre-configured zsh config in $HOME/Config/zsh/
#
# Why This Works:
#   - Applications that respect XDG automatically use our directories
#   - Applications that don't (looking at you, vim) can be aliased
#   - New users get the correct structure from /etc/skel/
#   - Existing dotfiles won't break things (XDG is additive)
#
# ═══════════════════════════════════════════════════════════════════════════
# ZSH CONFIGURATION PHILOSOPHY
# ═══════════════════════════════════════════════════════════════════════════
#
# Design Goals:
#   1. Modular - Each feature in its own file
#   2. Portable - Works across distros and systems
#   3. Fast - Lazy loading, minimal startup time
#   4. Maintainable - Clear structure, easy to extend
#   5. XDG-compliant - All config in $XDG_CONFIG_HOME/zsh/
#
# Directory Structure:
#   $HOME/Config/zsh/
#     ├── .zshrc                 - Main config (sources everything else)
#     ├── env/                   - Environment variables (per-language)
#     │   ├── rust.zsh           - CARGO_HOME, RUSTUP_HOME
#     │   ├── python.zsh         - PIPX, PYENV, VIRTUAL_ENV
#     │   ├── go.zsh             - GOPATH
#     │   ├── java.zsh           - SDKMAN
#     │   └── javascript.zsh     - NVM, NPM_CONFIG_PREFIX
#     ├── aliases/               - Command aliases (by category)
#     │   ├── core.zsh           - cp, mv, rm, ls
#     │   ├── apt.zsh            - Package management shortcuts
#     │   ├── gpg.zsh            - GPG key management
#     │   └── xdg-fixes.zsh      - Force apps to use XDG paths
#     ├── functions/             - Shell functions (complex logic)
#     │   ├── admin_tools.zsh    - upgrayyedd, gpg-copy-pub
#     │   └── tagging.zsh        - Aptitude tag helpers
#     ├── completions/           - Custom completion scripts
#     ├── plugins/               - Third-party plugins (git clones)
#     └── local/                 - Machine-specific overrides
#
# Loading Order:
#   1. /etc/zsh/zshenv         - System-wide XDG variables (always)
#   2. ~/.zshrc                - User config (sources everything below)
#   3. env/*.zsh               - Environment setup (PATH, language tools)
#   4. aliases/*.zsh           - Command aliases
#   5. functions/*.zsh         - Shell functions
#   6. completions/*.zsh       - Completion scripts
#   7. plugins/*.zsh           - Third-party plugins
#   8. local/*.zsh             - Machine-specific overrides (gitignored)
#
# Why This Structure?
#   - Each file has one job (single responsibility principle)
#   - Easy to enable/disable features (just delete/rename file)
#   - Conflicts are impossible (no monolithic .zshrc)
#   - Git-friendly (each feature in separate commits)
#   - Portable (copy env/python.zsh to new system, done)
#
# Plugin Management:
#   - No oh-my-zsh (bloated, slow, opinionated)
#   - Manual git clones into plugins/ directory
#   - Load only what you need (syntax highlighting, autosuggestions)
#   - Graceful degradation if plugins missing
#
# Performance:
#   - zcompdump cached in $XDG_CACHE_HOME/zsh/
#   - Only regenerated if >24h old
#   - Plugins loaded last (after core functionality works)
#   - No expensive operations in .zshrc (put in env/ files)
#
# ═══════════════════════════════════════════════════════════════════════════
# DESKTOP ENVIRONMENT STRATEGY
# ═══════════════════════════════════════════════════════════════════════════
#
# Choice: XFCE4 (The Pragmatist's Desktop)
#
# Why XFCE?
#   - Lightweight (500MB RAM idle)
#   - Stable (no Wayland drama, no GNOME breakage)
#   - Customizable (GTK3, traditional menus, compositing optional)
#   - Sysvinit-friendly (no hard systemd dependencies)
#   - X11-based (remote desktop, VNC, screen sharing just work)
#
# Display Manager: LightDM
#   - Lightweight (not GDM's 200MB monster)
#   - GTK greeter (themeable, consistent with XFCE)
#   - Works without systemd (elogind support)
#   - Multi-seat capable (if you're into that)
#
# Theme Strategy: Dark Mode Enforcement
#   - Arc-Dark GTK theme (dark windows, light text)
#   - Papirus-Dark icon theme (modern, complete coverage)
#   - Configured system-wide (new users get dark mode by default)
#   - Two configuration points:
#       1. LightDM greeter (/etc/lightdm/lightdm-gtk-greeter.conf)
#       2. XFCE defaults (/etc/xdg/xfce4/xfconf/xfce-perchannel-xml/)
#
# Terminal: XFCE Terminal with Cyberpunk HUD Theme
#   - Font: Hack Nerd Font (ligatures, powerline symbols)
#   - Colors: Black background, white text, red cursor
#   - Cursor: Block, no blink (because we're not animals)
#   - UI: No scrollbar, no menubar, no toolbar (zero bloat)
#
# Why Not Wayland?
#   - Nvidia proprietary drivers (X11 is more stable)
#   - Remote desktop (X11 forwarding over SSH just works)
#   - Screen recording (no portal permission nightmares)
#   - Mature ecosystem (20 years of X11 tools don't need rewriting)
#   - We can always migrate later (but why?)
#
# ═══════════════════════════════════════════════════════════════════════════
# NVIDIA PROPRIETARY DRIVER STRATEGY
# ═══════════════════════════════════════════════════════════════════════════
#
# The Problem:
#   Nvidia's proprietary driver is a fragile, closed-source kernel module.
#   It conflicts with nouveau (open-source driver) and has broken postinst
#   scripts that fail dpkg operations. We work around this.
#
# The Solution:
#   1. Blacklist nouveau kernel module (prevent conflicts)
#   2. Install nvidia-driver package (allows failure)
#   3. Stub out nvidia-persistenced.postinst (force dpkg to proceed)
#   4. Run dpkg --configure -a (clear any package locks)
#
# Why This Works:
#   - nvidia-persistenced is not critical for desktop use
#   - Stubbing postinst allows dpkg to mark package as configured
#   - Real nvidia drivers still load correctly at boot
#   - We can reconfigure later if needed
#
# Alternatives Considered:
#   - Nouveau (open source, but 1/10th the performance)
#   - Nvidia beta drivers (even more unstable)
#   - Not installing Nvidia drivers (defeats the purpose of having GPU)
#
# Known Issues:
#   - Suspend/resume unreliable (Nvidia bug, not our problem)
#   - Wayland doesn't work well (use X11)
#   - CUDA/OpenCL may need additional setup
#
# ═══════════════════════════════════════════════════════════════════════════
# REFRACTA SNAPSHOT: THE QUINE TOOLING
# ═══════════════════════════════════════════════════════════════════════════
#
# What is Refracta?
#   Refracta Snapshot creates bootable live ISOs from your running system.
#   It's like Clonezilla, but for entire OS configurations.
#
# Why Include It?
#   - System becomes self-replicating (install once, clone forever)
#   - Live USB for system recovery (boot from ISO, mount encrypted drives)
#   - Deployment tool (create custom Devuan respins)
#   - Backup strategy (ISO snapshot = bootable backup)
#
# The Quine Connection:
#   - This bootstrap script copies itself into /etc/skel/
#   - New users get the script in ~/bin/scripts/
#   - Users can create snapshot ISOs containing the bootstrap script
#   - Booting the snapshot ISO lets you run bootstrap script again
#   - Result: The system can recreate itself infinitely
#
# Configuration:
#   - /etc/refractasnapshot.conf defines snapshot behavior
#   - Snapshot filename matches hostname (tracking which system created it)
#   - Excludes are minimal (we want full system captured)
#
# Workflow:
#   1. Install and configure system (this script)
#   2. Customize to your liking (dotfiles, packages, etc.)
#   3. Run refractasnapshot-gui
#   4. Create ISO (writes to ~/snapshots/)
#   5. Burn ISO to USB (dd or Etcher)
#   6. Boot USB on new hardware
#   7. Run bootstrap script from USB
#   8. Repeat ad infinitum
#
# ═══════════════════════════════════════════════════════════════════════════
# ERROR HANDLING PHILOSOPHY
# ═══════════════════════════════════════════════════════════════════════════
#
# Bash Error Handling:
#   set -e  : Exit immediately if any command fails (non-zero exit code)
#   set -u  : Exit if trying to use undefined variable
#   set -o pipefail : Fail if any command in pipeline fails
#
# Why This Matters:
#   Without 'set -e', failed commands are silently ignored.
#   Example: mkfs.ext4 fails, but script continues to mount nothing.
#   Result: Corrupted installation, wasted hours debugging.
#
# Exception Handling:
#   Some commands are EXPECTED to fail:
#     - `command || true` (ignore failure, continue)
#     - `command || log_warning "Expected failure"` (log but continue)
#     - `command || die "Critical failure"` (log and exit)
#
# Logging Strategy:
#   - Color-coded output (blue=info, green=success, yellow=warning, red=error)
#   - log_info: Informational messages (progress updates)
#   - log_success: Operation completed successfully
#   - log_warning: Non-fatal issue (script continues)
#   - log_error: Fatal issue (script will exit)
#   - die: Log error and exit immediately (critical failures)
#
# Safety Checks:
#   - require_root: Must run as root (need permissions)
#   - require_live_environment: Must run from live USB (not installed system)
#   - verify_drive_exists: Drive must exist before operations
#   - confirm_drives_unmounted: Drives must be unmounted before erase
#   - interactive_confirmation: Final "are you sure?" before destruction
#
# Dependency Checking:
#   - Critical dependencies: Script cannot run without them (exit if missing)
#   - Optional dependencies: Script degrades gracefully (warn if missing)
#   - Example: nvme-cli is optional (secure erase falls back to wipefs)
#
# ═══════════════════════════════════════════════════════════════════════════
# FUTURE IMPROVEMENTS (The Roadmap)
# ═══════════════════════════════════════════════════════════════════════════
#
# TODO: Modularization
#   - Extract config into YAML/TOML file (like Ansible/Puppet)
#   - Separate drive config, package lists, user settings
#   - Allow multiple profiles (laptop, desktop, server)
#
# TODO: Idempotency
#   - Check if partitions already exist (resume from failure)
#   - Skip secure erase if already done (save time)
#   - Support incremental runs (change config, re-run safely)
#
# TODO: Dry-Run Mode
#   - `--dry-run` flag to show what would happen
#   - Print commands without executing them
#   - Verify config without destructive operations
#
# TODO: Logging to File
#   - Redirect all output to /var/log/bootstrap.log
#   - Timestamp every operation (audit trail)
#   - Separate error log for failures
#
# TODO: Pre-flight Verification
#   - Check USB drive GUID before erase (prevent wrong drive)
#   - Verify network connectivity (debootstrap needs internet)
#   - Check available disk space (ensure enough for bootstrap)
#   - Validate config before starting (catch typos early)
#
# TODO: Secure Boot Support
#   - Sign kernel and bootloader (prevent evil maid attacks)
#   - Enroll MOK keys (Machine Owner Keys)
#   - Verify boot chain integrity
#
# TODO: Backup Integration
#   - Automatic first snapshot after install
#   - Schedule weekly snapshots (cron job)
#   - Incremental backups to external drive
#
# TODO: Network Install
#   - PXE boot support (network-based bootstrap)
#   - Preseed config file (fully automated install)
#   - Remote deployment (install on headless servers)
#
# ═══════════════════════════════════════════════════════════════════════════
# BEGIN SCRIPT EXECUTION
# ═══════════════════════════════════════════════════════════════════════════

# Bash strict mode: exit on error, undefined variables, pipe failures
# This is the foundation of reliable automation. Without these flags,
# bash will happily continue after failures, leading to subtle corruption.
set -euo pipefail

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

# generate_hostname: Create random hostname with prefix
#
# Usage: generate_hostname [prefix] [min] [max]
# Example: generate_hostname "laptop" 10000 99999
# Output: laptop-42719
#
# Why? Hostname uniqueness for tracking systems in Refracta snapshots.
# Each installed system gets a unique identifier for management.
generate_hostname() {
    local prefix=${1:-laptop}
    local min=${2:-10000}
    local max=${3:-99999}
    local random_num=$(shuf -i ${min}-${max} -n 1)
    echo "${prefix}-${random_num}"
}

#==============================================================================
# CONFIGURATION VARIABLES - EDIT THESE BEFORE RUNNING
#==============================================================================
#
# This is the "Mad Libs" section. Fill in the blanks before running.
# In a future version, this will be an external config file (YAML/TOML).
#
# CRITICAL: Run `lsblk -o NAME,SIZE,MODEL,SERIAL` first!
# Wrong drive paths = permanent data loss. No recovery. No exceptions.
#==============================================================================

# ──────────────────────────────────────────────────────────────────────────
# DRIVE CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────
# YOU MUST RUN `lsblk` FIRST AND SET THESE CORRECTLY
# Wrong values = destroyed wrong drive = data loss
#
# Drive Identification:
#   - NVMe: Usually /dev/nvme0n1 or /dev/nvme1n1
#   - SATA: Usually /dev/sda or /dev/sdb  
#   - USB: Usually /dev/sdb or /dev/sdc (check lsblk!)
#
# Partitions are auto-created as:
#   - NVMe: nvme0n1p1, nvme0n1p2, nvme0n1p3
#   - SATA: sda1
#   - USB: sdc1

NVME_DRIVE="/dev/nvme0n1"  # Fast system drive (root filesystem)
SATA_DRIVE="/dev/sda"      # Large data drive (home filesystem)
USB_DRIVE="/dev/sdb"       # Boot keyfile drive (LUKS unlock key)

# USB keyfile path (relative to USB mount point)
# The keyfile will be created at: /mount/point/keyfile
USB_KEYFILE_PATH="/keyfile"

# ──────────────────────────────────────────────────────────────────────────
# PARTITION SIZES
# ──────────────────────────────────────────────────────────────────────────
# EFI: 512M is standard (100M minimum, 512M allows for multiple bootloaders)
# Boot: 10G allows storing a custom live ISO for system recovery
#       (Standard /boot is 512M-1G, we're being generous)
# Root: Remaining space on NVMe (auto-calculated)
# Home: Remaining space on SATA (auto-calculated)

EFI_SIZE="512M"   # EFI System Partition (FAT32, UEFI boot files)
BOOT_SIZE="10G"   # Boot partition (ext4, kernel + initramfs + custom ISOs)

# ──────────────────────────────────────────────────────────────────────────
# LUKS ENCRYPTION SETTINGS
# ──────────────────────────────────────────────────────────────────────────
# These are cryptographically sound defaults. Don't change unless you know
# what you're doing and have read the cryptsetup documentation.
#
# Cipher: AES-XTS-PLAIN64
#   - AES: Advanced Encryption Standard (FIPS 140-2 approved)
#   - XTS: XEX-based tweaked-codebook mode (prevents pattern analysis)
#   - PLAIN64: 64-bit sector numbering (supports large drives)
#
# Key Size: 512 bits
#   - XTS splits key in half (256-bit AES key + 256-bit tweak key)
#   - Effectively 256-bit AES (still overkill for current hardware)
#
# Hash: SHA-256
#   - Used for key derivation (password → encryption key)
#   - SHA-256 is standard, SHA-512 offers no practical benefit
#
# PBKDF: Argon2id
#   - Password-Based Key Derivation Function
#   - Argon2id resists GPU/ASIC attacks (memory-hard algorithm)
#   - Better than PBKDF2, bcrypt, or scrypt
#
# Iteration Time: 4000ms (4 seconds)
#   - Time to derive key from password/keyfile
#   - Higher = slower unlocking, more bruteforce resistance
#   - 4s is balance (1s minimum for security, 10s+ annoying)
#   - Only matters if attacker has keyfile (you protect USB, right?)

LUKS_CIPHER="aes-xts-plain64"
LUKS_KEY_SIZE="512"
LUKS_HASH="sha256"
LUKS_PBKDF="argon2id"
LUKS_ITER_TIME="4000"  # milliseconds (4 seconds)

# ──────────────────────────────────────────────────────────────────────────
# PARTITION LABELS
# ──────────────────────────────────────────────────────────────────────────
# GPT partition labels (metadata in partition table)
# Used for referencing partitions via /dev/disk/by-partlabel/
#
# Why labels instead of UUIDs?
#   - UUIDs are random, labels are human-readable
#   - Labels persist across reformats (if you reuse the label)
#   - Easier to script (no need to query blkid)
#
# These labels are used in:
#   - fstab (mounting filesystems)
#   - crypttab (unlocking encrypted partitions)
#   - GRUB config (finding kernel)

PARTLABEL_EFI="ESP"             # EFI System Partition (standard name)
PARTLABEL_BOOT="boot"           # Boot partition (kernel, initramfs)
PARTLABEL_CRYPTROOT="cryptroot" # Encrypted root container
PARTLABEL_CRYPTHOME="crypthome" # Encrypted home container
PARTLABEL_USB="bootkey"         # USB keyfile partition

# ──────────────────────────────────────────────────────────────────────────
# CRYPT DEVICE MAPPER NAMES
# ──────────────────────────────────────────────────────────────────────────
# When LUKS volumes are unlocked, they appear as /dev/mapper/<name>
# These names must match between crypttab and fstab.
#
# Example:
#   cryptsetup open /dev/nvme0n1p3 cryptroot
#   # Creates /dev/mapper/cryptroot
#   mount /dev/mapper/cryptroot /mnt
#
# Keep these consistent with crypttab entries!

CRYPT_ROOT_NAME="cryptroot"  # Unlocked root device (/dev/mapper/cryptroot)
CRYPT_HOME_NAME="crypthome"  # Unlocked home device (/dev/mapper/crypthome)

# ──────────────────────────────────────────────────────────────────────────
# SYSTEM CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────

# Hostname Configuration
# Uncomment ONE of these options:

# Option 1: Random hostname with default prefix/range
# HOSTNAME=$(generate_hostname "laptop")

# Option 2: Random hostname with custom prefix/range  
# HOSTNAME=$(generate_hostname "devuan" 10000 99999)

# Option 3: Manual hostname (default)
HOSTNAME="laptop-demo"

# Timezone: Your local timezone
# List available: `ls /usr/share/zoneinfo/`
# Examples: America/New_York, Europe/London, Asia/Tokyo
TIMEZONE="America/Chicago"

# Locale: Your system language/encoding
# List available: `cat /usr/share/i18n/SUPPORTED`
# Format: language_COUNTRY.ENCODING
# Always use UTF-8 encoding (it's 2024, not 1984)
LOCALE="en_US.UTF-8"

# ──────────────────────────────────────────────────────────────────────────
# DEVUAN REPOSITORY CONFIGURATION  
# ──────────────────────────────────────────────────────────────────────────
# Devuan Mirrors:
#   - deb.devuan.org/merged: Official CDN (recommended)
#   - pkgmaster.devuan.org/merged: Primary mirror
#   - auto.mirror.devuan.org/merged: Automatic mirror selection
#
# Devuan Suites:
#   - excalibur: Stable (Debian 12 "Bookworm" base)
#   - freia: Testing (Debian 13 "Trixie" base)  
#   - ceres: Unstable (Debian "Sid" base)
#
# Choose based on stability vs freshness:
#   - excalibur: Rock-solid, older packages, security updates
#   - freia: Newer packages, occasional breakage, rolling updates
#   - ceres: Bleeding edge, breaks often, for developers/masochists

DEVUAN_MIRROR="http://deb.devuan.org/merged"
DEVUAN_SUITE="freia"  # Options: excalibur, freia, ceres

# Alternative mirrors (if primary is slow/down):
# DEVUAN_MIRROR="http://pkgmaster.devuan.org/merged"
# DEVUAN_MIRROR="http://auto.mirror.devuan.org/merged"

# ──────────────────────────────────────────────────────────────────────────
# BOOTSTRAP PATHS
# ──────────────────────────────────────────────────────────────────────────

CHROOT_TARGET="/mnt"  # Where to mount target system during bootstrap
SKEL="/etc/skel"      # Skeleton directory (template for new users)

# ──────────────────────────────────────────────────────────────────────────
# USER CONFIGURATION
# ──────────────────────────────────────────────────────────────────────────
# User Account Settings:
#   WHO_IS_THIS: Username (lowercase, no spaces, 3-32 chars)
#   WHERE_YOU_BELONG: Groups (comma-separated, no spaces)
#   WHAT_YOU_USE: Login shell (full path)
#
# Important Groups:
#   - sudo: Superuser privileges (via sudo command)
#   - video: Access to GPU (required for X11/Wayland)
#   - render: Access to GPU rendering nodes (Vulkan, OpenGL)
#   - audio: Access to sound devices
#   - input: Access to input devices (mice, keyboards)
#   - plugdev: Access to removable devices (USB drives)
#   - netdev: Manage network devices (NetworkManager)
#   - kvm: Hardware virtualization (QEMU/KVM)
#   - libvirt: Manage VMs (libvirt/virt-manager)
#   - dialout: Access to serial ports (Arduino, etc.)
#   - dip: Dial-up networking (legacy, rarely needed)
#   - bluetooth: Manage Bluetooth devices

WHO_IS_THIS="user-demo"                # Username for primary user account
WHERE_YOU_BELONG="sudo,video,render,audio,input,plugdev,netdev,kvm,libvirt,dialout,dip,bluetooth"
WHAT_YOU_USE="/usr/bin/zsh"            # Login shell (zsh required for our config)

# ──────────────────────────────────────────────────────────────────────────
# CONFIG FILE REFERENCES (Not used in current version)
# ──────────────────────────────────────────────────────────────────────────
# These were placeholders for external config files. Currently unused
# because we generate fstab/crypttab dynamically. Kept for future use.

FSTAB_CONFIG="fstab"
CRYPTTAB_CONFIG="crypttab"

#==============================================================================
# COLOR OUTPUT AND LOGGING
#==============================================================================
#
# ANSI color codes for terminal output. Makes logs human-readable.
# These are escape sequences that terminals interpret as color changes.
#
# Format: \033[<style>;<color>m
#   Style: 0=normal, 1=bold
#   Color: 31=red, 32=green, 33=yellow, 34=blue
#   Reset: \033[0m (return to default color)
#
# Why colors?
#   - Instant visual feedback (green = good, red = bad)
#   - Easier to scan long logs for errors
#   - Professional-looking output (we're not cavemen)
#==============================================================================

RED='\033[0;31m'      # Error messages (fatal problems)
GREEN='\033[0;32m'    # Success messages (operations completed)
YELLOW='\033[1;33m'   # Warning messages (non-fatal issues)
BLUE='\033[0;34m'     # Info messages (progress updates)
NC='\033[0m'          # No Color (reset to default)

# log_info: Informational message (progress updates)
# Usage: log_info "Installing packages..."
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# log_success: Success message (operation completed)
# Usage: log_success "Partitions created"
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# log_warning: Warning message (non-fatal issue, script continues)
# Usage: log_warning "Optional dependency missing"
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# log_error: Error message (fatal problem, may exit)
# Usage: log_error "Drive not found"
log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# die: Fatal error - log message and exit immediately
# Usage: die "Cannot proceed without critical dependency"
# This is the nuclear option. Only use for unrecoverable errors.
die() {
    log_error "$1"
    exit 1
}

#==============================================================================
# SAFETY CHECKS
#==============================================================================
#
# These functions prevent catastrophic mistakes:
#   - Running as non-root (need permissions for partitioning)
#   - Running on installed system (would destroy running OS)
#   - Operating on mounted filesystems (data corruption)
#   - Operating on non-existent drives (typo in config)
#
# Each check is a safety net. Multiple nets = fewer disasters.
#==============================================================================

# require_root: Verify script is running as root
#
# Why? Most operations require root:
#   - Partitioning drives (parted, gdisk)
#   - Formatting filesystems (mkfs.*)
#   - Mounting filesystems (mount)
#   - Creating encrypted volumes (cryptsetup)
#
# Without root, these commands fail with "Permission denied"
require_root() {
    if [[ $EUID -ne 0 ]]; then
        die "This script must be run as root (use sudo)"
    fi
}

# require_live_environment: Verify running from live USB, not installed system
#
# Why? Running on installed system would:
#   - Erase the currently running OS
#   - Destroy all user data
#   - Leave system unbootable
#
# Detection Strategy:
#   - Check for /etc/debian_version (Debian-based live USB)
#   - Check for /target directory (installer environment)
#   - If unsure, prompt user for confirmation
#
# This is a heuristic, not foolproof. Hence the manual confirmation.
require_live_environment() {
    # Check if we're running from live environment (not installed system)
    if [[ ! -f /etc/debian_version ]] || [[ -d /target ]]; then
        log_warning "Cannot definitively confirm live environment"
        read -p "Are you SURE you're running from a Live USB? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            die "Aborted - run from Live USB only"
        fi
    fi
}

# verify_drive_exists: Check if block device exists before operations
#
# Why? Typo in NVME_DRIVE="/dev/nvme0n1" → "/dev/nvme1n1" means:
#   - Erase wrong drive (data loss)
#   - Or fail immediately (better outcome)
#
# This check catches typos before destructive operations begin.
verify_drive_exists() {
    local drive=$1
    if [[ ! -b "$drive" ]]; then
        die "Drive $drive does not exist. Run lsblk and update variables."
    fi
}

# confirm_drives_unmounted: Verify target drives have no mounted partitions
#
# Why? Operating on mounted filesystems causes:
#   - Data corruption (kernel caching conflicts)
#   - Erase failures (device busy)  
#   - Undefined behavior (really bad things)
#
# Must unmount before proceeding.
confirm_drives_unmounted() {
    log_info "Checking if target drives are mounted..."
    
    # grep -q: quiet mode (return exit code only, no output)
    if mount | grep -q "$NVME_DRIVE"; then
        die "$NVME_DRIVE has mounted partitions. Unmount first."
    fi
    
    if mount | grep -q "$SATA_DRIVE"; then
        die "$SATA_DRIVE has mounted partitions. Unmount first."
    fi
    
    log_success "Target drives are not mounted"
}

# interactive_confirmation: Final "are you absolutely sure?" prompt
#
# Why? This is the last chance to abort before data destruction.
# Shows user exactly what will be erased (drive models, serial numbers).
# 5-second countdown allows panic-abort (Ctrl+C).
#
# UX Design:
#   - Clear visual separation (banner lines)
#   - lsblk output (see exact drives)
#   - Config summary (hostname, timezone)
#   - Countdown timer (last chance to abort)
interactive_confirmation() {
    echo ""
    echo "=========================================="
    echo "  FINAL CONFIRMATION BEFORE DESTRUCTION"
    echo "=========================================="
    echo ""
    echo "This will PERMANENTLY DESTROY ALL DATA on:"
    echo ""
    
    # lsblk: Show human-readable drive info
    # -o: Output columns (NAME, SIZE, MODEL, SERIAL)
    lsblk -o NAME,SIZE,MODEL,SERIAL "$NVME_DRIVE" "$SATA_DRIVE"
    
    echo ""
    echo "Target drives:"
    echo "  NVMe Root: $NVME_DRIVE"
    echo "  SATA Home: $SATA_DRIVE"
    echo "  USB Key:   $USB_DRIVE"
    echo ""
    echo "New system will be:"
    echo "  Hostname: $HOSTNAME"
    echo "  Timezone: $TIMEZONE"
    echo "  Init:     Sysvinit"
    echo ""
    
    log_warning "Proceeding with destructive operations in 5 seconds..."
    log_warning "Press Ctrl+C NOW to abort!"
    sleep 5
}

#==============================================================================
# DEPENDENCY CHECKS  
#==============================================================================
#
# Verify all required tools are installed before proceeding.
# Failing fast (at start) is better than failing late (mid-install).
#
# Dependency Categories:
#   1. Critical: Script cannot run without these (exit if missing)
#   2. Optional: Script degrades gracefully (warn if missing)
#
# Critical Dependencies:
#   - Partitioning: parted, sgdisk, wipefs
#   - Filesystems: mkfs.vfat, mkfs.ext4, mkfs.btrfs
#   - Encryption: cryptsetup
#   - Bootstrap: debootstrap
#   - Chroot: arch-chroot (or regular chroot)
#
# Optional Dependencies:
#   - Secure erase: nvme-cli, hdparm (fallback to wipefs)
#   - Diagnostics: smartmontools (nice to have)
#
# Why arch-chroot?
#   - Auto-mounts /dev, /proc, /sys (less error-prone)
#   - Copies /etc/resolv.conf (network works in chroot)
#   - Cleaner syntax than manual bind mounts
#==============================================================================

check_dependencies() {
    log_info "Checking for required dependencies..."
    
    local missing_deps=()          # Optional dependencies (warn only)
    local missing_critical=()      # Critical dependencies (fatal)
    
    # Critical dependencies: "command:package" format
    # Format allows checking for command (which we run) and package (which we install)
    # Example: "parted:parted" checks for 'parted' command in 'parted' package
    local critical_deps=(
        "parted:parted"               # Partition management
        "sgdisk:gdisk"                # GPT partition tables
        "mkfs.vfat:dosfstools"        # FAT32 (EFI partition)
        "mkfs.ext4:e2fsprogs"         # ext4 (boot partition)
        "mkfs.btrfs:btrfs-progs"      # BTRFS (root/home filesystems)
        "btrfs:btrfs-progs"           # BTRFS utilities (subvolumes)
        "cryptsetup:cryptsetup"       # LUKS encryption
        "debootstrap:debootstrap"     # Bootstrap Devuan
        "wipefs:util-linux"           # Wipe filesystem signatures
        "lsblk:util-linux"            # List block devices
        "mount:util-linux"            # Mount filesystems
        "dd:coreutils"                # Data duplication (keyfile)
        "shuf:coreutils"              # Random number generation (hostname)
        "partprobe:parted"            # Notify kernel of partition changes
        "arch-chroot:arch-install-scripts"  # Chroot helper
        "wget:wget"                   # Download Hack font
    )
    
    # Optional dependencies: Script works without these, but less securely
    local optional_deps=(
        "nvme:nvme-cli"               # NVMe secure erase (cryptographic)
        "hdparm:hdparm"               # SATA secure erase (ATA commands)
        "smartctl:smartmontools"      # Drive health monitoring
    )
    
    # Check critical dependencies
    for dep_info in "${critical_deps[@]}"; do
        local cmd="${dep_info%%:*}"   # Extract command (before colon)
        local pkg="${dep_info##*:}"   # Extract package (after colon)
        
        # command -v: Check if command exists in PATH
        # &>/dev/null: Suppress output (we only care about exit code)
        if ! command -v "$cmd" &>/dev/null; then
            missing_critical+=("$pkg")
        fi
    done
    
    # Check optional dependencies
    for dep_info in "${optional_deps[@]}"; do
        local cmd="${dep_info%%:*}"
        local pkg="${dep_info##*:}"
        
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$pkg")
        fi
    done
    
    # Report missing critical dependencies
    if [[ ${#missing_critical[@]} -gt 0 ]]; then
        log_error "Missing critical dependencies!"
        echo ""
        echo "The following packages are required but not installed:"
        for pkg in "${missing_critical[@]}"; do
            echo "  - $pkg"
        done
        echo ""
        echo "Install them with:"
        echo "  apt update && apt install ${missing_critical[*]}"
        echo ""
        die "Cannot proceed without critical dependencies"
    fi
    
    # Report missing optional dependencies (non-fatal)
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_warning "Missing optional dependencies:"
        for pkg in "${missing_deps[@]}"; do
            echo "  - $pkg (secure erase may not work optimally)"
        done
        echo ""
        echo "Install them with:"
        echo "  apt install ${missing_deps[*]}"
        echo ""
        read -p "Continue without optional dependencies? (yes/no): " confirm
        if [[ "$confirm" != "yes" ]]; then
            die "Aborted by user"
        fi
    fi
    
    # Verify chroot capability (either arch-chroot or regular chroot)
    if ! command -v arch-chroot &>/dev/null && ! command -v chroot &>/dev/null; then
        log_error "No chroot command available!"
        echo ""
        echo "Install arch-install-scripts for arch-chroot:"
        echo "  apt install arch-install-scripts"
        echo ""
        die "Cannot proceed without chroot capability"
    fi
    
    log_success "All critical dependencies satisfied"
}

#==============================================================================
# SECURE ERASE FUNCTIONS
#==============================================================================
#
# Data Destruction Strategy:
#   1. Try hardware-level secure erase (instant, irreversible)
#   2. Fall back to partition table wipe (fast, less secure)
#
# Why Secure Erase?
#   - Deleted files are NOT erased (just marked as "free space")
#   - Reformatting does NOT erase data (just rebuilds filesystem metadata)
#   - Data recovery tools can restore "deleted" files easily
#   - Secure erase writes zeros/random data to entire drive
#
# NVMe Secure Erase:
#   - Cryptographic erase (instant, destroys encryption key)
#   - User data erase (slower, writes zeros)
#   - Fallback: Wipe partition table only
#
# SATA Secure Erase:
#   - ATA Secure Erase (vendor-specific, usually fast)
#   - Fallback: Wipe partition table only
#
# Fallback Strategy:
#   - wipefs: Remove filesystem signatures (magic bytes)
#   - sgdisk --zap-all: Destroy GPT/MBR partition tables
#   - LUKS encryption protects new data (old data may be recoverable)
#
# When is Fallback Acceptable?
#   - New drives (no sensitive data yet)
#   - Non-sensitive data (performance benchmarks, test systems)
#   - LUKS encryption (protects data going forward)
#
# When is Secure Erase Required?
#   - Used drives with sensitive data
#   - Drives being sold/donated/discarded
#   - Compliance requirements (HIPAA, GDPR, etc.)
#==============================================================================

# secure_erase_nvme: Attempt NVMe-specific secure erase
#
# NVMe Format Command:
#   nvme format /dev/nvmeXnY --ses=N
#
# Secure Erase Settings (SES):
#   --ses=0: No secure erase (just format)
#   --ses=1: User Data Erase (write zeros to all blocks)
#   --ses=2: Cryptographic Erase (destroy encryption key, instant)
#
# How Cryptographic Erase Works:
#   - Modern SSDs encrypt all data with internal key (transparent)
#   - Cryptographic erase destroys this key, making data unrecoverable
#   - Instant operation (no need to write zeros)
#   - Most secure option (no data recovery possible)
#
# Fallback Strategy:
#   1. Try cryptographic erase (--ses=2)
#   2. Try user data erase (--ses=1)
#   3. Give up, wipe partition table only
#
# Why Fallback?
#   - Not all NVMe drives support secure erase
#   - Some require vendor-specific tools
#   - LUKS encryption protects new data anyway
#
# Security Implications:
#   - Fallback means old data MAY be recoverable
#   - But: LUKS encrypts all new data
#   - But: Recovering old data requires lab equipment + time
#   - Acceptable risk for most use cases
secure_erase_nvme() {
    local drive=$1
    
    log_info "Attempting NVMe secure erase..."
    
    # Try cryptographic erase (instant, secure)
    if nvme format "$drive" --ses=2 2>/dev/null; then
        log_success "NVMe cryptographic erase completed"
        return 0
    fi
    
    # Try user data erase (slower, but secure)
    if nvme format "$drive" --ses=1 2>/dev/null; then
        log_success "NVMe user data erase completed"
        return 0
    fi
    
    # Secure erase not supported - just nuke the partition table
    log_warning "NVMe secure erase not supported"
    log_info "Wiping partition table and filesystem signatures..."
    
    wipefs -af "$drive" 2>/dev/null || true
    sgdisk --zap-all "$drive" 2>/dev/null || true
    
    log_warning "Drive contents not securely erased - old data may be recoverable"
    log_warning "LUKS encryption will protect new data going forward"
    
    return 0
}
# secure_erase_sata: Attempt SATA/ATA secure erase
#
# ATA Secure Erase Process:
#   1. Set a temporary password (required by ATA spec)
#   2. Issue secure erase command (drive wipes itself)
#   3. Verify completion (drive should auto-disable password)
#
# How ATA Secure Erase Works:
#   - ATA command tells drive to erase all sectors
#   - Drive firmware handles the actual erasure
#   - Usually fast (few minutes for 1TB drive)
#   - Vendor-implemented (quality varies)
#
# Security Notes:
#   - Not all SATA drives support it (especially old ones)
#   - Some drives lie about completion (firmware bugs)
#   - Some laptops disable it in BIOS (security feature, ironically)
#   - Frozen state: Drive locked by BIOS, must power-cycle to unlock
#
# Frozen State Workaround:
#   - Suspend laptop (sleep mode)
#   - Wake up (drive resets without BIOS lock)
#   - Try secure erase again
#   - Or: Hot-swap drive (power off, unplug, replug, power on)
#
# Password Security:
#   - Temporary password only used during erase
#   - Auto-cleared after erase completes
#   - If erase fails, we manually disable password
#   - Random password to avoid conflicts
#
# Fallback Strategy:
#   Same as NVMe - wipe partition table, warn user
secure_erase_sata() {
    local drive=$1
    # Generate random password (avoid conflicts with existing passwords)
    # $(date +%s): Unix timestamp (seconds since 1970-01-01)
    local temp_password="SecureEraseTemp$(date +%s)"
    
    log_info "Attempting SATA secure erase on $drive..."
    
    # Try ATA Secure Erase directly
    # Step 1: Set password (enables security mode)
    # --user-master u: User password (not master password)
    # --security-set-pass: Set ATA password
    if hdparm --user-master u --security-set-pass "$temp_password" "$drive" 2>/dev/null; then
        # Step 2: Issue secure erase command
        # --security-erase: Erase all data
        if hdparm --user-master u --security-erase "$temp_password" "$drive" 2>/dev/null; then
            log_success "ATA Secure Erase completed"
            return 0
        fi
        
        # Step 3: Erase failed - clean up password
        # --security-disable: Remove ATA password
        # If we don't do this, drive stays locked!
        hdparm --user-master u --security-disable "$temp_password" "$drive" 2>/dev/null
    fi
    
    # ATA Secure Erase failed - just wipe partition table
    log_warning "ATA Secure Erase failed or not supported"
    log_info "Wiping partition table and filesystem signatures..."
    
    wipefs -af "$drive" 2>/dev/null || true
    sgdisk --zap-all "$drive" 2>/dev/null || true
    
    log_warning "Drive contents not securely erased - old data may be recoverable"
    log_warning "LUKS encryption will protect new data going forward"
    
    return 0
}

#==============================================================================
# PREPARE THE BOOTKEY
#==============================================================================
#
# USB Keyfile Strategy:
#   - Small USB drive (1GB+) dedicated to boot unlocking
#   - Contains single file: /keyfile (4096 bytes random data)
#   - Must be inserted at boot for system to unlock
#   - Can be removed after boot (optional security measure)
#
# Filesystem Choice: ext4
#   - Reliable, universally supported
#   - initramfs has ext4 drivers built-in
#   - Simple (no journaling complications)
#
# Partition Table: GPT
#   - Modern standard (replaced MBR)
#   - Supports partition labels (by-partlabel references)
#   - Compatible with UEFI systems
#
# Partition Type: Linux filesystem (8300)
#   - Standard GUID for ext4 partitions
#   - Explicitly set to avoid type mismatch errors
#
# Security: Born Secure Pattern
#   - File created with umask 077 (chmod 600 equivalent)
#   - No race condition (permissions correct from birth)
#   - Subshell isolates umask (doesn't affect parent script)
#
# Why Wipe First?
#   - USB might have existing filesystem/partitions
#   - Old partition type GUID might conflict
#   - Fresh start ensures clean state
#   - Fixes "partition type mismatch" errors from previous runs
#
# Keyfile Size: 4096 bytes
#   - More than enough entropy (512 bytes would suffice)
#   - Matches typical disk block size (efficient I/O)
#   - Paranoid overkill (but disk space is cheap)
#
# Random Source: /dev/urandom
#   - Cryptographically secure random number generator
#   - Non-blocking (doesn't wait for entropy)
#   - Good enough for key material (kernel CSPRNG)
#   - Alternative: /dev/random (blocks if low entropy, slower)
#==============================================================================

prepare_usb_keyfile() {
    local drive=$1
    
    log_info "Preparing USB keyfile drive $drive..."
    
    # ──────────────────────────────────────────────────────────────────────
    # STEP 1: NUCLEAR OPTION - Always wipe everything
    # ──────────────────────────────────────────────────────────────────────
    # Why? Fixes partition type mismatch from previous runs.
    # We don't check 'if' it exists. We nuke it unconditionally.
    #
    # wipefs: Remove filesystem signatures (magic bytes)
    #   -a: All signatures (filesystem, RAID, partition table)
    # sgdisk --zap-all: Destroy GPT + protective MBR
    # 2>/dev/null: Suppress errors (don't care if nothing to wipe)
    # || true: Don't fail script if wipe commands fail
    
    wipefs -a "${drive}" 2>/dev/null || true
    wipefs -a "${drive}1" 2>/dev/null || true
    sgdisk --zap-all "$drive" 2>/dev/null || true
    
    # ──────────────────────────────────────────────────────────────────────
    # STEP 2: Create New GPT Table & Partition
    # ──────────────────────────────────────────────────────────────────────
    # parted scripting mode:
    #   -s: Script mode (non-interactive, no prompts)
    #   mklabel gpt: Create GPT partition table
    #   mkpart: Create partition
    #     primary: Partition type (legacy term, ignored in GPT)
    #     ext4: Filesystem type (sets partition type GUID to 8300)
    #     1MiB: Start offset (align to 1MB boundary for performance)
    #     100%: End offset (use all remaining space)
    #   name: Set partition label (for /dev/disk/by-partlabel/ reference)
    
    log_info "Creating partition table..."
    parted -s "$drive" mklabel gpt
    
    # Explicitly set filesystem type to ext4 for correct GUID
    # This ensures partition type GUID is 0FC63DAF-8483-4772-8E79-3D69D8477DE4
    # (Linux filesystem, type 8300 in gdisk terminology)
	# We combine label, partition, and name to prevent kernel race conditions.
    log_info "Creating partition table..."
    parted -s "$drive" \
        mklabel gpt \
        mkpart primary ext4 1MiB 100% \
        name 1 "$PARTLABEL_USB"
    
    # Wait for kernel to register the new partition
    # partprobe: Tell kernel to re-read partition table
    # sleep: Give udev time to create /dev/disk/by-partlabel/ symlinks
    partprobe "$drive"
    sleep 2
    
    # ──────────────────────────────────────────────────────────────────────
    # STEP 3: Format as ext4
    # ──────────────────────────────────────────────────────────────────────
    # mkfs.ext4 options:
    #   -F: Force (overwrite existing filesystem if present)
    #   -L: Set filesystem label (matches partition label for consistency)
    # ${drive}1: First partition (e.g., /dev/sdc1)
    
    log_info "Formatting as Ext4..."
    mkfs.ext4 -F -L "$PARTLABEL_USB" "${drive}1" || die "Failed to format USB drive"
    
    # ──────────────────────────────────────────────────────────────────────
    # STEP 4: Mount and Generate Keyfile
    # ──────────────────────────────────────────────────────────────────────
    # Create temporary mount point and mount USB
    mkdir -p /mnt/usb
    mount "${drive}1" /mnt/usb || die "Failed to mount USB drive"
    
    log_info "Generating random keyfile..."
    
    # ──────────────────────────────────────────────────────────────────────
    # STEP 5: Generate Keyfile (Born Secure Pattern)
    # ──────────────────────────────────────────────────────────────────────
    # Security Pattern: Subshell with umask
    #   ( ... ): Subshell (changes don't affect parent)
    #   umask 077: Only owner can read/write (chmod 600 equivalent)
    #   dd: Data duplication (copy random bytes to file)
    #
    # Why Subshell?
    #   - umask affects all files created after it's set
    #   - We only want it for this one file
    #   - Subshell isolates the umask change
    #   - Parent script's umask unchanged
    #
    # dd parameters:
    #   if=/dev/urandom: Input file (kernel CSPRNG)
    #   of=/mnt/usb/keyfile: Output file (our keyfile)
    #   bs=4096: Block size (4KB, typical disk block size)
    #   count=1: Number of blocks (1 × 4096 = 4096 bytes)
    #
    # Result: File created with 600 permissions atomically
    # No race condition (file never world-readable)
    
    (
        umask 077
        dd if=/dev/urandom of="/mnt/usb${USB_KEYFILE_PATH}" bs=4096 count=1
    ) || die "Failed to create keyfile"
    
    # Verification (redundant but explicitly safe)
    # This chmod is technically unnecessary (umask already set 600)
    # But: Belt and suspenders approach (explicit is better than implicit)
    chmod 600 "/mnt/usb${USB_KEYFILE_PATH}"
    
    # Cleanup: unmount USB
    umount /mnt/usb
    
    log_success "USB keyfile drive prepared (EXT4 + Permissions Secured)"
}

#==============================================================================
# PARTITIONING
#==============================================================================
#
# Partition Layout Strategy:
#   - GPT (GUID Partition Table): Modern standard, replaces MBR
#   - Aligned to 1MiB boundaries: Optimal for SSD performance
#   - Labels for all partitions: Human-readable references
#
# NVMe Drive (System):
#   p1: EFI System Partition (512M, FAT32)
#       - UEFI firmware reads bootloader from here
#       - Must be FAT32 (UEFI spec requirement)
#       - ESP flag set (marks as EFI System Partition)
#   p2: Boot partition (10G, ext4)
#       - Kernel, initramfs, GRUB config
#       - Unencrypted (GRUB can't unlock LUKS)
#       - Large enough for custom live ISOs (system recovery)
#   p3: Encrypted root (remaining space, LUKS → BTRFS)
#       - Root filesystem + subvolumes
#       - LUKS2 encrypted (AES-XTS, Argon2id)
#
# SATA Drive (Data):
#   p1: Encrypted home (all space, LUKS → BTRFS)
#       - User home directories + VM/container storage
#       - Separate drive = failure isolation
#       - Independent encryption = defense in depth
#
# Why These Sizes?
#   - EFI: 512M is standard (100M minimum, room for multiple bootloaders)
#   - Boot: 10G allows custom ISOs (typical: 512M-1G, we're generous)
#   - Root: Depends on use case (50G minimum, 200G comfortable, we use all)
#   - Home: All remaining space (users generate lots of data)
#
# Partition Label Strategy:
#   - Descriptive names (ESP, boot, cryptroot, crypthome)
#   - Used in fstab/crypttab (by-partlabel references)
#   - Persist across repartitioning (if you reuse same labels)
#   - More reliable than UUIDs (UUIDs change on reformat)
#==============================================================================

# create_nvme_partitions: Partition NVMe system drive
#
# Partition Calculation:
#   - EFI: 1MiB to 512M (start, end)
#   - Boot: 512M to (512M + 10G) = 10.5G
#   - Root: 10.5G to 100% (remaining space)
#
# Size String Parsing:
#   ${EFI_SIZE%M}: Strip 'M' suffix ("512M" → "512")
#   ${BOOT_SIZE%G}: Strip 'G' suffix ("10G" → "10")
#   $((expr)): Arithmetic expansion (bash calculator)
#
# Example Calculation:
#   EFI_SIZE="512M", BOOT_SIZE="10G"
#   ${EFI_SIZE%M} = 512
#   ${BOOT_SIZE%G} = 10
#   ${EFI_SIZE%M} + ${BOOT_SIZE%G} * 1024 = 512 + 10240 = 10752 MiB
# create_nvme_partitions: Partition NVMe system drive
#
# Partition Calculation:
#   - EFI: 1MiB to 512M (start, end)
#   - Boot: 512M to (512M + 10G) = 10.5G
#   - Root: 10.5G to 100% (remaining space)
#
# Race Condition Note:
#   Collapsing all parted commands into one prevents the kernel/udev 
#   from locking the device while we are still creating the table.
create_nvme_partitions() {
    local drive=$1
    
    log_info "Creating partition table on $drive..."
    
    # Create GPT partition table and all sub-partitions in one atomic call
    parted -s "$drive" \
        mklabel gpt \
        mkpart primary fat32 1MiB "$EFI_SIZE" \
        mkpart primary ext4 "$EFI_SIZE" "$((${EFI_SIZE%M} + ${BOOT_SIZE%G} * 1024))MiB" \
        mkpart primary btrfs "$((${EFI_SIZE%M} + ${BOOT_SIZE%G} * 1024))MiB" 100% \
        name 1 "$PARTLABEL_EFI" \
        name 2 "$PARTLABEL_BOOT" \
        name 3 "$PARTLABEL_CRYPTROOT" \
        set 1 esp on
    
    log_success "NVMe partitions created"
}

# create_sata_partitions: Partition SATA data drive
#
# Simple layout: One big encrypted partition for everything
# No need for EFI/boot (those are on NVMe)
# create_sata_partitions: Partition SATA data drive
#
# Simple layout: One big encrypted partition for everything
# No need for EFI/boot (those are on NVMe)
# 
# Race Condition Note:
#   Using a single parted call prevents the kernel from locking the 
#   drive between the label creation and the partition naming.
create_sata_partitions() {
    local drive=$1
    
    log_info "Creating partition table on $drive..."
    
    # Create GPT partition table, partition, and name in one atomic call
    # 1MiB start for alignment, 100% end for all space
    parted -s "$drive" \
        mklabel gpt \
        mkpart primary btrfs 1MiB 100% \
        name 1 "$PARTLABEL_CRYPTHOME"
    
    log_success "SATA partitions created"
}

#==============================================================================
# FILESYSTEM CREATION
#==============================================================================
#
# Filesystem Strategy:
#   - EFI: FAT32 (UEFI requirement, no choice)
#   - Boot: ext4 (simple, reliable, GRUB support)
#   - Root/Home: BTRFS (CoW, compression, subvolumes)
#
# Why BTRFS?
#   - Copy-on-Write: Never overwrites data (instant snapshots)
#   - Transparent compression: Save disk space automatically
#   - Subvolumes: Independent mount options per directory
#   - Checksums: Detect silent data corruption
#   - Online defrag: Fix fragmentation without unmounting
#
# Why NOT BTRFS?
#   - Databases: CoW causes fragmentation (use nodatacow)
#   - VMs: Disk images fragment badly (use nodatacow)
#   - Swap: CoW breaks swap files (use nodatacow subvolume)
#
# LUKS Configuration:
#   - Type: LUKS2 (modern format, Argon2 support)
#   - Cipher: AES-XTS-PLAIN64 (industry standard)
#   - Key size: 512-bit (XTS splits to 256+256)
#   - KDF: Argon2id (GPU-resistant)
#   - Iteration time: 4 seconds (bruteforce resistance)
#
# Why Separate Encrypted Volumes?
#   - Root and home have different threat models
#   - Home may contain more sensitive data (documents, keys)
#   - Separate encryption = defense in depth
#   - If root compromised, home remains protected
#
# LUKS Header Location:
#   - Stored at beginning of partition (first 16MB)
#   - Contains encrypted master key (protected by keyfile)
#   - Master key encrypts actual data (key rotation possible)
#   - Backup LUKS header: `cryptsetup luksHeaderBackup`
#==============================================================================

# format_boot_partitions: Create filesystems on unencrypted boot partitions
#
# EFI Partition:
#   - mkfs.vfat: Create FAT32 filesystem
#   - -F 32: Force FAT32 (not FAT16)
#   - -n: Set volume label (optional, nice to have)
#
# Boot Partition:
#   - mkfs.ext4: Create ext4 filesystem
#   - -L: Set filesystem label (for fstab references)
#
# Why by-partlabel?
#   - /dev/disk/by-partlabel/ESP: Symlink to actual device
#   - More reliable than /dev/nvme0n1p1 (device names can change)
#   - Works even if drive letter shifts (hot-swap scenarios)
format_boot_partitions() {
    log_info "Formatting boot partitions..."
    
    # Format EFI partition as FAT32
    # || die: If format fails, abort entire script (critical)
    mkfs.vfat -F 32 -n "$PARTLABEL_EFI" "/dev/disk/by-partlabel/$PARTLABEL_EFI" || \
        die "Failed to format EFI partition"
    
    # Format boot partition as ext4
    mkfs.ext4 -L "$PARTLABEL_BOOT" "/dev/disk/by-partlabel/$PARTLABEL_BOOT" || \
        die "Failed to format boot partition"
    
    log_success "Boot partitions formatted"
}

# setup_luks_encryption: Encrypt root and home partitions with LUKS2
#
# LUKS2 Format Process:
#   1. Mount USB keyfile drive
#   2. Format root partition with LUKS2 (using keyfile)
#   3. Format home partition with LUKS2 (using keyfile)
#   4. Open both encrypted partitions (map to /dev/mapper/)
#   5. Unmount USB keyfile drive
#
# Security Note:
#   - Same keyfile unlocks both volumes (convenience)
#   - Alternative: Separate keyfiles (more secure, more complex)
#   - Backup passphrase can be added later (add-backup-passphrase.sh)
#
# LUKS Parameters:
#   --type luks2: Use LUKS2 format (not legacy LUKS1)
#   --cipher: Encryption algorithm (AES-XTS-PLAIN64)
#   --key-size: Key length in bits (512 = 256+256 for XTS)
#   --hash: Hash for key derivation (SHA-256)
#   --pbkdf: Key derivation function (Argon2id)
#   --iter-time: KDF iteration time in ms (4000 = 4 seconds)
#   --key-file: Path to keyfile (on mounted USB drive)
#
# Device Mapper Names:
#   - cryptsetup open creates /dev/mapper/cryptroot
#   - cryptsetup open creates /dev/mapper/crypthome
#   - These are used in fstab to mount filesystems
setup_luks_encryption() {
    log_info "Setting up LUKS encryption..."
    
    # ──────────────────────────────────────────────────────────────────────
    # Mount USB Keyfile Drive
    # ──────────────────────────────────────────────────────────────────────
    # Create mount point and mount USB by label
    # by-label works because we set filesystem label during USB prep
    mkdir -p /mnt/usb
    mount "/dev/disk/by-label/$PARTLABEL_USB" /mnt/usb || die "Failed to mount USB keyfile"
    
    # ──────────────────────────────────────────────────────────────────────
    # Encrypt Root Partition
    # ──────────────────────────────────────────────────────────────────────
    log_info "Encrypting root partition..."
    cryptsetup luksFormat \
        --type luks2 \
        --cipher "$LUKS_CIPHER" \
        --key-size "$LUKS_KEY_SIZE" \
        --hash "$LUKS_HASH" \
        --pbkdf "$LUKS_PBKDF" \
        --iter-time "$LUKS_ITER_TIME" \
        --key-file "/mnt/usb${USB_KEYFILE_PATH}" \
        "/dev/disk/by-partlabel/$PARTLABEL_CRYPTROOT" || \
        die "Failed to encrypt root partition"
    
    # ──────────────────────────────────────────────────────────────────────
    # Encrypt Home Partition
    # ──────────────────────────────────────────────────────────────────────
    log_info "Encrypting home partition..."
    cryptsetup luksFormat \
        --type luks2 \
        --cipher "$LUKS_CIPHER" \
        --key-size "$LUKS_KEY_SIZE" \
        --hash "$LUKS_HASH" \
        --pbkdf "$LUKS_PBKDF" \
        --iter-time "$LUKS_ITER_TIME" \
        --key-file "/mnt/usb${USB_KEYFILE_PATH}" \
        "/dev/disk/by-partlabel/$PARTLABEL_CRYPTHOME" || \
        die "Failed to encrypt home partition"
    
    # ──────────────────────────────────────────────────────────────────────
    # Open Encrypted Partitions
    # ──────────────────────────────────────────────────────────────────────
    # cryptsetup open: Unlock LUKS volume and map to /dev/mapper/
    # --key-file: Use keyfile (no passphrase prompt)
    # <source> <name>: Source partition, mapper name
    #
    # Result:
    #   /dev/disk/by-partlabel/cryptroot → /dev/mapper/cryptroot
    #   /dev/disk/by-partlabel/crypthome → /dev/mapper/crypthome
    
    log_info "Opening encrypted partitions..."
    cryptsetup open \
        --key-file "/mnt/usb${USB_KEYFILE_PATH}" \
        "/dev/disk/by-partlabel/$PARTLABEL_CRYPTROOT" \
        "$CRYPT_ROOT_NAME" || \
        die "Failed to open root partition"
    
    cryptsetup open \
        --key-file "/mnt/usb${USB_KEYFILE_PATH}" \
        "/dev/disk/by-partlabel/$PARTLABEL_CRYPTHOME" \
        "$CRYPT_HOME_NAME" || \
        die "Failed to open home partition"
    
    # Cleanup: unmount USB (keyfile no longer needed until reboot)
    umount /mnt/usb
    
    log_success "LUKS encryption configured"
}

# create_btrfs_filesystems: Format encrypted volumes with BTRFS
#
# BTRFS on LUKS Strategy:
#   - LUKS provides encryption (at block level)
#   - BTRFS provides features (at filesystem level)
#   - Layering: Physical drive → LUKS → BTRFS → Subvolumes
#
# Why No Labels?
#   - We reference by /dev/mapper/cryptroot (mapper name)
#   - Labels would be redundant (mapper name is already label)
#   - Keeps fstab/crypttab consistent
#
# mkfs.btrfs Options:
#   -f: Force (overwrite existing filesystem if present)
#   /dev/mapper/cryptroot: Encrypted device (not raw partition)
create_btrfs_filesystems() {
    log_info "Creating BTRFS filesystems..."
    
    # Format root encrypted volume
    # No label - reference by /dev/mapper/cryptroot
    mkfs.btrfs -f "/dev/mapper/$CRYPT_ROOT_NAME" || die "Failed to create root filesystem"
    
    # Format home encrypted volume
    mkfs.btrfs -f "/dev/mapper/$CRYPT_HOME_NAME" || die "Failed to create home filesystem"
    
    log_success "BTRFS filesystems created"
}

# create_btrfs_subvolumes: Create BTRFS subvolume structure
#
# Subvolume Strategy:
#   - Root drive: System directories + logs/cache
#   - Home drive: User data + VM/container storage
#
# Subvolume Naming Convention:
#   - '@' prefix identifies subvolumes
#   - '@' alone is root subvolume (/)
#   - Path separators '/' become '@' (/@var/log → @var@log)
#   - Prevents mount path conflicts
#   - Enables clean snapshot operations
#
# Why Separate Subvolumes?
#   - Independent mount options (compress vs nodatacow)
#   - Independent snapshots (backup /home without /var/cache)
#   - Independent quotas (limit /var/log size)
#   - Rollback granularity (restore /usr/local without affecting /)
#
# CoW (Copy-on-Write) vs nodatacow:
#   - CoW: Enable compression, snapshots (most directories)
#   - nodatacow: Disable CoW for performance (databases, VMs, cache)
#
# Subvolume Descriptions:
#   @: Root filesystem (/)
#       - All system files not in other subvolumes
#       - CoW + compression (save space, enable snapshots)
#   @opt: Optional packages (/opt)
#       - Third-party software (Google Chrome, etc.)
#       - CoW + compression
#   @srv: Server data (/srv)
#       - Web server content, FTP data
#       - CoW + compression
#   @usr@local: Local binaries (/usr/local)
#       - Manually installed software
#       - CoW + compression
#   @var@log: System logs (/var/log)
#       - rsyslog, journald, application logs
#       - CoW + compression (logs compress well)
#   @var@cache: Package cache (/var/cache)
#       - apt cache, thumbnails
#       - nodatacow (temporary data, no need for CoW overhead)
#   @var@tmp: Temporary files (/var/tmp)
#       - Persistent temp files (survive reboot)
#       - nodatacow (throwaway data)
#   @swap: Swap file container (/swap)
#       - Must be nodatacow (BTRFS requirement for swap files)
#       - Optional (only needed if RAM < 16GB)
#   @home: User home directories (/home)
#       - User documents, config files
#       - CoW + compression (most valuable data)
#   @var@lib@libvirt@images: VM disk images
#       - QEMU/KVM virtual machine disks
#       - nodatacow (VM images fragment badly with CoW)
#   @var@lib@containers: Container storage
#       - Docker/Podman container layers
#       - nodatacow (container images have internal CoW)
create_btrfs_subvolumes() {
    log_info "Creating BTRFS subvolumes..."
    
    # ──────────────────────────────────────────────────────────────────────
    # Root Drive Subvolumes
    # ──────────────────────────────────────────────────────────────────────
    # Mount top-level subvolume (subvolid=5, BTRFS root)
    mount "/dev/mapper/$CRYPT_ROOT_NAME" /mnt || die "Failed to mount root"
    
    # Create subvolumes in top-level root
    # btrfs subvolume create: Create new subvolume (like mkdir, but special)
    btrfs subvolume create /mnt/@                # Root filesystem
    btrfs subvolume create /mnt/@opt             # Optional packages
    btrfs subvolume create /mnt/@srv             # Server data
    btrfs subvolume create /mnt/@usr@local       # Local binaries
    btrfs subvolume create /mnt/@var@log         # System logs
    btrfs subvolume create /mnt/@var@cache       # Package cache
    btrfs subvolume create /mnt/@var@tmp         # Temp files
    
    # Swap subvolume (optional, uncomment if needed)
    # Only create if you plan to use swap file
    # btrfs subvolume create /mnt/@swap          # Swap file container
    
    # Unmount top-level (we mount subvolumes individually later)
    umount /mnt
    
    # ──────────────────────────────────────────────────────────────────────
    # Home Drive Subvolumes
    # ──────────────────────────────────────────────────────────────────────
    # Mount top-level subvolume of home drive
    mount "/dev/mapper/$CRYPT_HOME_NAME" /mnt || die "Failed to mount home"
    
    # Create subvolumes for user data and VM/container storage
    btrfs subvolume create /mnt/@home                      # User home directories
    btrfs subvolume create /mnt/@var@lib@libvirt@images    # VM disk images
    btrfs subvolume create /mnt/@var@lib@containers        # Container storage
    
    # Unmount top-level
    umount /mnt
    
    log_success "BTRFS subvolumes created"
}

#==============================================================================
# MOUNTING FOR BOOTSTRAP
#==============================================================================
#
# Mount Strategy:
#   1. Mount root subvolume (@) to /mnt
#   2. Create directory structure in /mnt
#   3. Mount all other subvolumes to their paths
#   4. Mount boot partitions last
#
# Mount Order Matters:
#   - Parent directories must exist before mounting
#   - Root (/) mounted first, then subdirectories
#   - boot/efi requires boot to be mounted first
#
# BTRFS Mount Options:
#   defaults: Use default options (rw, suid, dev, exec, auto, nouser, async)
#   noatime: Don't update access time (performance, less wear on SSD)
#   compress=zstd:3: Transparent compression (level 3 = balanced)
#   ssd: Enable SSD-specific optimizations (TRIM, allocation strategy)
#   discard=async: Async TRIM (better performance than sync)
#   subvol=@: Mount specific subvolume (not top-level)
#   nodatacow: Disable Copy-on-Write (for databases, VMs, cache)
#
# Compression Levels (zstd):
#   1: Fast compression, less space savings
#   3: Balanced (default, recommended)
#   9: Slow compression, max space savings
#   15: Maximum (extreme CPU usage, minimal benefit)
#
# Why zstd Over Other Algorithms?
#   - Faster than zlib (older compression)
#   - Better compression ratio than lzo (fast but weak)
#   - Good balance of speed and compression
#   - Level 3 is "sweet spot" (fast + effective)
#
# When to Use nodatacow:
#   - Databases (PostgreSQL, MySQL data directories)
#   - VM disk images (QEMU qcow2, VirtualBox VDI)
#   - Container storage (Docker/Podman layers)
#   - Package cache (apt cache, pip cache)
#   - Swap files (BTRFS requirement)
#
# Why nodatacow for VMs/Databases?
#   - CoW causes fragmentation (many small writes)
#   - Fragmentation kills performance (random I/O patterns)
#   - VMs/databases already have internal consistency
#   - Snapshots still work (but lose some benefits)
#==============================================================================

mount_for_bootstrap() {
    log_info "Mounting filesystems for bootstrap..."
    
    # ──────────────────────────────────────────────────────────────────────
    # Mount Root Subvolume
    # ──────────────────────────────────────────────────────────────────────
    # Mount @ subvolume to /mnt with compression and SSD optimizations
    mount -o defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@ \
        "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET" || \
        die "Failed to mount root"
    
    # ──────────────────────────────────────────────────────────────────────
    # Create Directory Structure
    # ──────────────────────────────────────────────────────────────────────
    # mkdir -p: Create directories (and parents if needed)
    # This creates all mount points for subvolumes
    mkdir -p "$CHROOT_TARGET"/{boot,home,opt,srv,usr/local,var/{log,cache,tmp,lib/{libvirt/images,containers}}}
    
    # ──────────────────────────────────────────────────────────────────────
    # Mount Boot Partitions
    # ──────────────────────────────────────────────────────────────────────
    # Mount /boot (ext4, unencrypted)
    mount "/dev/disk/by-partlabel/$PARTLABEL_BOOT" "$CHROOT_TARGET/boot" || \
        die "Failed to mount boot"
    
    # Create EFI directory and mount ESP
    mkdir -p "$CHROOT_TARGET/boot/efi"
    mount "/dev/disk/by-partlabel/$PARTLABEL_EFI" "$CHROOT_TARGET/boot/efi" || \
        die "Failed to mount EFI"
    
    # ──────────────────────────────────────────────────────────────────────
    # Mount Root Drive Subvolumes (CoW + Compression)
    # ──────────────────────────────────────────────────────────────────────
    # These all get compression because they contain compressible data
    # (text files, binaries, configs)
    
    mount -o defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@opt \
        "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET/opt"
    
    mount -o defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@srv \
        "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET/srv"
    
    mount -o defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@usr@local \
        "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET/usr/local"
    
    mount -o defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@var@log \
        "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET/var/log"
    
    # ──────────────────────────────────────────────────────────────────────
    # Mount Root Drive Subvolumes (nodatacow for Performance)
    # ──────────────────────────────────────────────────────────────────────
    # Cache and tmp get nodatacow because:
    #   - Data is temporary (no need for CoW overhead)
    #   - High write frequency (CoW would cause fragmentation)
    #   - Snapshots less useful (throwaway data)
    
    mount -o defaults,noatime,nodatacow,ssd,discard=async,subvol=@var@cache \
        "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET/var/cache"
    
    mount -o defaults,noatime,nodatacow,ssd,discard=async,subvol=@var@tmp \
        "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET/var/tmp"
    
    # Swap subvolume (optional, uncomment if you created @swap)
    # MUST be nodatacow (BTRFS requirement for swap files)
    # mount -o defaults,noatime,nodatacow,ssd,discard=async,subvol=@swap \
    #     "/dev/mapper/$CRYPT_ROOT_NAME" "$CHROOT_TARGET/swap"
    
    # ──────────────────────────────────────────────────────────────────────
    # Mount Home Drive Subvolumes
    # ──────────────────────────────────────────────────────────────────────
    # Home gets compression (user documents compress well)
    mount -o defaults,noatime,compress=zstd:3,subvol=@home \
        "/dev/mapper/$CRYPT_HOME_NAME" "$CHROOT_TARGET/home"
    
    # VM/container storage gets nodatacow (performance critical)
    mount -o defaults,noatime,nodatacow,subvol=@var@lib@libvirt@images \
        "/dev/mapper/$CRYPT_HOME_NAME" "$CHROOT_TARGET/var/lib/libvirt/images"
    
    mount -o defaults,noatime,nodatacow,subvol=@var@lib@containers \
        "/dev/mapper/$CRYPT_HOME_NAME" "$CHROOT_TARGET/var/lib/containers"
    
    log_success "Filesystems mounted"
}

#==============================================================================
# BOOTSTRAP
#==============================================================================
#
# What is Debootstrap?
#   - Installs base Debian/Devuan system from scratch
#   - Downloads packages from repository
#   - Unpacks them into target directory
#   - Configures basic system (dpkg, apt, init)
#   - Result: Minimal bootable system (no kernel, no bootloader yet)
#
# Debootstrap Process:
#   1. Download Release/InRelease files (repository metadata)
#   2. Verify GPG signatures (security)
#   3. Download required packages (base system)
#   4. Unpack packages to target directory
#   5. Configure packages (run postinst scripts)
#   6. Install Essential packages (dpkg, apt, libc)
#
# Parameters:
#   --arch=amd64: CPU architecture (64-bit x86)
#   --components: Repository sections to enable
#       - main: Free software (DFSG-compliant)
#       - contrib: Free software depending on non-free
#       - non-free: Proprietary software (Nvidia, firmware)
#       - non-free-firmware: Firmware blobs (WiFi, GPU)
#   --include: Extra packages to install during bootstrap
#       - zsh: Z shell (our login shell)
#       - locales: Locale data (language/timezone)
#       - zstd: Compression tool (for BTRFS)
#   <suite>: Devuan release (excalibur, freia, ceres)
#   <target>: Where to install (our /mnt)
#   <mirror>: Package repository URL
#
# Why Include Extra Packages?
#   - zsh: Needed as login shell (user account requires it)
#   - locales: Required for locale generation (chroot step)
#   - zstd: Needed for BTRFS compression verification
#
# Bootstrap Size:
#   - Minimal: ~300MB (Essential + Required packages)
#   - With extras: ~500MB (adds zsh, locales, etc.)
#   - After full install: ~5-10GB (kernel, desktop, apps)
#
# Time Estimate:
#   - Fast mirror + fast connection: 3-5 minutes
#   - Slow mirror or slow connection: 10-15 minutes
#   - Depends on: Network speed, mirror load, CPU speed
#==============================================================================

run_bootstrap() {
    log_info "Running debootstrap for Devuan $DEVUAN_SUITE..."
    log_warning "This will take 5-10 minutes..."
    
    # Run debootstrap (install base system)
    # || die: If bootstrap fails, abort (can't continue without base system)
    debootstrap \
        --arch=amd64 \
        --components=main,contrib,non-free,non-free-firmware \
        --include=zsh,locales,zstd \
        "$DEVUAN_SUITE" \
        "$CHROOT_TARGET" \
        "$DEVUAN_MIRROR" || \
        die "Bootstrap failed"
    
    log_success "Bootstrap completed"
}

#==============================================================================
# CHROOT CONFIGURATION
#==============================================================================
#
# What is Chroot Configuration?
#   - Chroot = "change root" (fake root filesystem for process)
#   - We configure files in /mnt before entering chroot
#   - These files are used when system boots
#
# Files We Configure:
#   - fstab: Filesystem mount table (what mounts where)
#   - crypttab: Encrypted device table (how to unlock LUKS)
#   - apt sources: Repository configuration (where to get packages)
#   - grub config: Bootloader settings (kernel parameters)
#   - hostname: System name
#   - hosts: Local DNS (127.0.0.1 mapping)
#   - locale.gen: Language/encoding settings
#   - timezone: Local timezone
#
# Why Configure Before Chroot?
#   - Easier to generate from host (we have all variables)
#   - No need to pass variables into chroot environment
#   - Can use HEREDOC to generate files (cleaner syntax)
#==============================================================================

# configure_fstab: Generate /etc/fstab (filesystem mount table)
#
# fstab Format:
#   <device> <mountpoint> <type> <options> <dump> <pass>
#
# Fields:
#   device: What to mount (/dev/mapper/cryptroot, UUID=..., LABEL=...)
#   mountpoint: Where to mount (/, /home, /boot)
#   type: Filesystem type (btrfs, ext4, vfat, tmpfs)
#   options: Mount options (defaults, noatime, compress, etc.)
#   dump: Backup flag (0=don't backup, 1=backup)
#   pass: fsck order (0=skip, 1=first, 2=after root)
#
# Device References:
#   - /dev/mapper/cryptroot: Encrypted device (after unlocking)
#   - /dev/disk/by-partlabel/boot: Unencrypted partition (label)
#   - tmpfs: RAM-based filesystem (for /tmp)
#
# Mount Options Explained:
#   defaults: rw,suid,dev,exec,auto,nouser,async
#   noatime: Don't update access time (performance + SSD wear)
#   compress=zstd:3: BTRFS compression (level 3)
#   ssd: Enable SSD optimizations (TRIM, allocation)
#   discard=async: Async TRIM (better performance)
#   subvol=@: Mount specific BTRFS subvolume
#   nodatacow: Disable Copy-on-Write (for VMs/databases)
#   umask=0077: Permissions for FAT32 (only root can access)
#   mode=1777: Permissions for tmpfs (sticky bit, all can write)
#
# fsck Pass Numbers:
#   0: Never check (tmpfs, swap, network filesystems)
#   1: Check first (root filesystem only)
#   2: Check after root (all other filesystems)
#
# Why tmpfs for /tmp?
#   - RAM-based (very fast)
#   - Cleared on reboot (security)
#   - No disk wear (good for SSDs)
#   - Default on most modern systems
#
# Swap Configuration:
#   - Commented out by default (not everyone needs swap)
#   - Uncomment if you created @swap subvolume
#   - Swap file must be on nodatacow subvolume (BTRFS requirement)
configure_fstab() {
    log_info "Installing fstab..."
    
    # Generate /etc/fstab using HEREDOC
    # EOF is unquoted, so variables expand
    cat > "$CHROOT_TARGET/etc/fstab" <<EOF
# /etc/fstab - $HOSTNAME goes here for tracking purposes
# <device> <mount point> <type> <options> <dump> <pass>

# Root filesystem
/dev/mapper/cryptroot / btrfs defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@ 0 0

# Boot partitions
/dev/disk/by-partlabel/boot /boot ext4 defaults,noatime 0 2
/dev/disk/by-partlabel/ESP /boot/efi vfat defaults,noatime,umask=0077 0 2

# System subvolumes (CoW enabled, compression)
/dev/mapper/cryptroot /opt btrfs defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@opt 0 0
/dev/mapper/cryptroot /srv btrfs defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@srv 0 0
/dev/mapper/cryptroot /usr/local btrfs defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@usr@local 0 0
/dev/mapper/cryptroot /var/log btrfs defaults,noatime,compress=zstd:3,ssd,discard=async,subvol=@var@log 0 0

# Cache/tmp subvolumes (nodatacow for performance)
/dev/mapper/cryptroot /var/cache btrfs defaults,noatime,nodatacow,ssd,discard=async,subvol=@var@cache 0 0
/dev/mapper/cryptroot /var/tmp btrfs defaults,noatime,nodatacow,ssd,discard=async,subvol=@var@tmp 0 0

# Home (separate encrypted drive, CoW + compression)
/dev/mapper/crypthome /home btrfs defaults,noatime,compress=zstd:3,subvol=@home 0 0

# VM/Container storage (nodatacow for performance)
/dev/mapper/crypthome /var/lib/libvirt/images btrfs defaults,noatime,nodatacow,subvol=@var@lib@libvirt@images 0 0
/dev/mapper/crypthome /var/lib/containers btrfs defaults,noatime,nodatacow,subvol=@var@lib@containers 0 0

# Tmpfs
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0

# Swap Volume (optional - see documentation above)
# On btrfs you MUST put your swapfile on a separate subvolume or it will NOT snapshot
# Uncomment these lines if you need swap:
# /dev/mapper/cryptroot /swap btrfs defaults,subvol=@swap,nodatacow,noatime 0 0
# /swap/swapfile none swap sw 0 0
EOF
    
    log_success "/etc/fstab installed"
}

# configure_crypttab: Generate /etc/crypttab (encrypted device table)
#
# crypttab Format:
#   <target> <source> <key file> <options>
#
# Fields:
#   target: Device mapper name (cryptroot, crypthome)
#   source: Encrypted partition (/dev/disk/by-partlabel/cryptroot)
#   key file: Unlock key (USB device:path/to/keyfile)
#   options: cryptsetup options (luks, keyscript, timeout, etc.)
#
# Key File Syntax:
#   /dev/disk/by-partlabel/bootkey:/keyfile
#   - Device (/dev/disk/by-partlabel/bootkey)
#   - Colon separator (:)
#   - Path on device (/keyfile)
#
# Options:
#   luks: Use LUKS (default, but explicit is good)
#   keyscript=/lib/cryptsetup/scripts/passdev:
#       - Script to read key from removable device
#       - Mounts device, reads keyfile, unmounts device
#       - Handles USB device detection automatically
#
# Boot Process:
#   1. initramfs runs cryptsetup (via init scripts)
#   2. cryptsetup reads /etc/crypttab
#   3. passdev script detects USB drive (by partition label)
#   4. passdev mounts USB, reads /keyfile
#   5. cryptsetup uses keyfile to unlock LUKS volume
#   6. Device appears as /dev/mapper/cryptroot
#   7. System continues booting (mounts filesystems from fstab)
#
# Why passdev Script?
#   - Handles removable devices (USB might not be /dev/sdb every boot)
#   - Partition label is stable (device name can change)
#   - Auto-mounts and unmounts USB (clean operation)
#
# Alternative Key Configurations:
#   - none: Prompt for passphrase (interactive unlock)
#   - /path/to/keyfile: Key on root filesystem (after / is mounted)
#   - /dev/urandom: Random key (data lost on reboot, for temp volumes)
configure_crypttab() {
    log_info "Installing crypttab..."
    
    # Generate /etc/crypttab using HEREDOC
    cat > "$CHROOT_TARGET/etc/crypttab" <<EOF
# <target name> <source device> <key file> <options>

# Root partition - unlocked via keyfile on boot USB
cryptroot /dev/disk/by-partlabel/${PARTLABEL_CRYPTROOT} /dev/disk/by-partlabel/${PARTLABEL_USB}:${USB_KEYFILE_PATH} luks,keyscript=/lib/cryptsetup/scripts/passdev

# Home partition - unlocked via same keyfile
crypthome /dev/disk/by-partlabel/${PARTLABEL_CRYPTHOME} /dev/disk/by-partlabel/${PARTLABEL_USB}:${USB_KEYFILE_PATH} luks,keyscript=/lib/cryptsetup/scripts/passdev
EOF
    
    log_success "/etc/crypttab installed"
}

# configure_policy_rcd: Install policy-rc.d (service start blocker)
#
# What is policy-rc.d?
#   - Script that controls which services can auto-start
#   - Debian/Devuan specific (not on Red Hat/Arch)
#   - Invoked by init scripts before starting services
#   - Exit code: 0 = allow, 101 = deny
#
# Why Block Services?
#   - During bootstrap, we don't want network services running
#   - SSH server starting = security risk (default credentials)
#   - Database servers starting = unnecessary resource usage
#   - Web servers starting = potential attack surface
#
# Kali Strategy:
#   - Allow essential services (dbus, udev, time sync, network)
#   - Block network servers (SSH, web, database, FTP)
#   - User enables services manually after configuration
#
# Implementation:
#   - Whitelist: Essential services (exit 0)
#   - Blacklist: Network servers (exit 101)
#   - Default: Allow everything else (exit 0)
#
# Service Categories:
#   Whitelist (Always Allow):
#     - dbus, udev: Essential system services
#     - cryptdisks: Required for unlocking drives
#     - rsyslog: Logging (need logs for debugging)
#     - lightdm: Display manager (need GUI login)
#     - acpid, tlp: Power management (critical for laptops)
#     - network-manager: Network connectivity (need internet)
#     - wpa_supplicant: WiFi (need wireless)
#     - chrony, ntp: Time sync (critical for CMOS battery issues)
#   
#   Blacklist (Always Deny):
#     - apache2, nginx: Web servers
#     - mysql, postgresql: Database servers
#     - ssh, sshd: Remote access
#     - vsftpd, proftpd: FTP servers
#     - postfix, exim4: Mail servers
#     - samba, nfs: File sharing
#     - openvpn, wireguard: VPN servers
#
# Alternative: Deny-by-Default
#   - Change final "exit 0" to "exit 101"
#   - Only whitelisted services start
#   - More secure, but requires explicit whitelist for everything
configure_policy_rcd() {
    log_info "Installing policy-rc.d (Kali-style: block network services only)..."
    
    # Generate /usr/sbin/policy-rc.d using HEREDOC
    # 'EOF' is quoted, so variables don't expand (we want literal $1)
    cat > "$CHROOT_TARGET/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
# Kali-style policy-rc.d: prevent network services from auto-starting
# Exit codes: 0 = allow, 101 = deny

# Whitelist: Always allow these essential services
case "$1" in
    dbus|udev|eudev|elogind|consolekit)
        exit 0
        ;;
    # Boot/crypto
    cryptdisks|cryptdisks-early|cryptsetup|cryptsetup-early)
        exit 0
        ;;
    # Logging
    rsyslog|syslog-ng)
        exit 0
        ;;
    # Display/session management
    lightdm|gdm3|sddm|xdm|slim)
        exit 0
        ;;
    # Power management (critical for laptops)
    acpid|tlp|laptop-mode-tools|thermald|cpufrequtils|irqbalance)
        exit 0
        ;;
    # Audio
    pulseaudio|pipewire|alsa-utils)
        exit 0
        ;;
    # Time sync (critical for CMOS battery issues)
    chrony|systemd-timesyncd|ntp|ntpd|openntpd)
        exit 0
        ;;
    # Network connectivity (essential for laptop)
    network-manager|NetworkManager|wicd|connman)
        exit 0
        ;;
    # DHCP client (not server!)
    dhclient|dhcpcd|dhcpcd5)
        exit 0
        ;;
    # Wireless
    wpa_supplicant|iwd)
        exit 0
        ;;
    # Input methods
    ibus|fcitx|fcitx5)
        exit 0
        ;;
    # Scheduled tasks
    cron|anacron)
        exit 0
        ;;
    # Printer client (not server)
    cups-browsed)
        exit 0
        ;;
esac

# Blacklist: Block these network services
case "$1" in
    # Web servers
    apache2|nginx|lighttpd|httpd)
        exit 101
        ;;
    # Database servers
    mysql|mariadb|postgresql|mongodb|redis*|memcached)
        exit 101
        ;;
    # SSH/Remote access
    ssh|sshd|openssh-server)
        exit 101
        ;;
    # FTP
    vsftpd|proftpd|pure-ftpd)
        exit 101
        ;;
    # Mail servers
    postfix|exim4|sendmail|dovecot)
        exit 101
        ;;
    # DNS servers
    bind9|named|dnsmasq|unbound)
        exit 101
        ;;
    # Samba/NFS
    smbd|nmbd|samba|nfs-*|rpcbind)
        exit 101
        ;;
    # DHCP servers
    isc-dhcp-server|dhcpd)
        exit 101
        ;;
    # VPN servers
    openvpn|wireguard)
        exit 101
        ;;
    # CUPS (printing)
    cups|cupsd)
        exit 101
        ;;
    # Avahi/mDNS
    avahi-daemon|avahi)
        exit 101
        ;;
    # Bluetooth
    bluetooth|bluez)
        exit 101
        ;;
    # Proxy servers
    squid|privoxy|tinyproxy)
        exit 101
        ;;
    # Metasploit/pentesting services
    metasploit|postgresql@*-metasploit)
        exit 101
        ;;
esac

# Default: allow everything else
# Change to 'exit 101' if you want deny-by-default
exit 0
EOF
    
    # Make executable
    chmod +x "$CHROOT_TARGET/usr/sbin/policy-rc.d"
    
    log_success "policy-rc.d installed (Kali-style)"
}
# Configure apt sources is designed to detect the version we're installing.
# I'm not sure if Kali would accept the new style .sources file but that might be something 
# worth looking into at later date, if I ever return to it's origins as a Kali Bootstrap script
# after I figure out how to rip out systemd completely and replace it with s6 or openrc or 
# literally anything else

configure_apt_sources() {
    log_info "Configuring APT sources (DEB822 format)..."
    
    mkdir -p "$CHROOT_TARGET/etc/apt/sources.list.d"
    
    # Determine if this is a stable release (has -updates and -security)
    case "$DEVUAN_SUITE" in
        excalibur|daedalus|chimaera|beowulf|ascii|jessie)
            # Stable releases have -updates and -security
            cat > "$CHROOT_TARGET/etc/apt/sources.list.d/devuan.sources" <<EOF
## Devuan ${DEVUAN_SUITE} (stable)

Types: deb
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE} ${DEVUAN_SUITE}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64

Types: deb-src
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE} ${DEVUAN_SUITE}-updates
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64

Types: deb
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64

Types: deb-src
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE}-security
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64
EOF
            ;;
        freia|ceres)
            # Testing/unstable - just the main suite, no -updates or -security
            cat > "$CHROOT_TARGET/etc/apt/sources.list.d/devuan.sources" <<EOF
## Devuan ${DEVUAN_SUITE} (testing/unstable)

Types: deb
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE}
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64

Types: deb-src
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE}
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64
EOF
            ;;
        *)
            log_warning "Unknown suite '$DEVUAN_SUITE', assuming testing/unstable format"
            cat > "$CHROOT_TARGET/etc/apt/sources.list.d/devuan.sources" <<EOF
## Devuan ${DEVUAN_SUITE}

Types: deb
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE}
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64

Types: deb-src
URIs: ${DEVUAN_MIRROR}
Suites: ${DEVUAN_SUITE}
Components: main contrib non-free non-free-firmware
Signed-By: /usr/share/keyrings/devuan-archive-keyring.gpg
Architectures: amd64
EOF
            ;;
    esac
    
    if [[ -f "$CHROOT_TARGET/etc/apt/sources.list" ]]; then
        mv "$CHROOT_TARGET/etc/apt/sources.list" "$CHROOT_TARGET/etc/apt/sources.list.backup"
    fi
    
    cat > "$CHROOT_TARGET/etc/apt/sources.list" <<'EOF'
# Repository configuration has moved to /etc/apt/sources.list.d/devuan.sources
EOF
    
    log_success "APT sources configured"
}

configure_basic_system() {
    log_info "Configuring basic system settings..."
    
    # Hostname
    echo "$HOSTNAME" > "$CHROOT_TARGET/etc/hostname"
    
    # Hosts file
    cat > "$CHROOT_TARGET/etc/hosts" << EOF
127.0.0.1   localhost
127.0.1.1   $HOSTNAME
::1         localhost ip6-localhost ip6-loopback
EOF
    
    # Locale
    echo "$LOCALE UTF-8" >> "$CHROOT_TARGET/etc/locale.gen"
    
    # Timezone (will be applied in chroot)
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" "$CHROOT_TARGET/etc/localtime"
    
    log_success "Basic system settings configured"
}

configure_target_system() {
    echo "Applying aggressive system configuration to $CHROOT_TARGET..."
# We call this the god mode fix, because we had to godlike write to these directories because the 
# XDG 
# ==========================================
# 1. GLOBAL ENV VARS (The "God Mode" Fix)
# Purpose: Force LightDM, Zsh, and XFCE to use visible Home folders.
# ==========================================
cat <<EOF > "$CHROOT_TARGET/etc/profile.d/00-xdg-custom.sh"
#!/bin/sh
# Visible Folders in Home (No Dots)
export XDG_CONFIG_HOME="\$HOME/Config"
export XDG_CACHE_HOME="\$HOME/Cache"
export XDG_DATA_HOME="\$HOME/Data"
export XDG_STATE_HOME="\$HOME/State"

# Force Zsh to look in the custom folder immediately
export ZDOTDIR="\$XDG_CONFIG_HOME/zsh"
EOF
    chmod +x "$CHROOT_TARGET/etc/profile.d/00-xdg-custom.sh"

    # Create the skeleton directories so they exist for the new user
    mkdir -p "$CHROOT_TARGET/etc/skel/Config"
    mkdir -p "$CHROOT_TARGET/etc/skel/Cache"
    mkdir -p "$CHROOT_TARGET/etc/skel/Data"
    mkdir -p "$CHROOT_TARGET/etc/skel/State"
    
    # Note: GUI and Nvidia hacks have been moved to finalize-install.sh
    # to ensure they run AFTER packages are installed.
}

# No safety checking.  If these directories aren't set correctly before now, they will fucking be
configure_bash_xdg() {
    log_info "Configuring bash for XDG compliance..."
    # System-wide bash environment (sourced by all bash shells)
    cat >> "$CHROOT_TARGET/etc/bash.bashrc" <<'EOF'
# XDG Base Directory Specification
export XDG_CONFIG_HOME="${$HOME/Config}"
export XDG_DATA_HOME="${$HOME/Data}"
export XDG_STATE_HOME="${$HOME/State}"
export XDG_CACHE_HOME="${$HOME/Cache}"
export XDG_RUNTIME_DIR="${/tmp/runtime-$USER}"
[[ -d "$HOME/bin" ]] && PATH="$HOME/bin:$PATH"
export HISTFILE="$XDG_STATE_HOME/bash/history"
mkdir -p "$(dirname "$HISTFILE")" 2>/dev/null
EOF
}


#==============================================================================
# ZSH CONFIGURATION
#==============================================================================
# Yes, There are no quotes in any of those export statements
# No it's not POSIX but it is zsh and if you want to fight about I will 
# and here is the page you can find my justification 
# https://zsh.sourceforge.io/Guide/zshguide05.html#l114
configure_zshenv() {
    log_info "Installing system-wide zshenv..."
    
    mkdir -p "$CHROOT_TARGET/etc/zsh"
    
    cat > "$CHROOT_TARGET/etc/zsh/zshenv" <<'EOF'
# /etc/zsh/zshenv - System-wide environment for zsh
#
# DEPLOYMENT: This file is installed during system bootstrap
# Forced Consistency: XDG Variables defined here AND in /etc/profile.d/
#
# WHY THIS FILE EXISTS:
#   /etc/zsh/zshenv is sourced by ALL zsh instances:
#   - Interactive shells
#   - Non-interactive shells (scripts with #!/usr/bin/zsh)
#   - Login shells
#   - Non-login shells
#   - Even zsh -c 'command'
#
#   This makes it the ONE reliable place to set environment variables
#   that absolutely must be present everywhere.
#
# WHAT GOES HERE:
#   - XDG Base Directory variables (so all programs respect them)
#   - PATH additions that scripts depend on
#   - Locale settings (LANG, LC_*)
#
# WHAT DOES NOT GO HERE:
#   - Aliases (not available in non-interactive shells anyway)
#   - Prompt configuration
#   - Completion setup
#   - Anything slow (this runs for EVERY zsh invocation)

# --- XDG Base Directories ---
# Set defaults if not already set
# We use Capitalized, Visible folders ($HOME/Config) explicitly.
# No hidden .local/share rubbish.

# User-specific configuration files
: ${XDG_CONFIG_HOME:=$HOME/Config}
export XDG_CONFIG_HOME

# User-specific data files
export XDG_DATA_HOME=$HOME/Data

# User-specific state files (logs, history, recently used)
export XDG_STATE_HOME=$HOME/State

# User-specific cache files (non-essential)
export XDG_CACHE_HOME=$HOME/Cache

# User-specific runtime files (sockets, named pipes)
# Usually set by the system (pam_systemd sets it to /run/user/$UID)
# Only set if not already defined
export XDG_RUNTIME_DIR=/tmp/runtime-$USER

# --- Locale ---
# Ensure UTF-8 locale; adjust to your preference
# Uncomment if your system doesn't set this properly
# export LANG=en_US.UTF-8

# --- PATH Additions ---
# Add user binary directories to PATH
# These are added early so they're available to scripts

# User's personal bin directory
[[ -d "$HOME/bin" ]] && PATH=$HOME/bin:$PATH



export PATH

# --- ZDOTDIR ---
# Force zsh to look for configs here.
export ZDOTDIR=XDG_CONFIG_HOME/zsh
EOF
    
    log_success "System-wide zshenv installed"
}

#==============================================================================
# HACK FONT FOR HACKER VIBES
#==============================================================================
# This a place holder until I can figure out the best way to add nerd fonts to the install
# potential function names configure_hack_font, configure_nerd_font, cyberpunk_fon_for terminal
#
#
#==============================================================================
# GRUB CONFIGURATION
#==============================================================================

configure_grub() {
    log_info "Preparing for GRUB installation (will complete in chroot)..."
    
    # Create GRUB config (chroot will finalize)
    cat > "$CHROOT_TARGET/etc/default/grub" << 'EOF'
# GRUB Configuration

GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="GNU/Linux"

# Kernel parameters
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
GRUB_CMDLINE_LINUX="rootflags=subvol=@ rootdelay=10"

# Display
GRUB_GFXMODE=1920x1080
GRUB_GFXPAYLOAD_LINUX=keep

# Enable cryptodisk for encrypted /boot (if needed in future)
GRUB_ENABLE_CRYPTODISK=n
EOF
    
    log_success "GRUB config prepared"
}

#==============================================================================
# CHROOT SCRIPT GENERATION
#==============================================================================

generate_chroot_script() {
    log_info "Generating chroot finalization script..."
    
# -------------------------------------------------------------------------
# PART 1: HEADER (Unquoted)
# This expands variables from the HOST script into the file.
# -------------------------------------------------------------------------
    cat > "$CHROOT_TARGET/root/finalize-install.sh" <<EOF
#!/usr/bin/zsh
# finalize-install.sh - Run inside chroot to complete installation

set -euo pipefail

# --- INJECTED VARIABLES ---
WHO_IS_THIS="${WHO_IS_THIS}"
WHAT_YOU_USE="${WHAT_YOU_USE}"
WHERE_YOU_BELONG="${WHERE_YOU_BELONG}"
USB_KEYFILE_PATH="${USB_KEYFILE_PATH}"
PARTLABEL_USB="${PARTLABEL_USB}"
SKEL="${SKEL}"

# Color output functions
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "\${BLUE}[INFO]\${NC} \$1"; }
log_success() { echo -e "\${GREEN}[SUCCESS]\${NC} \$1"; }
log_warning() { echo -e "\${YELLOW}[WARNING]\${NC} \$1"; }
log_error() { echo -e "\${RED}[ERROR]\${NC} \$1"; }


EOF

# -------------------------------------------------------------------------
# PART 2: BODY (Quoted)
# This appends the logic literally. No variables here are expanded by the host.
# -------------------------------------------------------------------------
    cat >> "$CHROOT_TARGET/root/finalize-install.sh" <<'CHROOT_EOF'

#==============================================================================
# LOCALE AND TIMEZONE
#==============================================================================

log_info "Generating locales..."
locale-gen

log_info "Setting timezone..."
dpkg-reconfigure -f noninteractive tzdata

#==============================================================================
# PACKAGE MANAGEMENT
#==============================================================================

log_info "Updating package lists..."
apt update

log_info "Upgrading base system..."
apt upgrade -y

log_info "Installing kernel and firmware..."
apt install -y \
    linux-image-amd64 \
    linux-headers-amd64 \
    firmware-linux \
    firmware-linux-nonfree \
    firmware-misc-nonfree \
    intel-microcode \
    amd64-microcode \
    bluez-firmware \
    firmware-atheros \
    firmware-intel-graphics \
    firmware-iwlwifi
    firmware-mediatek \
    firmware-intel-misc \
    firmware-intel-sound

log_info "Installing cryptsetup and filesystem tools..."
apt install -y \
    cryptsetup \
    cryptsetup-initramfs \
    btrfs-progs \
    dosfstools \
    e2fsprogs 

log_info "Installing bootloader..."
apt install -y \
    grub-efi-amd64 \
    grub-efi-amd64-bin \
    efibootmgr

log_info "Installing essential system utilities..."
apt install -y \
    vim \
    tmux \
    htop \
    ncdu \
    aptitude \
    lnav \
    tree \
    rsync \
    screen \
    less \
    man-db \
    manpages \
    sudo \
    dbus \
    
log_info "Installing shell and development tools..."
apt install -y \
    zsh \
    zsh-syntax-highlighting \
    zsh-autosuggestions \
    git \
    curl \
    wget \
    build-essential \
    pkg-config

log_info "Installing network stack..."
apt install -y \
    network-manager \
    wireless-tools \
    wpasupplicant \
    iw \
    rfkill \
    net-tools \
    dnsutils \
    iputils-ping \
    iproute2 \
    ethtool

log_info "Installing system services..."
apt install -y \
    elogind \
    libpam-elogind \
    dbus-x11 \
    acpid \
    chrony \
	libvirt-daemon-system \
    libvirt-clients \
    qemu-kvm \
    bluez \
    bluez-tools

log_info "Installing hardware support..."
apt install -y \
    pciutils \
    usbutils \
    lshw \
    smartmontools \
    hdparm \
	nvme-cli

log_info "Installing Desktop Environment (XFCE4)..."
# We install a minimal but functional desktop.
# - task-xfce-desktop: The core environment
# - lightdm: The login manager
# - arc-theme/papirus: Dark mode essentials
apt install -y \
    task-xfce-desktop \
    xfce4-goodies \
    lightdm \
    network-manager-gnome \
    pulseaudio pavucontrol \
    firefox-esr


# Theme Assets
apt install -y \
    arc-theme \
    papirus-icon-theme 

# Tools needed for the NEXT iteration of the Quine
apt install -y \
    arch-install-scripts \
    debootstrap \
    cryptsetup \
    parted \
    gdisk \
    btrfs-progs \
    wget


log_info "Installing Nvidia Drivers (Proprietary)..."
# This pulls the kernel modules and the settings panel.
# We handled the 'nouveau' blacklist in the config phase.
# We allow this to "fail" because the postinst script is known to be buggy
# and we have a fix ready in the next step.
apt install -y \
    nvidia-driver \
    firmware-misc-nonfree \
    nvidia-smi \
    nvidia-settings || true

log_info "Applying post-install configuration fixes..."

# 1. Nvidia Persistence Hack & DPKG Repair
# We force the postinst to pass and then reconfigure everything to clear locks.
mkdir -p /var/lib/dpkg/info
echo "#!/bin/sh" > /var/lib/dpkg/info/nvidia-persistenced.postinst
echo "exit 0" >> /var/lib/dpkg/info/nvidia-persistenced.postinst
chmod +x /var/lib/dpkg/info/nvidia-persistenced.postinst

log_info "Ensuring package database is consistent..."
dpkg --configure -a || log_warning "dpkg configure returned an error, but proceeding..."

# 2. GUI PRE-CONFIGURATION (Dark Mode Default)
# Purpose: Force Arc-Dark/Papirus now that packages are actually installed.

# A. Force LightDM (Login Screen) to Dark Mode
GREETER_CONF="/etc/lightdm/lightdm-gtk-greeter.conf"
if [ -f "$GREETER_CONF" ]; then
    sed -i 's/^#\?theme-name=.*/theme-name=Arc-Dark/' "$GREETER_CONF"
    sed -i 's/^#\?icon-theme-name=.*/icon-theme-name=Papirus-Dark/' "$GREETER_CONF"
    sed -i 's/^#\?background=.*/background=#2f343f/' "$GREETER_CONF"
else
    log_warning "LightDM config not found at $GREETER_CONF. Skipping Greeter theme."
fi

# B. Force XFCE (Desktop) to Dark Mode for all new users
XFCE_XML_DIR="/etc/xdg/xfce4/xfconf/xfce-perchannel-xml"
mkdir -p "$XFCE_XML_DIR"

# Appearance Settings: Arc-Dark + Papirus
cat <<EOF > "$XFCE_XML_DIR/xsettings.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xsettings" version="1.0">
  <property name="Net" type="empty">
    <property name="ThemeName" type="string" value="Arc-Dark"/>
    <property name="IconThemeName" type="string" value="Papirus-Dark"/>
  </property>
</channel>
EOF

# Window Manager Settings: Arc-Dark Borders
cat <<EOF > "$XFCE_XML_DIR/xfwm4.xml"
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfwm4" version="1.0">
  <property name="general" type="empty">
    <property name="theme" type="string" value="Arc-Dark"/>
  </property>
</channel>
EOF



log_success "Post-install configuration complete (Nvidia hacked, Dpkg cleared, Dark Mode enforced)."

#==============================================================================
# SYSCTL TWEAKS
#==============================================================================
echo ">>> Appending Kernel Overrides to main sysctl.conf..."

cat <<EOF >> /etc/sysctl.conf

# --- CUSTOM BOOTSTRAP OVERRIDES ---
# Allow unprivileged users to run dmesg
kernel.dmesg_restrict = 0

# Disable privileged ports (Allow users to bind ports 0-1023)
net.ipv4.ip_unprivileged_port_start = 0
# ----------------------------------
EOF

#==============================================================================
# INITRAMFS CONFIGURATION
#==============================================================================

log_info "Configuring cryptsetup for initramfs..."

# Ensure cryptsetup hooks are enabled
mkdir -p /etc/cryptsetup-initramfs
cat > /etc/cryptsetup-initramfs/conf-hook <<EOF
# Cryptsetup initramfs hook configuration
CRYPTSETUP=y
KEYFILE_PATTERN="/dev/disk/by-partlabel/${PARTLABEL_USB}:${USB_KEYFILE_PATH}"
EOF

# Configure initramfs to include USB drivers early
log_info "Adding USB modules to initramfs..."
cat >> /etc/initramfs-tools/modules <<EOF

# USB support for keyfile on boot
usb_storage
uas
sd_mod
# Filesystem support for the key drive (CRITICAL)
ext4
nls_utf8
nls_cp437
crc32
EOF

# Ensure resume is disabled (no swap)
log_info "Disabling resume in initramfs..."
echo "RESUME=none" > /etc/initramfs-tools/conf.d/resume

log_info "Rebuilding initramfs for all kernels..."
update-initramfs -c -k all

#==============================================================================
# BOOTLOADER
#==============================================================================

log_info "Installing GRUB to EFI..."
grub-install \
    --target=x86_64-efi \
    --efi-directory=/boot/efi \
    --bootloader-id="GNU/Linux" \
    --recheck || {
    log_error "GRUB installation failed!"
    exit 1
}

log_info "Generating GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg || {
    log_error "GRUB config generation failed!"
    exit 1
}

#==============================================================================
# INIT SYSTEM SERVICES
#==============================================================================

log_info "Configuring SysVinit services..."

# Crypto
update-rc.d cryptdisks defaults
update-rc.d cryptdisks-early defaults

# Networking
update-rc.d networking defaults
update-rc.d network-manager defaults

# System services
update-rc.d dbus defaults
update-rc.d elogind defaults
update-rc.d acpid defaults
update-rc.d chrony defaults
update-rc.d cron defaults
update-rc.d libvirtd defaults
update-rc.d bluetooth defaults

log_success "Services configured"

#==============================================================================
# SUDO CONFIGURATION
#==============================================================================

log_info "Configuring sudo..."

# Allow sudo group to use sudo
if ! grep -q "^%sudo" /etc/sudoers; then
    echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers
fi

#==============================================================================
# SKELETON DIRECTORY SETUP (/etc/skel) - XDG & ZSH Logic
#==============================================================================

log_info "Configuring /etc/skel XDG structure..."

SKEL="/etc/skel"

# 1. Create Base Hierarchy (CAPITALIZED to match God Mode XDG vars)
mkdir -p "$SKEL/Config/zsh/"{env,aliases,functions,plugins,completions,local}
mkdir -p "$SKEL/Data"
mkdir -p "$SKEL/State"
mkdir -p "$SKEL/Cache/zsh"
mkdir -p "$SKEL/bin/"{bootstrap,utilities,personal}

# 2. XDG User Directories
mkdir -p "$SKEL/Desktop" "$SKEL/Public" "$SKEL/Music"
mkdir -p "$SKEL/Downloads/"{Quarantine,Sort,Move}
mkdir -p "$SKEL/Videos/"{Anime,Movies,TV,Porn}
mkdir -p "$SKEL/Documents/"{Personal,Business,Bills}
mkdir -p "$SKEL/Library/"{Fiction,Research,Non-Fiction,Manga,Comics,Hentai}
mkdir -p "$SKEL/Templates/"{Documents,Spreadsheets,Presentations,Scripts,Code}
mkdir -p "$SKEL/Pictures/"{Memes,Work,Personal,Spicy}

# 3. Write user-dirs.dirs
cat > "$SKEL/Config/user-dirs.dirs" << 'EOF'
XDG_DESKTOP_DIR="$HOME/Desktop"
XDG_DOWNLOAD_DIR="$HOME/Downloads"
XDG_TEMPLATES_DIR="$HOME/Templates"
XDG_PUBLICSHARE_DIR="$HOME/Public"
XDG_DOCUMENTS_DIR="$HOME/Documents"
XDG_MUSIC_DIR="$HOME/Music"
XDG_PICTURES_DIR="$HOME/Pictures"
XDG_VIDEOS_DIR="$HOME/Videos"
EOF

# 4. The Master .zshrc
cat > "$SKEL/Config/zsh/.zshrc" << 'MASTER_ZSHRC'
# ~/.zshrc - Distro-agnostic ZSH configuration
# Design principles: XDG compliance, Modular loading, Graceful degradation

# --- XDG Base Directories ---
# Inherit from zshenv, but set defaults just in case
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/Config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/Data}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/State}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/Cache}"

mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME" "$XDG_CACHE_HOME" 2>/dev/null
export ZDOTDIR="${XDG_CONFIG_HOME}/zsh"

# --- Shell Options ---
setopt autocd interactivecomments magicequalsubst nonomatch notify
setopt numericglobsort promptsubst
WORDCHARS='_-'
PROMPT_EOL_MARK=""

# --- History ---
HISTFILE="${XDG_STATE_HOME}/zsh/history"
mkdir -p "$(dirname "$HISTFILE")" 2>/dev/null
HISTSIZE=50000
SAVEHIST=50000
setopt hist_expire_dups_first hist_ignore_dups hist_ignore_space
setopt hist_verify extended_history hist_reduce_blanks
alias history="history 0"

# --- Keybindings (Emacs) ---
bindkey -e
bindkey ' ' magic-space
bindkey '^U' backward-kill-line
bindkey '^[[3;5~' kill-word
bindkey '^[[3~' delete-char
bindkey '^[[1;5C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[5~' beginning-of-buffer-or-history
bindkey '^[[6~' end-of-buffer-or-history
bindkey '^[[H' beginning-of-line
bindkey '^[[F' end-of-line
bindkey '^[[Z' undo

# --- Completion ---
autoload -Uz compinit
_comp_dump="${XDG_CACHE_HOME}/zsh/zcompdump"
mkdir -p "$(dirname "$_comp_dump")" 2>/dev/null

if [[ -f "$_comp_dump" ]]; then
    _dump_age=$(stat -c '%Y' "$_comp_dump" 2>/dev/null || stat -f '%m' "$_comp_dump" 2>/dev/null)
    if [[ -n "$_dump_age" ]] && (( $(date +%s) - _dump_age < 86400 )); then
        compinit -d "$_comp_dump" -C
    else
        compinit -d "$_comp_dump"
    fi
else
    compinit -d "$_comp_dump"
fi
unset _dump_age _comp_dump

zstyle ':completion:*' menu select
zstyle ':completion:*' completer _expand _complete _correct _approximate
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"

# --- Colors ---
if command -v dircolors &>/dev/null; then
    eval "$(dircolors -b)"
    export LS_COLORS="$LS_COLORS:ow=30;44:"
fi

# --- Prompt ---
_setup_default_prompt() {
    local nl=$'\n'
    if [[ "$EUID" -eq 0 ]]; then
        PROMPT="%F{red}%~${nl}#%f "
    else
        PROMPT="%F{blue}%~${nl}%F{green}$%f "
    fi
}
_setup_default_prompt

# --- Terminal Title ---
case "$TERM" in
    xterm*|rxvt*|Eterm|aterm|kterm|gnome*|alacritty|foot|kitty|tmux*)
        precmd() { print -Pnr -- $'\e]0;%n@%m: %~\a'; }
        ;;
esac

# --- Plugins ---
_source_first_found() {
    local f
    for f in "$@"; do
        if [[ -f "$f" ]]; then source "$f"; return 0; fi
    done
    return 1
}

# Syntax Highlighting
if _source_first_found \
    "$ZSHCONFIG/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" \
    /usr/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh \
    /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
then
    ZSH_HIGHLIGHT_HIGHLIGHTERS=(main brackets pattern)
fi

# Autosuggestions
if _source_first_found \
    "$ZSHCONFIG/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" \
    /usr/share/zsh-autosuggestions/zsh-autosuggestions.zsh \
    /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
then
    ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=244'
    ZSH_AUTOSUGGEST_STRATEGY=(history completion)
fi

# Command Not Found
_source_first_found /etc/zsh_command_not_found /usr/share/zsh/functions/command-not-found.zsh

# --- Modular Loading ---
_load_zsh_dir() {
    local dir="$1"
    [[ ! -d "$dir" ]] && return
    local f
    for f in "$dir"/*.zsh(N); do source "$f"; done
}

_load_zsh_dir "$ZSHCONFIG/env"
_load_zsh_dir "$ZSHCONFIG/aliases"
_load_zsh_dir "$ZSHCONFIG/functions"
_load_zsh_dir "$ZSHCONFIG/completions"
_load_zsh_dir "$ZSHCONFIG/plugins"
_load_zsh_dir "$ZSHCONFIG/local"

# Starship Support
if command -v starship &>/dev/null; then eval "$(starship init zsh)"; fi

# Cleanup
unfunction _source_first_found _load_zsh_dir _setup_default_prompt 2>/dev/null
MASTER_ZSHRC

# 5. Remove legacy zshrc
[ -f "$SKEL/.zshrc" ] && rm "$SKEL/.zshrc"

# 6. Inject Environment Modules (ENV)
cat > "$SKEL/Config/zsh/env/rust.zsh" << 'EOF'
export RUST_HOME="${HOME}/bin/rust"
[[ ! -d "$RUST_HOME" ]] && mkdir -p "$RUST_HOME"
export RUSTUP_HOME="${RUST_HOME}/rustup"
export CARGO_HOME="${RUST_HOME}/cargo"
if [[ -d "${CARGO_HOME}/bin" ]]; then export PATH="${CARGO_HOME}/bin:$PATH"; fi
EOF

cat > "$SKEL/Config/zsh/env/python.zsh" << 'EOF'
export PYTHON_HOME="${HOME}/bin/python"
[[ ! -d "$PYTHON_HOME" ]] && mkdir -p "$PYTHON_HOME"
if command -v pipx &>/dev/null; then
    export PIPX_HOME="${PYTHON_HOME}/pipx/venvs"
    export PIPX_BIN_DIR="${PYTHON_HOME}/pipx/bin"
    export PATH="${PIPX_BIN_DIR}:$PATH"
fi
if [[ -d "${PYTHON_HOME}/pyenv" ]]; then
    export PYENV_ROOT="${PYTHON_HOME}/pyenv"
    export PATH="${PYENV_ROOT}/bin:$PATH"
    eval "$(pyenv init -)"
fi
export VIRTUAL_ENV_DISABLE_PROMPT=1
EOF

cat > "$SKEL/Config/zsh/env/go.zsh" << 'EOF'
export GOPATH="${HOME}/bin/go"
[[ ! -d "$GOPATH" ]] && mkdir -p "$GOPATH"
export PATH="${GOPATH}/bin:$PATH"
EOF

cat > "$SKEL/Config/zsh/env/java.zsh" << 'EOF'
export JAVA_HOME_BASE="${HOME}/bin/java"
[[ ! -d "$JAVA_HOME_BASE" ]] && mkdir -p "$JAVA_HOME_BASE"
export SDKMAN_DIR="${JAVA_HOME_BASE}/sdkman"
if [[ -s "${SDKMAN_DIR}/bin/sdkman-init.sh" ]]; then source "${SDKMAN_DIR}/bin/sdkman-init.sh"; fi
EOF

cat > "$SKEL/Config/zsh/env/javascript.zsh" << 'EOF'
export JS_HOME="${HOME}/bin/javascript"
[[ ! -d "$JS_HOME" ]] && mkdir -p "$JS_HOME"
export NPM_CONFIG_PREFIX="${JS_HOME}/npm-global"
export PATH="${NPM_CONFIG_PREFIX}/bin:$PATH"
export NVM_DIR="${JS_HOME}/nvm"
if command -v fnm &>/dev/null; then eval "$(fnm env --use-on-cd)"; fi
EOF

cat > "$SKEL/Config/zsh/env/ruby.zsh" << 'EOF'
export RBENV_ROOT="${HOME}/bin/ruby"
if [[ -d "$RBENV_ROOT" ]]; then
    export PATH="${RBENV_ROOT}/bin:$PATH"
    if command -v rbenv &>/dev/null; then eval "$(rbenv init - zsh)"; fi
fi
EOF

cat > "$SKEL/Config/zsh/env/elixir.zsh" << 'EOF'
export BEAM_HOME="${HOME}/bin/beam"
[[ ! -d "$BEAM_HOME" ]] && mkdir -p "$BEAM_HOME"
export ASDF_DATA_DIR="${BEAM_HOME}/asdf"
export ASDF_CONFIG_FILE="${XDG_CONFIG_HOME}/asdf/asdfrc"
if [[ -f "${ASDF_DATA_DIR}/asdf.sh" ]]; then source "${ASDF_DATA_DIR}/asdf.sh"; fi
EOF

# 7. Inject Aliases
cat > "$SKEL/Config/zsh/aliases/core.zsh" << 'EOF'
alias cp='cp -iv'
alias mv='mv -iv'
alias rm='rm -Iv'
alias mkdir='mkdir -pv'
alias df='df -h'
alias du='du -h'
alias free='free -h'
alias ll='ls -lAh'
alias la='ls -A'
alias grep='grep --color=auto'
alias ip='ip --color=auto' 2>/dev/null
EOF

cat > "$SKEL/Config/zsh/aliases/apt.zsh" << 'EOF'
alias retag='sudo aptitude add-user-tag'
alias untag='sudo aptitude remove-user-tag'
alias tag-orphans='aptitude search "?user-tag(?not(~g~i))"'
alias apt-update='sudo apt update'
alias apt-upgrade='sudo apt full-upgrade'
alias apt-clean='sudo apt-get autopurge'
alias apt-sizes='dpkg-query -W --showformat="${Installed-Size}\t${Package}\n" | sort -rn | head -20'
EOF

cat > "$SKEL/Config/zsh/aliases/gpg.zsh" << 'EOF'
alias gpg-list-secrets='gpg --list-secret-keys --with-subkey-fingerprint'
alias gpg-fix='gpgconf --kill gpg-agent && gpgconf --launch gpg-agent'
EOF

cat > "$SKEL/Config/zsh/aliases/colors.zsh" << 'EOF'
alias ls='ls --color=auto'
alias diff='diff --color'
EOF

cat > "$SKEL/Config/zsh/aliases/xdg-fixes.zsh" << 'EOF'
alias wget="wget --hsts-file=$XDG_DATA_HOME/wget-hsts"
alias adb='HOME="$XDG_DATA_HOME"/android adb'
EOF

# 8. Inject Functions
cat > "$SKEL/Config/zsh/functions/admin_tools.zsh" << 'EOF'
upgrayyedd() {
  echo "🔄 Updating package lists..."; sudo apt update || return 1
  echo "\n📦 Upgradable:"; apt list --upgradable
  read -q "confirm?Proceed? (y/n) " || return 1
  sudo apt full-upgrade || return 1
  echo "\n🧹 Cleanup candidates:"; apt-get -s autopurge | grep '^Remv'
  read -q "confirm2?Cleanup? (y/n) " && sudo apt-get autopurge
  echo "✅ Done"
}
gpg-copy-pub() {
  gpg --export --armor "${1:-}" | xclip -selection clipboard
  echo "✓ Key copied"
}
EOF

cat > "$SKEL/Config/zsh/functions/tagging.zsh" << 'EOF'
tag-search() { aptitude search "?user-tag($1)"; }
tag-batch() { local tag="$1"; shift; sudo aptitude add-user-tag "$tag" "$@"; }
apt-tag() { local tag=$1; shift; sudo aptitude install --add-user-tag="$tag" "$@"; }
pkg-info() { aptitude show "$1"; echo "\nTags:"; aptitude search "?exact-name($1)" -F '%T'; }
EOF

# 9. Utilities (Live Env Mount)
mkdir -p "$SKEL/bin/bootstrap"
cat > "$SKEL/bin/bootstrap/mount-live.sh" << 'EOF'
#!/bin/bash
export ROOTDRIVE=/dev/nvme0n1
export HOMEDRIVE=/dev/sda
export BOOTDRIVE=/dev/sdc1
mkdir -p /tmp/bootkey
sudo mount $BOOTDRIVE /tmp/bootkey
[ ! -e /dev/mapper/cryptroot ] && sudo cryptsetup open ${ROOTDRIVE}p3 cryptroot --key-file /tmp/bootkey/keyfile
[ ! -e /dev/mapper/crypthome ] && sudo cryptsetup open ${HOMEDRIVE}1 crypthome --key-file /tmp/bootkey/keyfile
sudo mount -o subvol=@ /dev/mapper/cryptroot /mnt
sudo mount /dev/disk/by-partlabel/boot /mnt/boot
sudo mount /dev/disk/by-partlabel/ESP /mnt/boot/efi
sudo mount -o subvol=@home /dev/mapper/crypthome /mnt/home
echo "System mounted at /mnt"
EOF
chmod +x "$SKEL/bin/bootstrap/mount-live.sh"

# 10. Backup passphrase utility
cat > "$SKEL/bin/bootstrap/add-backup-passphrase.sh" << 'EOF'
#!/bin/bash
# add-backup-passphrase.sh - Add backup passphrase to LUKS volumes
#
# This allows you to unlock your encrypted drives without the USB keyfile
# Useful if the USB drive is lost or damaged

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Configuration - adjust if your partition labels differ
CRYPTROOT_DEVICE="/dev/disk/by-partlabel/cryptroot"
CRYPTHOME_DEVICE="/dev/disk/by-partlabel/crypthome"
USB_KEYFILE_DEVICE="/dev/disk/by-partlabel/bootkey"
USB_KEYFILE_PATH="/keyfile"

echo "========================================"
echo "  Add Backup Passphrase to LUKS Volumes"
echo "========================================"
echo ""
log_warning "This will add a passphrase to your encrypted volumes"
log_warning "You will need the USB keyfile currently to proceed"
echo ""

# Check if USB keyfile is available
if [[ ! -b "$USB_KEYFILE_DEVICE" ]]; then
    log_error "USB keyfile drive not found at $USB_KEYFILE_DEVICE"
    log_error "Please insert the USB keyfile drive and try again"
    exit 1
fi

# Mount USB keyfile
log_info "Mounting USB keyfile..."
KEYFILE_MOUNT=$(mktemp -d)
mount "$USB_KEYFILE_DEVICE" "$KEYFILE_MOUNT" || {
    log_error "Failed to mount USB keyfile"
    exit 1
}

# Check if keyfile exists
if [[ ! -f "${KEYFILE_MOUNT}${USB_KEYFILE_PATH}" ]]; then
    log_error "Keyfile not found at ${KEYFILE_MOUNT}${USB_KEYFILE_PATH}"
    umount "$KEYFILE_MOUNT"
    rmdir "$KEYFILE_MOUNT"
    exit 1
fi

log_success "USB keyfile found"
echo ""

# Add passphrase to root partition
log_info "Adding backup passphrase to root partition..."
echo ""
log_info "Enter a strong passphrase (you'll need to type it twice)"
echo ""

if cryptsetup luksAddKey \
    --key-file "${KEYFILE_MOUNT}${USB_KEYFILE_PATH}" \
    "$CRYPTROOT_DEVICE"; then
    log_success "Backup passphrase added to root partition"
else
    log_error "Failed to add passphrase to root partition"
    umount "$KEYFILE_MOUNT"
    rmdir "$KEYFILE_MOUNT"
    exit 1
fi

echo ""

# Add passphrase to home partition
log_info "Adding backup passphrase to home partition..."
echo ""
log_info "Enter the SAME passphrase (or a different one if you prefer)"
echo ""

if cryptsetup luksAddKey \
    --key-file "${KEYFILE_MOUNT}${USB_KEYFILE_PATH}" \
    "$CRYPTHOME_DEVICE"; then
    log_success "Backup passphrase added to home partition"
else
    log_error "Failed to add passphrase to home partition"
    umount "$KEYFILE_MOUNT"
    rmdir "$KEYFILE_MOUNT"
    exit 1
fi

# Cleanup
umount "$KEYFILE_MOUNT"
rmdir "$KEYFILE_MOUNT"

echo ""
echo "========================================"
log_success "Backup passphrases configured!"
echo "========================================"
echo ""
echo "Important notes:"
echo "  - You can now unlock drives with either the USB keyfile OR passphrase"
echo "  - Keep the USB keyfile safe as the primary unlock method"
echo "  - The passphrase is for emergency recovery only"
echo ""
echo "To test passphrase unlock (from live USB):"
echo "  cryptsetup open /dev/disk/by-partlabel/cryptroot cryptroot"
echo "  (it will prompt for passphrase)"
echo ""
echo "To view LUKS key slots:"
echo "  cryptsetup luksDump /dev/disk/by-partlabel/cryptroot"
echo ""

EOF
chmod +x "$SKEL/bin/bootstrap/add-backup-passphrase.sh"

log_success "Backup passphrase utility created"
log_success "/etc/skel configured with XDG environment and Master Zshrc."

#==============================================================================
# USER CREATION
#==============================================================================

log_info "Creating user account: ${WHO_IS_THIS}..."

if id "${WHO_IS_THIS}" &>/dev/null; then
    log_warning "User ${WHO_IS_THIS} already exists."
else
    # useradd -m will now copy our perfectly populated /etc/skel
    useradd -m -s "${WHAT_YOU_USE}" -G "${WHERE_YOU_BELONG}" "${WHO_IS_THIS}"
    
    log_info "Set password for ${WHO_IS_THIS}:"
    passwd "${WHO_IS_THIS}"
    
    log_success "User ${WHO_IS_THIS} created with ${WHAT_YOU_USE} as default shell"
fi

#==============================================================================
# ROOT USER SKELETON
#==============================================================================

log_info "Creating /root directory skeleton (Structure only)..."

# 1. Base ZSH & XDG Structure (Capitalized to match God Mode XDG vars)
# If these don't match XDG_CONFIG_HOME in /etc/zsh/zshenv, root shell will be unconfigured.
mkdir -p "/root/Config/zsh/"{env,aliases,functions,plugins,completions,local}

# 2. XDG Data/State/Cache (Visible Folders)
mkdir -p "/root/Data"
mkdir -p "/root/State"
mkdir -p "/root/Cache/zsh"

# 3. Binaries
mkdir -p "/root/bin/"{bootstrap,utilities,personal}

log_success "/root skeleton created."

#==============================================================================
# ROOT PASSWORD
#==============================================================================

log_info "Setting root password..."
echo ""
passwd root

#==============================================================================
# TRUSTED GROUP IMPLEMENTATION
#==============================================================================
log_info " Configuring 'Trusted' Group Infrastructure..."

# 1. Create the 'trusted' group (system group, hidden)
groupadd -r trusted

# 2. Configure Sudoers (Terminal)
# Only members of 'trusted' get NOPASSWD. Everyone else needs a password.
echo "%trusted ALL=(ALL:ALL) NOPASSWD: ALL" > /target/etc/sudoers.d/trusted
chmod 0440 /target/etc/sudoers.d/trusted

# 3. Configure Polkit (GUI apps like GParted/Synaptic)
# This allows 'trusted' users to bypass the GUI password prompt.
mkdir -p /target/etc/polkit-1/rules.d/
cat <<EOF > /target/etc/polkit-1/rules.d/49-trusted-nopasswd.rules
/* Allow members of the 'trusted' group to execute any action without password */
polkit.addRule(function(action, subject) {
    if (subject.isInGroup("trusted")) {
        return polkit.Result.YES;
    }
});
EOF

#==============================================================================
# UNLOCK 
#==============================================================================

# Inspired by Kali's kali-grant-root but using shell scripting instead
log_info "Adding Unlock script..."
cat > /usr/local/bin/unlock <<EOF
#!/bin/bash
# /usr/local/bin/unlock

if id -nG "$USER" | grep -qw "trusted"; then
    echo "You are already trusted (God Mode)."
else
    echo ">>> Elevating privileges for $USER..."
    echo ">>> You will need to enter your password."
    
    # Add user back to trusted
    su -c "usermod -aG trusted $USER"
    
    echo ">>> Done. Please Log Out and Log Back In to activate God Mode."
fi
EOF

chmod +x /usr/local/bin/unlock


#==============================================================================
# LOCKDOWN
#==============================================================================

# If you have unlocked but need to lockdown
log_info "Adding Lockdown script..."
cat > /usr/local/bin/lockdown <<EOF
#!/bin/bash
# /usr/local/bin/lockdown

# Check if user is actually privileged
if id -nG "$USER" | grep -qw "trusted"; then
    echo ">>> Revoking 'trusted' privileges for $USER..."
    
    # Remove user from the group (requires sudo one last time)
    sudo gpasswd -d "$USER" trusted
    
    echo ">>> Privileges revoked."
    echo ">>> LOGGING OUT IN 3 SECONDS to apply changes..."
    sleep 3
    
    # Force XFCE to logout immediately
    xfce4-session-logout --logout
else
    echo "You are already locked down (standard user)."
fi
EOF

chmod +x /usr/local/bin/lockdown

log_info "Unlock and Lockdown Modes added..."


#==============================================================================
# NETWORK CONFIGURATION
#==============================================================================

log_info "Configuring NetworkManager..."

# Enable NetworkManager to manage all devices
cat > /etc/NetworkManager/conf.d/managed.conf <<EOF
[main]
plugins=ifupdown,keyfile

[ifupdown]
managed=true
EOF

log_success "NetworkManager configured"

#==============================================================================
# SWAP CONFIGURATION (OPTIONAL)
#==============================================================================

log_info "Checking RAM for swap recommendation..."
total_ram_kb=$(grep MemTotal /proc/meminfo | awk '{print $2}')
total_ram_gb=$((total_ram_kb / 1024 / 1024))

if [[ $total_ram_gb -lt 16 ]]; then
    log_warning "System has ${total_ram_gb}GB RAM - swap recommended"
    echo ""
    read -p "Create swap file? (y/n): " create_swap
    
    if [[ "$create_swap" == "y" ]]; then
        # Create swap subvolume if it doesn't exist
        if [[ ! -d /swap ]]; then
            log_info "Creating swap subvolume..."
            mount -o subvol=/ /dev/mapper/cryptroot /mnt
            btrfs subvolume create /mnt/@swap
            umount /mnt
            
            # Add to fstab
            echo "/dev/mapper/cryptroot /swap btrfs defaults,subvol=@swap,nodatacow,noatime 0 0" >> /etc/fstab
            
            # Mount it
            mkdir -p /swap
            mount /swap
        fi
        
        log_info "Creating ${total_ram_gb}GB swap file..."
        
        # Create swapfile
        truncate -s 0 /swap/swapfile
        chattr +C /swap/swapfile
        dd if=/dev/zero of=/swap/swapfile bs=1G count=$total_ram_gb status=progress
        chmod 600 /swap/swapfile
        mkswap /swap/swapfile
        
        # Add to fstab
        echo "/swap/swapfile none swap sw 0 0" >> /etc/fstab
        
        # Enable now
        swapon /swap/swapfile
        
        log_success "Swap file created and enabled"
    fi
else
    log_info "System has ${total_ram_gb}GB RAM - swap not needed"
fi

#==============================================================================
# REFRACTA SNAPSHOT DEFAULTS
#==============================================================================

log_info "Configuring Refracta Snapshot defaults..."
# Ensure Refracta doesn't exclude our custom /usr/local fonts or XDG configs
# We append to the excludes list only if we wanted to hide things, 
# but here we WANT everything.

# Optional: Set default snapshot filename to match the hostname
sed -i "s/^snapshot_basename=.*/snapshot_basename=\"${HOSTNAME}-snapshot\"/" /etc/refractasnapshot.conf || true

#==============================================================================
# QUINE TOOLS
#==============================================================================
# The "Quine" Engine (Self-Replication Tools)
apt install -y \
    refractasnapshot-gui \
    refractainstaller-gui \
    refractainstaller-base \
    refractasnapshot-base 
    

#==============================================================================
# CLEANUP
#==============================================================================

log_info "Cleaning package cache..."
apt clean
apt autoremove -y

#==============================================================================
# VERIFICATION
#==============================================================================

log_info "Running post-installation checks..."

# Critical files
for file in /boot/grub/grub.cfg /etc/fstab /etc/crypttab; do
    if [[ ! -f "$file" ]]; then
        log_error "CRITICAL: $file is missing!"
        exit 1
    fi
done

# Check if kernel exists
if ! ls /boot/vmlinuz-* &>/dev/null; then
    log_error "CRITICAL: No kernel found in /boot!"
    exit 1
fi

# Check if initramfs exists
if ! ls /boot/initrd.img-* &>/dev/null; then
    log_error "CRITICAL: No initramfs found in /boot!"
    exit 1
fi

# Check if cryptsetup is in initramfs
latest_initrd=$(ls -t /boot/initrd.img-* | head -n1)
if ! lsinitramfs "$latest_initrd" | grep -q cryptsetup; then
    log_warning "WARNING: cryptsetup may not be in initramfs!"
fi

# Check if USB modules are in initramfs
if ! lsinitramfs "$latest_initrd" | grep -q usb-storage; then
    log_warning "WARNING: usb-storage module may not be in initramfs!"
fi

# Check GRUB installation
if [[ ! -d /boot/efi/EFI/GNU ]]; then
    log_warning "WARNING: GRUB EFI directory not found at expected location"
fi

log_success "All critical checks passed"

#==============================================================================
# SUMMARY
#==============================================================================

echo ""
echo "=========================================="
log_success "Installation Complete!"
echo "=========================================="
echo ""
echo "System Summary:"
echo "  Hostname: $(cat /etc/hostname)"
echo "  Kernel:   $(ls /boot/vmlinuz-* | tail -n1 | sed 's|/boot/vmlinuz-||')"
echo "  Init:     SysVinit"
echo "  RAM:      ${total_ram_gb}GB"
[[ -f /swap/swapfile ]] && echo "  Swap:     Yes (${total_ram_gb}GB)" || echo "  Swap:     No"
[[ -n "$WHO_IS_THIS" ]] && echo "  User:     $WHO_IS_THIS"
echo ""
echo "Next Steps:"
echo ""
echo "1. Exit chroot:"
echo "   exit"
echo ""
echo "2. Unmount all filesystems:"
echo "   umount -R /mnt"
echo ""
echo "3. Close encrypted volumes:"
echo "   cryptsetup close crypthome"
echo "   cryptsetup close cryptroot"
echo ""
echo "4. Remove USB keyfile drive (keep it safe!)"
echo ""
echo "5. Reboot:"
echo "   reboot"
echo ""
echo "On First Boot:"
echo "  - Insert USB keyfile to unlock encrypted drives"
echo "  - System will boot to TTY login"
[[ -n "$WHO_IS_THIS" ]] && echo "  - Login as: $WHO_IS_THIS" || echo "  - Login as: root"
echo "  - Network: 'nmtui' to configure WiFi"
echo ""
echo "Post-Install TODO:"
echo "  - Deploy your zsh config"
echo "  - Install window manager / DE"
echo "  - Configure remaining dotfiles"
echo "  - Install additional tools"
echo ""

CHROOT_EOF
    
    chmod +x "$CHROOT_TARGET/root/finalize-install.sh"
    
    log_success "Chroot finalization script created at /root/finalize-install.sh"
}

#==============================================================================
# THE QUINE PROTOCOL (Self-Replication)
#==============================================================================
replicate_self() {
    log_info "Executing Quine Protocol: Cloning source to skeleton..."
    
    # Target the SKELETON so it is included in all future users
    local SKEL_SCRIPT_DIR="$CHROOT_TARGET/etc/skel/bin/scripts"
    mkdir -p "$SKEL_SCRIPT_DIR"
    
    # Copy the running script to the skeleton
    cat "$0" > "$SKEL_SCRIPT_DIR/phase1-automated-install-updated.sh"
    chmod +x "$SKEL_SCRIPT_DIR/phase1-automated-install-updated.sh"
    
    log_success "Source code cloned to skeleton: /etc/skel/bin/scripts"
}
#==============================================================================
# MAIN EXECUTION
#==============================================================================

main() {
    echo "=========================================="
    echo "  Devuan Bootstrap - Phase 1 Automation"
    echo "=========================================="
    echo ""
    
    # Safety checks
    require_root
    require_live_environment
    check_dependencies

    
    # Verify hardware
    log_info "Verifying hardware configuration..."
    verify_drive_exists "$NVME_DRIVE"
    verify_drive_exists "$SATA_DRIVE"
    verify_drive_exists "$USB_DRIVE"
    confirm_drives_unmounted
    
    # Final confirmation
    interactive_confirmation
    
    # Secure erase
    log_info "=== Phase 1.1: Secure Erase ==="
    secure_erase_nvme "$NVME_DRIVE"
    secure_erase_sata "$SATA_DRIVE"
    prepare_usb_keyfile "$USB_DRIVE"
    
    # Partitioning
    log_info "=== Phase 1.2: Partitioning ==="
    create_nvme_partitions "$NVME_DRIVE"
    create_sata_partitions "$SATA_DRIVE"
    
    # Wait for kernel to recognize new partitions
    sleep 2
    partprobe "$NVME_DRIVE" "$SATA_DRIVE"
    sleep 2
    
    # Filesystem creation
    log_info "=== Phase 1.3: Filesystems ==="
    format_boot_partitions
    setup_luks_encryption
    create_btrfs_filesystems
    create_btrfs_subvolumes
    
    # Mount
    log_info "=== Phase 1.4: Mounting ==="
    mount_for_bootstrap
    
    # Bootstrap
    log_info "=== Phase 1.5: Bootstrap ==="
    run_bootstrap
    
    # Configuration
    log_info "=== Phase 1.6: Configuration ==="
    configure_fstab
    configure_crypttab
    configure_apt_sources
    configure_policy_rcd
    configure_zshenv          
	configure_bash_xdg  
	configure_basic_system
    # Force XDG paths, Pre-seed Nvidia blacklist, Pre-set Dark Mode
    # This MUST run before generate_chroot_script so the files exist
    configure_target_system
    configure_grub
    generate_chroot_script
	
	# SELF REPLICATION
    replicate_self
    
    # Done
    echo "Next steps:"
    echo ""
    echo "1. Chroot into system:"
	echo "   arch-chroot $CHROOT_TARGET"
	echo "   (Or if you're a masochist)"
    echo "   mount --bind /dev $CHROOT_TARGET/dev"
    echo "   mount --bind /proc $CHROOT_TARGET/proc"
    echo "   mount --bind /sys $CHROOT_TARGET/sys"
    echo "   cp /etc/resolv.conf $CHROOT_TARGET/etc/resolv.conf"
    echo "   chroot $CHROOT_TARGET /bin/bash"
	echo ""
    echo "2. Run finalization script:"
    echo "   /root/finalize-install.sh"
    echo ""
    echo "3. Exit chroot and reboot"
    echo ""
}

# Run main function
main "$@"
