#!/system/bin/sh

## Variables
MOD_DIR="${0%/*}"
TEMP_PATH=/data/local/tmp
MMC_CRC_PATH="/sys/module/mmc_core/parameters"
SYS_KERNEL="/sys/kernel"
PROC_KERNEL="/proc/sys/kernel"
MOD_SYS="/sys/module"
PROC_SYS="/proc/sys"
SUBSYS_RST="/sys/module/subsystem_restart/parameters"
VM_SYS="/proc/sys/vm"
BLK_QUEUE="/sys/block/*/queue"
U32_MAX="4294967295"
SCHED_NS="$((5 * 1000 * 1000))"
TASK_SPLIT="5"
sync

## Functions
write_val() {
  if [[ ! -f "$1" ]]; then
    return 1
  fi
  local current_val
  current_val=$(cat "$1" 2> /dev/null)
  if [[ "$current_val" == "$2" ]]; then
    return 1
  fi
  chmod +w "$1" 2> /dev/null
  if ! echo "$2" > "$1" 2> /dev/null; then
    return 0
  fi
}
sleep 30
write_val /proc/sys/kernel/perf_cpu_time_max_percent 2
write_val /proc/sys/kernel/sched_autogroup_enabled 1
write_val /proc/sys/kernel/sched_child_runs_first 0
write_val /proc/sys/kernel/sched_tunable_scaling 0
write_val /proc/sys/kernel/sched_latency_ns "$SCHED_NS"
write_val /proc/sys/kernel/sched_min_granularity_ns "$((SCHED_NS / TASK_SPLIT))"
write_val /proc/sys/kernel/sched_wakeup_granularity_ns "$((SCHED_NS / 2))"
write_val /proc/sys/kernel/sched_migration_cost_ns 5000000
write_val /proc/sys/kernel/sched_min_task_util_for_colocation 0
write_val /proc/sys/kernel/sched_nr_migrate 256
write_val /proc/sys/kernel/sched_schedstats 0
write_val /proc/sys/kernel/printk_devkmsg off
write_val /proc/sys/vm/dirty_background_ratio 2
write_val /proc/sys/vm/dirty_ratio 5
write_val /proc/sys/vm/dirty_expire_centisecs 500
write_val /proc/sys/vm/dirty_writexback_centisecs 500
write_val /proc/sys/vm/page-cluster 0
write_val /proc/sys/vm/stat_interval 10
write_val /proc/sys/vm/swappiness 20
write_val /proc/sys/vm/vfs_cache_pressure 100
write_val /proc/sys/net/ipv4/tcp_ecn 1
write_val /proc/sys/net/ipv4/tcp_fastopen 3
write_val /proc/sys/net/ipv4/tcp_syncookies 0

if [[ -f "/sys/kernel/debug/sched_features" ]]; then
  write_val /sys/kernel/debug/sched_features NEXT_BUDDY
  write_val /sys/kernel/debug/sched_features NO_TTWU_QUEUE
fi

[[ "$ANDROID" == true ]] && if [[ -d "/dev/stune/" ]]; then
  write_val /dev/stune/top-app/schedtune.prefer_idle 0
  write_val /dev/stune/top-app/schedtune.boost 0
fi

for cpu in /sys/devices/system/cpu/cpu*/cpufreq; do
  available_govs="$(cat "$cpu/scaling_available_governors")"
  for gov in schedutil interactive; do
    if [[ "$available_govs" == *"$gov"* ]]; then
      write_val "$cpu/scaling_governor" "$gov"
      break
    fi
  done
done

find /sys/devices/system/cpu/ -name schedutil -type d | while IFS= read -r gov_path; do
  write_val "$gov_path/up_rate_limit_us" "$((SCHED_NS / 1000))"
  write_val "$gov_path/down_rate_limit_us" "$((SCHED_NS / 1000))"
  write_val "$gov_path/rate_limit_us" "$((SCHED_NS / 1000))"
  write_val "$gov_path/hispeed_load" 99
  write_val "$gov_path/hispeed_freq" "$U32_MAX"
