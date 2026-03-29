#!/usr/bin/env bash

set -euo pipefail

if (( BASH_VERSINFO[0] < 4 || (BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 3) )); then
  printf 'Error: Bash 4.3+ is required (current: %s)\n' "${BASH_VERSION}" >&2
  exit 1
fi

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "${SCRIPT_DIR}/.." && pwd)

cd "${REPO_ROOT}"

COMMAND="${1:-summary}"
TOP_N="${2:-10}"
REDIS_CONTAINER_NAME="${REDIS_CONTAINER_NAME:-dnslow.me-redis}"
SCAN_COUNT=2000

usage() {
  cat <<'USAGE'
Usage:
  scripts/redis-cache-report.sh [summary|memory|expire|full] [TOP_N]

Examples:
  scripts/redis-cache-report.sh
  scripts/redis-cache-report.sh summary
  scripts/redis-cache-report.sh memory
  scripts/redis-cache-report.sh expire 20
  scripts/redis-cache-report.sh full 20

Notes:
  summary  Cheap report. Uses Redis INFO only.
  memory   Cheap report. Shows Redis memory usage and eviction policy.
  expire   Maintenance-only fast path. One O(N) incremental scan for expiring Blocky cache entries with approximate counts.
  full     Maintenance-only full report. One O(N) incremental scan for approximate TTL buckets across Redis keys with TTL plus expiring Blocky cache entries that preserve DNS type.
  scope    Supports the current Blocky Redis cache key layout in this repo, not arbitrary Redis keys.
  env      Set REDIS_CONTAINER_NAME if the Redis container name differs.
USAGE
}

die() {
  printf 'Error: %s\n' "$1" >&2
  exit 1
}

require_docker() {
  command -v docker >/dev/null 2>&1 || die "docker is required; docker compose is not used by this helper"
}

is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

reset_batch_lines() {
  # Bash 4.3 + nounset treats empty array expansion as unset. Keep a single
  # empty sentinel line so later "${BATCH_LINES[@]}" expansion stays safe.
  BATCH_LINES=("")
}

redis_capture() {
  local output stderr_file stderr_output
  stderr_file=$(mktemp "${TMPDIR:-/tmp}/redis-cache-report.stderr.XXXXXX")

  if ! output=$(docker exec -i "${REDIS_CONTAINER_NAME}" redis-cli "$@" 2>"${stderr_file}"); then
    stderr_output=$(<"${stderr_file}")
    rm -f -- "${stderr_file}"
    die "unable to run redis-cli in container ${REDIS_CONTAINER_NAME}: ${stderr_output:-command failed}"
  fi

  rm -f -- "${stderr_file}"
  printf '%s' "${output}"
}

validate_batch_output() {
  local mode="$1"
  local output="$2"
  local line

  [[ -n "${output}" ]] || return 0

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue

    case "${line}" in
      "(error)"*|"ERR "*)
        die "Redis batch ${mode} failed: ${line}"
        ;;
    esac

    case "${mode}:${line}" in
      expire:$'CURSOR\t'*|expire:$'ENTRY\t'*)
        ;;
      full:$'CURSOR\t'*|full:$'COUNTS\t'*|full:$'ENTRY\t'*)
        ;;
      *)
        die "unexpected Redis batch ${mode} output: ${line}"
        ;;
    esac
  done <<<"${output}"
}

redis_info() {
  redis_capture INFO "$1"
}

validate_top_n() {
  [[ "${TOP_N}" =~ ^[1-9][0-9]*$ ]] || die "TOP_N must be a positive integer"
}

print_scan_warning() {
  printf 'Caution\n'
  printf '  maintenance-only diagnostic; uses one incremental SCAN pass and per-batch Redis-side aggregation\n'
  printf '  lower blocking risk than a single full-keyspace Lua scan, but still adds O(N) Redis load\n'
  printf '  TTL bucket totals and expiring entry counts are approximate because SCAN may return duplicate keys\n'
  printf '  full mode TTL buckets cover Redis keys with TTL; expiring-entry ranking preserves DNS type and domain for the current Blocky cache key layout\n'
  printf '  supports the current Blocky Redis cache key layout in this repo, not arbitrary Redis keys\n'
  printf '  best run off-peak on production systems\n'
}

