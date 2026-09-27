#!/usr/bin/env bash
# Read-only health check for the touch setup. Needs no root.

ok()   { printf '  \e[32mok\e[0m    %s\n' "$1"; }
bad()  { printf '  \e[31mFAIL\e[0m  %s\n' "$1"; }
info() { printf '  \e[33m--\e[0m    %s\n' "$1"; }

echo "Packages"
for p in ithc-dkms iptsd wvkbd-deskintl; do
  if v=$(pacman -Q "$p" 2>/dev/null); then ok "$v"; else bad "$p not installed"; fi
done

echo "Kernel $(uname -r)"
if [[ -d "/usr/lib/modules/$(uname -r)/build" ]]; then
  ok "headers present"
else
  bad "no headers for this kernel (DKMS can't build ithc)"
fi

status=$(dkms status ithc 2>/dev/null | grep "$(uname -r)" || true)
if [[ "$status" == *installed* ]]; then ok "dkms: $status"; else bad "dkms: ithc not built for this kernel (${status:-no entry})"; fi

if lsmod | grep -q '^ithc '; then ok "ithc module loaded"; else bad "ithc module not loaded"; fi
# The poll parameter isn't exposed in sysfs; the driver logs it on every (re)probe.
if ! lsmod | grep -q '^ithc '; then
  info "poll mode unknown (ithc not loaded)"
elif journalctl -k -b --no-pager 2>/dev/null | grep -q "ithc.*using polling instead of irq"; then
  ok "poll mode active"
else
  info "no 'using polling' message this boot (is /usr/lib/modprobe.d/ithc.conf installed?)"
fi

hidraw=$(grep -l "Intel Touch Host Controller" /sys/class/hidraw/hidraw*/device/uevent 2>/dev/null | head -1 | cut -d/ -f5)
if [[ -n "$hidraw" ]]; then ok "touch device: /dev/$hidraw"; else bad "no Intel Touch Host Controller hidraw device"; fi

if [[ -n "$hidraw" ]] && systemctl is-active --quiet "iptsd@dev-$hidraw.service"; then
  ok "iptsd@dev-$hidraw.service running"
else
  bad "iptsd service not running for ${hidraw:-the touch device}"
fi

if grep -q "IPTSD Virtual Touchscreen" /proc/bus/input/devices; then ok "virtual touchscreen present"; else bad "no IPTSD virtual touchscreen"; fi
