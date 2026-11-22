#!/bin/bash
set -euo pipefail

FILE="${1:-/etc/network/interfaces}"
START='# Meek-io IPTABLES --START--'
STOP='# Meek-io IPTABLES --STOP--'
PORTS=(10000 10001 10003 10004 10005)   # external port = i*100 + index

# Markers must each exist exactly once (trailing spaces tolerated)
start_re="^[[:space:]]*${START}[[:space:]]*$"
stop_re="^[[:space:]]*${STOP}[[:space:]]*$"
[[ $(grep -cE "$start_re" "$FILE") -eq 1 ]] || { echo "START marker not found exactly once"; exit 1; }
[[ $(grep -cE "$stop_re"  "$FILE") -eq 1 ]] || { echo "STOP marker not found exactly once";  exit 1; }

BLOCK=$(mktemp); NEW=$(mktemp)
trap 'rm -f "$BLOCK" "$NEW"' EXIT

# 1. Generate the rules
for i in {101..199}; do
  base=$((i * 100))
  ip="10.10.10.$i"
  for idx in "${!PORTS[@]}"; do
    ext=$((base + idx))
    dport=${PORTS[$idx]}
    cat >> "$BLOCK" <<EOF
        post-up iptables -t nat -A PREROUTING -i vmbr0 -p tcp --dport $ext -j DNAT --to-destination $ip:$dport
        post-down iptables -t nat -D PREROUTING -i vmbr0 -p tcp --dport $ext -j DNAT --to-destination $ip:$dport
        post-up iptables -A FORWARD -i vmbr0 -o vmbr1 -d $ip -p tcp --dport $dport -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        post-down iptables -D FORWARD -i vmbr0 -o vmbr1 -d $ip -p tcp --dport $dport -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        post-up iptables -A FORWARD -i vmbr1 -o vmbr0 -s $ip -p tcp --sport $dport -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
        post-down iptables -D FORWARD -i vmbr1 -o vmbr0 -s $ip -p tcp --sport $dport -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
EOF
  done
  echo "" >> "$BLOCK"
done

# 2. Replace everything between the markers (markers themselves are kept)
awk -v blockfile="$BLOCK" -v s="$START" -v e="$STOP" '
  { line=$0; sub(/^[ \t]+/,"",line); sub(/[ \t\r]+$/,"",line) }
  line==s { print; while ((getline l < blockfile) > 0) print l; skip=1; next }
  line==e { skip=0; print; next }
  !skip   { print }
' "$FILE" > "$NEW"

# 3. Backup, then overwrite in place (keeps owner/permissions)
cp -p "$FILE" "${FILE}.bak.$(date +%Y%m%d-%H%M%S)"
cat "$NEW" > "$FILE"

echo "Updated $FILE ($(grep -c 'post-up' "$BLOCK") post-up lines, backup saved)."