eval_batch_expire() {
  local cursor="$1"
  local lua_script output

  reset_batch_lines

  # This helper intentionally follows the current Blocky Redis key layout used
  # in this repo: `blocky:cache:` + two qtype bytes + the DNS name.
  lua_script="local prefix='blocky:cache:'; local mins={}; local counts={}; local r=redis.call('SCAN',ARGV[1],'COUNT',ARGV[2]); local next_cursor=r[1]; for _,k in ipairs(r[2]) do if string.find(k,prefix,1,true)==1 and #k>#prefix+2 then local pttl=redis.call('PTTL',k); if pttl>0 then local hi=string.byte(k,#prefix+1); local lo=string.byte(k,#prefix+2); local qtype=(hi*256)+lo; local domain=string.sub(k,#prefix+3); local entry=qtype..'\t'..domain; if mins[entry]==nil or pttl<mins[entry] then mins[entry]=pttl end; counts[entry]=(counts[entry] or 0)+1 end end end; local out={'CURSOR\t'..next_cursor}; for entry,pttl in pairs(mins) do local tab=string.find(entry,'\t',1,true); local qtype=string.sub(entry,1,tab-1); local domain=string.sub(entry,tab+1); table.insert(out,'ENTRY\t'..pttl..'\t'..counts[entry]..'\t'..qtype..'\t'..domain) end; return out"
  output=$(redis_capture EVAL "${lua_script}" 0 "${cursor}" "${SCAN_COUNT}" | tr -d '\r')
  validate_batch_output expire "${output}"
  if [[ -n "${output}" ]]; then
    mapfile -t BATCH_LINES <<<"${output}"
  fi
}

eval_batch_full() {
  local cursor="$1"
  local lua_script output

  reset_batch_lines

  # This helper intentionally follows the current Blocky Redis key layout used
  # in this repo: `blocky:cache:` + two qtype bytes + the DNS name.
  lua_script="local prefix='blocky:cache:'; local c,b1,b2,b3,b4=0,0,0,0,0; local mins={}; local counts={}; local r=redis.call('SCAN',ARGV[1],'COUNT',ARGV[2]); local next_cursor=r[1]; for _,k in ipairs(r[2]) do local pttl=redis.call('PTTL',k); if pttl>0 then c=c+1; if pttl<60000 then b1=b1+1; elseif pttl<300000 then b2=b2+1; elseif pttl<3600000 then b3=b3+1; else b4=b4+1; end; if string.find(k,prefix,1,true)==1 and #k>#prefix+2 then local hi=string.byte(k,#prefix+1); local lo=string.byte(k,#prefix+2); local qtype=(hi*256)+lo; local domain=string.sub(k,#prefix+3); local entry=qtype..'\t'..domain; if mins[entry]==nil or pttl<mins[entry] then mins[entry]=pttl end; counts[entry]=(counts[entry] or 0)+1 end end end; local out={'CURSOR\t'..next_cursor,'COUNTS\t'..c..'\t'..b1..'\t'..b2..'\t'..b3..'\t'..b4}; for entry,pttl in pairs(mins) do local tab=string.find(entry,'\t',1,true); local qtype=string.sub(entry,1,tab-1); local domain=string.sub(entry,tab+1); table.insert(out,'ENTRY\t'..pttl..'\t'..counts[entry]..'\t'..qtype..'\t'..domain) end; return out"
  output=$(redis_capture EVAL "${lua_script}" 0 "${cursor}" "${SCAN_COUNT}" | tr -d '\r')
  validate_batch_output full "${output}"
  if [[ -n "${output}" ]]; then
    mapfile -t BATCH_LINES <<<"${output}"
  fi
}

print_memory() {
  local info used peak max policy
  info=$(redis_info memory)
  used=$(awk -F: '/^used_memory_human:/ {print $2}' <<<"${info}" | tr -d '\r')
  peak=$(awk -F: '/^used_memory_peak_human:/ {print $2}' <<<"${info}" | tr -d '\r')
  max=$(awk -F: '/^maxmemory_human:/ {print $2}' <<<"${info}" | tr -d '\r')
  policy=$(awk -F: '/^maxmemory_policy:/ {print $2}' <<<"${info}" | tr -d '\r')

  printf 'Memory\n'
  printf '  used: %s\n' "${used}"
  printf '  peak: %s\n' "${peak}"
  printf '  max: %s\n' "${max}"
  printf '  policy: %s\n' "${policy}"
}

print_stats() {
  local stats="$1" keyspace="$2" evicted keyspace_line keys expires
  evicted=$(awk -F: '/^evicted_keys:/ {print $2}' <<<"${stats}" | tr -d '\r')
  keyspace_line=$(awk -F'[=,:]' '/^db0:/ {print $3, $5}' <<<"${keyspace}" | tr -d '\r')
  keys=0
  expires=0
  if [[ -n "${keyspace_line}" ]]; then
    read -r keys expires <<<"${keyspace_line}"
  fi

  printf 'Cache\n'
  printf '  keys: %s\n' "${keys}"
  printf '  expires: %s\n' "${expires}"
  printf '  evicted_keys: %s\n' "${evicted:-0}"
}

