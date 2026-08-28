#!/bin/sh
# Compact CPU / memory / swap for the tmux status bar. Output: "C112% M73% S1.0G"
# The memory figure turns yellow under memory pressure and red when critical.
# Supports macOS and Linux; any other kernel prints nothing.
#
# C is CPU DEMAND, not utilisation: load1 as a percentage of the core count, so
# it exceeds 100% when threads are queueing. True utilisation is deliberately
# not used — on macOS the only stock sources are `top -l 1` and `iostat -c 2`,
# measured at 830ms and 1.03s, which a 1s status-interval cannot absorb, and
# summing `ps -o time` deltas undercounts badly (measured 71% against top's
# 99%) because exited processes take their CPU time with them. Linux could
# afford real utilisation via /proc/stat, but showing a different metric per
# platform under the same letter would be worse than showing one honest one.
#
# Note the two loads are NOT the same measurement. Linux counts
# TASK_UNINTERRUPTIBLE — threads blocked on disk or NFS — so a pure I/O stall
# raises Linux load with idle CPUs. macOS/BSD counts only the run queue.
#
# M is memory used: on macOS, Activity Monitor's "Memory Used" (app + wired +
# compressed); on Linux, MemTotal - MemAvailable. Note btop reports
# active+wired on macOS (btop_collect.cpp:1226), omitting compressed and
# inactive-anonymous pages — ~12 GB adrift on a loaded machine. This agrees
# with Activity Monitor, not with btop.
#
# The colour is the kernel's own stall signal on each platform, never a
# percentage of RAM. Memory deliberately runs full — macOS compresses rather
# than leave RAM idle, Linux caches — so a healthy machine sits high. An
# earlier revision escalated at 80% used and was caught firing on a box
# Activity Monitor showed as green at 86%. Don't reintroduce a percentage.

COLOUR_NORMAL="${COLOUR_NORMAL:-#[fg=#6c7086]}"      # catppuccin overlay0
COLOUR_WARN="${COLOUR_WARN:-#[fg=#f9e2af]}"          # catppuccin yellow
COLOUR_CRITICAL="${COLOUR_CRITICAL:-#[fg=#f38ba8]}"  # catppuccin red

export COLOUR_NORMAL COLOUR_WARN COLOUR_CRITICAL

# Each collector prints one line: "<cpu%> <mem%> <swap-bytes> <normal|warn|critical>"

collect_darwin() {
  # kern.memorystatus_vm_pressure_level is the signal behind Activity Monitor's
  # pressure graph: 1 normal, 2 warn, 4 critical (dispatch_source_memorypressure).
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
    /^[A-Z].*: *[0-9]/ { key = $0; sub(/:.*/, "", key)
                         value = $NF; sub(/\.$/, "", value)
                         pages[key] = value }
    END {
      wired      = pages["Pages wired down"]             * page_size
      anonymous  = pages["Anonymous pages"]              * page_size
      purgeable  = pages["Pages purgeable"]              * page_size
      compressed = pages["Pages occupied by compressor"] * page_size

      swap_bytes = swap_used_text + 0
      swap_bytes *= (swap_used_text ~ /G$/) ? 1073741824 : 1048576

      state = pressure_level >= 4 ? "critical" \
            : pressure_level >= 2 ? "warn" : "normal"

      printf "%.2f %.2f %.0f %s\n",
             load_1min * 100 / core_count,
             (anonymous - purgeable + wired + compressed) * 100 / memory_total,
             swap_bytes, state
    }'
}

collect_linux() {
  # PSI is the closest analogue to macOS pressure levels: "some avg10" is the
  # share of the last 10s in which at least one task stalled on memory, "full"
  # the share in which every task did. Anchored to systemd-oomd's own defaults,
  # which start KILLING processes at 60% sustained — so warn far below that.
  # PSI needs Linux 4.20+ with CONFIG_PSI; without it the figure stays grey
  # rather than falling back to an invented percentage.
  { nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo
    cat /proc/loadavg /proc/meminfo /proc/pressure/memory 2>/dev/null
  } | awk '
    NR == 1 { core_count = $1; next }
    NR == 2 { load_1min  = $1; next }

    /^MemTotal:/     { memory_total_kb     = $2 }
    /^MemAvailable:/ { memory_available_kb = $2 }
    /^SwapTotal:/    { swap_total_kb       = $2 }
    /^SwapFree:/     { swap_free_kb        = $2 }

    # + 0 is load-bearing: sub() marks the field as a string, and a string
    # comparison makes every value under 10 beginning with 9 sort above "10".
    /^some / { sub(/avg10=/, "", $2); pressure_some = $2 + 0 }
    /^full / { sub(/avg10=/, "", $2); pressure_full = $2 + 0 }
    END {
      PRESSURE_WARN = 10; OOMD_KILL_LIMIT = 60
      state = (pressure_full >= PRESSURE_WARN || pressure_some >= OOMD_KILL_LIMIT) ? "critical" \
            : (pressure_some >= PRESSURE_WARN) ? "warn" : "normal"

      printf "%.2f %.2f %.0f %s\n",
             load_1min * 100 / core_count,
             (memory_total_kb - memory_available_kb) * 100 / memory_total_kb,
             (swap_total_kb - swap_free_kb) * 1024, state
    }'
}

case "$(uname -s)" in
  Darwin) stats=$(collect_darwin) ;;
  Linux)  stats=$(collect_linux)  ;;
  *)      exit 0 ;;
esac

[ -n "$stats" ] || exit 0

printf '%s' "$stats" | awk '{
  colour = $4 == "critical" ? ENVIRON["COLOUR_CRITICAL"] \
         : $4 == "warn"     ? ENVIRON["COLOUR_WARN"] : ENVIRON["COLOUR_NORMAL"]

  # Always gigabytes: a fixed-width field keeps the segment from jittering as
  # swap crosses 1 GB, and it is one column narrower than the megabyte form.
  printf "C%.0f%% %sM%.0f%%%s S%.1fG",
         $1, colour, $2, ENVIRON["COLOUR_NORMAL"], $3 / 1073741824
}'