done

find /sys/devices/system/cpu/ -name interactive -type d | while IFS= read -r gov_path; do
  write_val "$gov_path/timer_rate" "$((SCHED_NS / 1000))"
  write_val "$gov_path/min_sample_time" "$((SCHED_NS / 1000))"
  write_val "$gov_path/go_hispeed_load" 99
  write_val "$gov_path/hispeed_freq" "$U32_MAX"
done

for q_path in /sys/block/*/queue; do
  available_schedulers="$(cat "$q_path/scheduler")"
  for sched in cfq noop kyber bfq mq-deadline none; do
    if [[ "$available_schedulers" == *"$sched"* ]]; then
      write_val "$q_path/scheduler" "$sched"
      break
    fi
  done
  write_val "$q_path/add_random" 0
  write_val "$q_path/iostats" 0
  write_val "$q_path/read_ahead_kb" 64
  write_val "$q_path/nr_requests" 512
done

{
  until [[ -e "/sdcard/" ]]; do
    sleep 1
  done

  for svc in logcat logcatd logd logd.rc tcpdump cnss_diag statsd traced idd-logreader idd-logreadermain stats dumpstate aplogd vendor.tcpdump vendor_tcpdump vendor.cnss_diag; do
    pid=$(pidof "$svc")
    if [ -n "$pid" ]; then
      kill -15 "$pid"
      sleep 2
      if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid"
      fi
    fi
  done

  for pattern in debug_mask log_level* debug_level* *debug_mode edac_mc_log* enable_event_log *log_level* *log_ue* *log_ce* log_ecn_error snapshot_crashdumper seclog* compat-log *log_enabled tracing_on mballoc_debug; do
    for match in $(find /sys/ -type f -name "$pattern"); do
      write_val "$match" 0
    done
  done

  if [ -f "$MOD_SYS/spurious/parameters/noirqdebug" ]; then
    write_val "$MOD_SYS/spurious/parameters/noirqdebug" 1
  fi
  if [ -f "$SYS_KERNEL/debug/sde_rotator0/evtlog/enable" ]; then
    write_val "$SYS_KERNEL/debug/sde_rotator0/evtlog/enable" 0
  fi
  if [ -f "$SYS_KERNEL/debug/dri/0/debug/enable" ]; then
    write_val "$SYS_KERNEL/debug/dri/0/debug/enable" 0
  fi
  if [ -f "$PROC_KERNEL/sched_schedstats" ]; then
    write_val "$PROC_KERNEL/sched_schedstats" 0
  fi
  if [ -f "$PROC_SYS/debug/exception-trace" ]; then
    write_val "$PROC_SYS/debug/exception-trace" 0
  fi
  if [ -f "$PROC_SYS/net/ipv4/tcp_no_metrics_save" ]; then
    write_val "$PROC_SYS/net/ipv4/tcp_no_metrics_save" 1
  fi

  if [ -d "$MMC_CRC_PATH" ]; then
    write_val "$MMC_CRC_PATH/crc" 0
    write_val "$MMC_CRC_PATH/use_spi_crc" 0
  fi

  if [ -d "$PROC_KERNEL" ]; then
    write_val "$PROC_KERNEL/printk" 0 0 0 0
    write_val "$PROC_KERNEL/printk_devkmsg" off
  fi

  if [ -d "$SUBSYS_RST" ]; then
    write_val "$SUBSYS_RST/enable_mini_RDUMPS" 0
    write_val "$SUBSYS_RST/enable_RDUMPS" 0
  fi

  for blk_q in $BLK_QUEUE; do
    write_val "$blk_q/iostats" 0
  done

  if [ -d "$VM_SYS" ]; then
    write_val "$VM_SYS/oom_dump_tasks" 0
    write_val "$VM_SYS/block_dump" 0
  fi
}