#!/bin/sh
# Compact CPU / memory / swap for the tmux status bar. Output: "C112% M73% S1.0G"
# The memory figure turns yellow under pressure and red when critical.
#
# CPU is load1 normalised by core count, not a true utilisation percentage:
# `top -l 2` and `iostat -c 2` are the only accurate macOS sources and both
# block ~1s, which is fatal at a 1s status-interval. Summing `ps -o time`
# deltas undercounts badly (measured 71% against top's 99%) because exited
# processes take their CPU time with them.
#
# Memory matches Activity Monitor's "Memory Used" = app + wired + compressed.
# btop reports active+wired instead (btop_collect.cpp:1226), which omits
# compressed and inactive-anonymous pages — ~12 GB apart on a loaded machine.
#
# The colour is kern.memorystatus_vm_pressure_level and nothing else
# (1=normal 2=warn 4=critical, the dispatch_source_memorypressure_flags_t
# values), so it agrees with Activity Monitor's pressure graph by construction.
#
# Deliberately NOT a percentage of RAM. macOS memory pressure is a composite of
# free RAM, compression ratio, swap usage and allocation-demand rate; the
# compressor keeps memory full on purpose, so a healthy machine sits high. An
# earlier revision escalated to yellow at 80% used and was measured firing on a
# box Activity Monitor showed as green at 86% (28.05/32 GB, swap 3.15 GB). No
# percentage reproduces the kernel's verdict, so don't reintroduce one.

# Darwin-only: vm_stat, kern.memorystatus_vm_pressure_level and vm.swapusage
# have no GNU equivalents. Exit silently rather than emit a broken segment —
# the shared tmux.conf is cross-platform (see the Linux overlay).
[ "$(uname -s)" = "Darwin" ] || exit 0

COLOUR_NORMAL="${COLOUR_NORMAL:-#[fg=#6c7086]}"    # catppuccin overlay0
COLOUR_WARN="${COLOUR_WARN:-#[fg=#f9e2af]}"      # catppuccin yellow
COLOUR_CRITICAL="${COLOUR_CRITICAL:-#[fg=#f38ba8]}"  # catppuccin red

export COLOUR_NORMAL COLOUR_WARN COLOUR_CRITICAL

{ sysctl -n hw.ncpu vm.loadavg hw.memsize vm.swapusage \
         kern.memorystatus_vm_pressure_level
  vm_stat
} | awk '
NR == 1 { core_count     = $1; next }
NR == 2 { load_1min      = $2; next }
NR == 3 { memory_total   = $1; next }
NR == 4 { swap_used_text = $6; next }
NR == 5 { pressure_level = $1; next }

/page size of/     { page_size = $8 }
/^[A-Z].*: *[0-9]/ { key = $0
                     sub(/:.*/, "", key)
                     value = $NF
                     sub(/\.$/, "", value)
                     pages[key] = value }
END {
  wired      = pages["Pages wired down"]              * page_size
  anonymous  = pages["Anonymous pages"]               * page_size
  purgeable  = pages["Pages purgeable"]               * page_size
  compressed = pages["Pages occupied by compressor"]  * page_size

  cpu_percent    = load_1min * 100 / core_count
  memory_percent = (anonymous - purgeable + wired + compressed) * 100 / memory_total

  PRESSURE_WARN = 2; PRESSURE_CRITICAL = 4
  if (pressure_level >= PRESSURE_CRITICAL)
    memory_colour = ENVIRON["COLOUR_CRITICAL"]
  else if (pressure_level >= PRESSURE_WARN)
    memory_colour = ENVIRON["COLOUR_WARN"]
  else
    memory_colour = ENVIRON["COLOUR_NORMAL"]

  # Always gigabytes: a fixed-width field keeps the segment from jittering as
  # swap crosses 1 GB, and one character narrower than the megabyte form.
  swap_megabytes = swap_used_text + 0
  if (swap_used_text ~ /G$/) swap_megabytes *= 1024
  swap = sprintf("%.1fG", swap_megabytes / 1024)

  printf "C%.0f%% %sM%.0f%%%s S%s", \
         cpu_percent, memory_colour, memory_percent, ENVIRON["COLOUR_NORMAL"], swap
}'