print_expiration_counters() {
  local stats="$1" expired_keys expired_keys_active expired_stale_perc expire_cpu_ms
  expired_keys=$(awk -F: '/^expired_keys:/ {print $2}' <<<"${stats}" | tr -d '\r')
  expired_keys_active=$(awk -F: '/^expired_keys_active:/ {print $2}' <<<"${stats}" | tr -d '\r')
  expired_stale_perc=$(awk -F: '/^expired_stale_perc:/ {print $2}' <<<"${stats}" | tr -d '\r')
  expire_cpu_ms=$(awk -F: '/^expire_cycle_cpu_milliseconds:/ {print $2}' <<<"${stats}" | tr -d '\r')

  printf 'Expiration\n'
  printf '  expired_keys: %s\n' "${expired_keys:-0}"
  printf '  expired_keys_active: %s\n' "${expired_keys_active:-0}"
  printf '  expired_stale_perc: %s\n' "${expired_stale_perc:-0}"
  printf '  expire_cycle_cpu_ms: %s\n' "${expire_cpu_ms:-0}"
}

qtype_name() {
  case "$1" in
    1) printf 'A' ;;
    2) printf 'NS' ;;
    5) printf 'CNAME' ;;
    6) printf 'SOA' ;;
    12) printf 'PTR' ;;
    15) printf 'MX' ;;
    16) printf 'TXT' ;;
    28) printf 'AAAA' ;;
    33) printf 'SRV' ;;
    64) printf 'SVCB' ;;
    65) printf 'HTTPS' ;;
    *) printf 'TYPE%s' "$1" ;;
  esac
}

print_expiring_entries_from_maps() {
  local limit="$1" entry pttl qtype domain qtype_display
  local -n min_ref=$2
  local -n count_ref=$3

  printf 'Redis Cache Entries Expiring Soon (min TTL seconds, rounded up from PTTL, maintenance-only O(N) incremental scan)\n'
  printf '  note: Redis entry TTL only; does not reflect Blocky in-memory cache freshness\n'
  printf '  note: approximate entry counts; SCAN may return duplicate keys\n'
  printf '  note: per-entry ranking preserves DNS type and domain for the current Blocky cache key layout\n'

  if (( ${#min_ref[@]} == 0 )); then
    printf '  no matching Blocky cache keys\n'
    return 0
  fi

  for entry in "${!min_ref[@]}"; do
    pttl=${min_ref["${entry}"]}
    IFS=$'\t' read -r qtype domain <<<"${entry}"
    qtype_display=$(qtype_name "${qtype}")
    printf '%s\t%s\t%s\t%s\t%s\n' \
      "${pttl}" \
      "$(( (pttl + 999) / 1000 ))" \
      "${count_ref["${entry}"]}" \
      "${qtype_display}" \
      "${domain}"
  done |
    sort -t $'\t' -k1,1n -k5,5 -k4,4 |
    awk -F'\t' -v limit="${limit}" 'NR <= limit {print $2 "\t" $3 "\t" $4 "\t" $5}'
}

print_ttl_buckets() {
  local ttl_total="$1" lt_1m="$2" lt_5m="$3" lt_1h="$4" ge_1h="$5"

  printf 'Redis Cache TTL Buckets (maintenance-only O(N) incremental scan)\n'
  printf '  note: Redis entry TTL only; does not reflect Blocky in-memory cache freshness\n'
  printf '  note: approximate totals across Redis keys with TTL; SCAN may return duplicate keys\n'
  printf '  note: not limited to Blocky cache domains\n'
  printf '  ttl_lt_1m: %s\n' "${lt_1m}"
  printf '  ttl_1m_to_5m: %s\n' "${lt_5m}"
  printf '  ttl_5m_to_1h: %s\n' "${lt_1h}"
  printf '  ttl_ge_1h: %s\n' "${ge_1h}"
  printf '  ttl_total: %s\n' "${ttl_total}"
}

collect_expire_report() {
  local limit="$1" cursor=0 next_cursor=0 line _tag pttl count qtype domain
  local entry_key
  local -A min_pttl_by_entry=()
  local -A count_by_entry=()

  while :; do
    eval_batch_expire "${cursor}"
    next_cursor=

    for line in "${BATCH_LINES[@]}"; do
      [[ -n "${line}" ]] || continue
      IFS=$'\t' read -r _tag pttl count qtype domain <<<"${line}"
      case "${_tag}" in
        CURSOR)
          is_uint "${pttl}" || die 'unable to parse expire batch cursor'
          next_cursor="${pttl}"
          ;;
        ENTRY)
          is_uint "${pttl}" || continue
          is_uint "${count}" || continue
          is_uint "${qtype}" || continue
          [[ -n "${domain}" ]] || continue

          entry_key="${qtype}"$'\t'"${domain}"
          if [[ -z "${min_pttl_by_entry[${entry_key}]:-}" ]] || (( pttl < min_pttl_by_entry[${entry_key}] )); then
            min_pttl_by_entry["${entry_key}"]=${pttl}
          fi
          count_by_entry["${entry_key}"]=$(( ${count_by_entry["${entry_key}"]:-0} + count ))
          ;;
      esac
    done

    [[ -n "${next_cursor}" ]] || die 'expire batch missing cursor'
    cursor="${next_cursor}"
    [[ "${cursor}" == '0' ]] && break
  done

  print_expiring_entries_from_maps "${limit}" min_pttl_by_entry count_by_entry
}

collect_full_report() {
  local limit="$1" cursor=0 next_cursor=0 line _tag a b c d e pttl count
  local qtype domain entry_key
  local ttl_total=0 lt_1m=0 lt_5m=0 lt_1h=0 ge_1h=0
  local batch_total=0 batch_lt_1m=0 batch_lt_5m=0 batch_lt_1h=0 batch_ge_1h=0
  local -A min_pttl_by_entry=()
  local -A count_by_entry=()

  while :; do
    eval_batch_full "${cursor}"
    next_cursor=

    for line in "${BATCH_LINES[@]}"; do
      [[ -n "${line}" ]] || continue
      IFS=$'\t' read -r _tag a b c d e <<<"${line}"
      case "${_tag}" in
        CURSOR)
          is_uint "${a}" || die 'unable to parse full batch cursor'
          next_cursor="${a}"
          ;;
        COUNTS)
          is_uint "${a}" || die 'unable to parse full batch total'
          is_uint "${b}" || die 'unable to parse full batch lt_1m'
          is_uint "${c}" || die 'unable to parse full batch lt_5m'
          is_uint "${d}" || die 'unable to parse full batch lt_1h'
          is_uint "${e}" || die 'unable to parse full batch ge_1h'
          batch_total="${a}"
          batch_lt_1m="${b}"
          batch_lt_5m="${c}"
          batch_lt_1h="${d}"
          batch_ge_1h="${e}"
          ttl_total=$(( ttl_total + batch_total ))
          lt_1m=$(( lt_1m + batch_lt_1m ))
          lt_5m=$(( lt_5m + batch_lt_5m ))
          lt_1h=$(( lt_1h + batch_lt_1h ))
          ge_1h=$(( ge_1h + batch_ge_1h ))
          ;;
        ENTRY)
          pttl="${a}"
          count="${b}"
          qtype="${c}"
          domain="${d}"
          is_uint "${pttl}" || continue
          is_uint "${count}" || continue
          is_uint "${qtype}" || continue
          [[ -n "${domain}" ]] || continue
          entry_key="${qtype}"$'\t'"${domain}"
          if [[ -z "${min_pttl_by_entry[${entry_key}]:-}" ]] || (( pttl < min_pttl_by_entry[${entry_key}] )); then
            min_pttl_by_entry["${entry_key}"]=${pttl}
          fi
          count_by_entry["${entry_key}"]=$(( ${count_by_entry["${entry_key}"]:-0} + count ))
          ;;
      esac
    done

    [[ -n "${next_cursor}" ]] || die 'full batch missing cursor'
    cursor="${next_cursor}"
    [[ "${cursor}" == '0' ]] && break
  done

  print_ttl_buckets "${ttl_total}" "${lt_1m}" "${lt_5m}" "${lt_1h}" "${ge_1h}"
  printf '\n'
  print_expiring_entries_from_maps "${limit}" min_pttl_by_entry count_by_entry
}

case "${COMMAND}" in
  summary)
    require_docker
    stats_info=$(redis_info stats)
    keyspace_info=$(redis_info keyspace)
    print_memory
    printf '\n'
    print_stats "${stats_info}" "${keyspace_info}"
    printf '\n'
    print_expiration_counters "${stats_info}"
    ;;
  memory)
    require_docker
    print_memory
    ;;
  expire)
    validate_top_n
    require_docker
    stats_info=$(redis_info stats)
    print_expiration_counters "${stats_info}"
    printf '\n'
    print_scan_warning
    printf '\n'
    collect_expire_report "${TOP_N}"
    ;;
  full)
    validate_top_n
    require_docker
    stats_info=$(redis_info stats)
    keyspace_info=$(redis_info keyspace)
    print_memory
    printf '\n'
    print_stats "${stats_info}" "${keyspace_info}"
    printf '\n'
    print_expiration_counters "${stats_info}"
    printf '\n'
    print_scan_warning
    printf '\n'
    collect_full_report "${TOP_N}"
    ;;
  -h|--help|help)
    usage
    ;;
  *)
    usage
    exit 1
    ;;
esac
