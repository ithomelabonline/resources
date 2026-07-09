#!/usr/bin/env bash
#
# setup_usb_ethernet_gadget.sh
#
# Turns a Raspberry Pi (Zero W / Zero 2 W / any dwc2-capable model) into a USB
# Ethernet gadget using CDC-NCM, which is natively supported by iOS (unlike
# CDC-ECM/RNDIS), and also works fine with Windows/macOS/Linux hosts.
# The Pi hands out a DHCP lease to whatever it's plugged into via dnsmasq.
#
# Built via configfs + libcomposite rather than the legacy g_ether/g_ncm
# kernel modules, because current Raspberry Pi OS kernels (Bookworm/Trixie)
# no longer ship g_ncm as a loadable module.
#
# Run this ON THE PI over an existing SSH/console session (not over the USB
# link you're about to reconfigure), as root:
#
#   sudo bash setup_usb_ethernet_gadget.sh
#
# A reboot is required at the end for gadget mode to take effect.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration - edit these if you want a different subnet
# ---------------------------------------------------------------------------
USB0_IP="10.55.0.1"
USB0_PREFIX="24"
USB0_NETMASK="255.255.255.0"
DHCP_RANGE_START="10.55.0.2"
DHCP_RANGE_END="10.55.0.10"
DHCP_LEASE="12h"
HOST_MAC="02:1a:2b:3c:4d:5e"
DEV_MAC="02:1a:2b:3c:4d:5f"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
if [ "$(id -u)" -ne 0 ]; then
  echo "Please run as root: sudo bash $0" >&2
  exit 1
fi

if [ -f /boot/firmware/config.txt ]; then
  BOOT_DIR="/boot/firmware"
else
  BOOT_DIR="/boot"
fi
CONFIG_TXT="$BOOT_DIR/config.txt"
CMDLINE_TXT="$BOOT_DIR/cmdline.txt"

for f in "$CONFIG_TXT" "$CMDLINE_TXT"; do
  [ -f "$f" ] || { echo "Expected file not found: $f" >&2; exit 1; }
done

echo "==> Using boot config: $CONFIG_TXT"
echo "==> Using cmdline:     $CMDLINE_TXT"

cp "$CONFIG_TXT" "${CONFIG_TXT}.bak.$(date +%s)"
cp "$CMDLINE_TXT" "${CMDLINE_TXT}.bak.$(date +%s)"

# ---------------------------------------------------------------------------
# 1. Install dnsmasq (DHCP server)
# ---------------------------------------------------------------------------
echo "==> Installing dnsmasq"
apt-get update -qq
apt-get install -y dnsmasq

# ---------------------------------------------------------------------------
# 2. Enable dwc2 in PERIPHERAL mode, unconditionally.
#
#    IMPORTANT: config.txt supports bracketed sections like [cm4]/[cm5]/[pi5]
#    which scope everything below them to a specific board. Any existing
#    dtoverlay=dwc2 line may already be sitting inside one of those sections
#    (this happens on some default images) and will silently do nothing on
#    other boards. We strip ALL existing dwc2 overlay lines and re-add a
#    single one at the very end of the file, after a fresh [all] marker,
#    so it always applies regardless of what's above it.
# ---------------------------------------------------------------------------
echo "==> Fixing dwc2 overlay (removing any board-scoped duplicates, forcing dr_mode=peripheral)"
sed -i '/^dtoverlay=dwc2/d' "$CONFIG_TXT"
{
  echo ""
  echo "[all]"
  echo "dtoverlay=dwc2,dr_mode=peripheral"
} >> "$CONFIG_TXT"

# ---------------------------------------------------------------------------
# 3. cmdline.txt / /etc/modules cleanup
#
#    We do NOT use modules-load=dwc2,g_ether or g_ncm here - g_ncm doesn't
#    exist as a module on current kernels, and dwc2 is compiled in (builtin)
#    on Raspberry Pi OS anyway, so it doesn't need to be requested via
#    modules-load at all. We only need libcomposite loaded, which the gadget
#    script below depends on.
# ---------------------------------------------------------------------------
echo "==> Cleaning up cmdline.txt (removing any stale modules-load=dwc2,g_ether/g_ncm)"
sed -i -E 's/ ?modules-load=dwc2,g_(ether|ncm)//' "$CMDLINE_TXT"

echo "==> Ensuring libcomposite loads at boot via /etc/modules"
sed -i '/^g_ether$/d; /^g_ncm$/d' /etc/modules
grep -q '^libcomposite$' /etc/modules || echo "libcomposite" >> /etc/modules

# ---------------------------------------------------------------------------
# 4. Gadget-assembly script (configfs + NCM function)
#
#    NOTE on the symlink below: configfs resolves a symlink's target
#    relative to the CURRENT WORKING DIRECTORY at the moment `ln` runs, not
#    relative to the link's own parent directory like a normal filesystem
#    symlink. Since we `cd` into the gadget root first, the target must be
#    written as "functions/ncm.usb0" (relative to that root), NOT
#    "../../functions/ncm.usb0" - the latter looks correct by ordinary
#    symlink logic but resolves outside the gadget directory under configfs
#    and fails with ENOENT.
# ---------------------------------------------------------------------------
echo "==> Writing /usr/local/bin/usb-ncm-gadget.sh"
cat > /usr/local/bin/usb-ncm-gadget.sh <<EOF
#!/bin/bash
set -e

GADGET=/sys/kernel/config/usb_gadget/pigadget
mkdir -p "\$GADGET"
cd "\$GADGET"

echo 0x1d6b > idVendor    # Linux Foundation
echo 0x0104 > idProduct   # Multifunction Composite Gadget
echo 0x0100 > bcdDevice
echo 0x0200 > bcdUSB

mkdir -p strings/0x409
echo "pi-usb-eth-0001" > strings/0x409/serialnumber
echo "Raspberry Pi" > strings/0x409/manufacturer
echo "Pi USB Ethernet Gadget" > strings/0x409/product

mkdir -p configs/c.1/strings/0x409
echo "NCM" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

mkdir -p functions/ncm.usb0
echo "${HOST_MAC}" > functions/ncm.usb0/host_addr
echo "${DEV_MAC}" > functions/ncm.usb0/dev_addr

ln -sf functions/ncm.usb0 configs/c.1/ncm.usb0

udevadm settle -t 5 || true
UDC=\$(ls /sys/class/udc | head -n1)
echo "\$UDC" > UDC
EOF
chmod +x /usr/local/bin/usb-ncm-gadget.sh

# ---------------------------------------------------------------------------
# 5. systemd service to assemble the gadget at boot
# ---------------------------------------------------------------------------
echo "==> Writing usb-ncm-gadget.service"
cat > /etc/systemd/system/usb-ncm-gadget.service <<'EOF'
[Unit]
Description=USB NCM Ethernet Gadget (configfs)
After=local-fs.target sys-kernel-config.mount
Before=network-pre.target dnsmasq.service
Wants=network-pre.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/usb-ncm-gadget.sh

[Install]
WantedBy=sysinit.target
EOF

systemctl daemon-reload
systemctl enable usb-ncm-gadget.service

# ---------------------------------------------------------------------------
# 6. Static IP for usb0
#
#    Current Raspberry Pi OS images (Bookworm/Trixie) default to
#    NetworkManager, not dhcpcd - dhcpcd.conf edits are silently ignored if
#    dhcpcd isn't the active network manager, which is a common trap. We
#    detect which one is actually running and configure accordingly.
# ---------------------------------------------------------------------------
if systemctl is-active --quiet NetworkManager; then
  echo "==> NetworkManager detected - creating usb0-static connection profile"
  nmcli connection show usb0-static >/dev/null 2>&1 && nmcli connection delete usb0-static
  nmcli connection add type ethernet ifname usb0 con-name usb0-static \
    ipv4.method manual ipv4.addresses "${USB0_IP}/${USB0_PREFIX}" \
    ipv4.never-default yes ipv6.method ignore
  # Will actually come up once usb0 exists (after reboot); activate now if present
  nmcli connection up usb0-static >/dev/null 2>&1 || true
elif [ -f /etc/dhcpcd.conf ]; then
  echo "==> dhcpcd detected - configuring static IP via dhcpcd.conf"
  if ! grep -q "^interface usb0" /etc/dhcpcd.conf; then
    cat >> /etc/dhcpcd.conf <<EOF

interface usb0
static ip_address=${USB0_IP}/${USB0_PREFIX}
nohook wpa_supplicant
EOF
  fi
else
  echo "WARNING: neither NetworkManager nor dhcpcd detected; set usb0's static IP manually." >&2
fi

# ---------------------------------------------------------------------------
# 7. dnsmasq: DHCP server scoped to usb0 only
# ---------------------------------------------------------------------------
echo "==> Writing /etc/dnsmasq.d/usb0-gadget.conf"
mkdir -p /etc/dnsmasq.d
cat > /etc/dnsmasq.d/usb0-gadget.conf <<EOF
# DHCP server for the USB Ethernet gadget interface only
interface=usb0
bind-dynamic
except-interface=lo
dhcp-range=${DHCP_RANGE_START},${DHCP_RANGE_END},${USB0_NETMASK},${DHCP_LEASE}
dhcp-option=3,${USB0_IP}
dhcp-option=6,${USB0_IP}
EOF

systemctl unmask dnsmasq >/dev/null 2>&1 || true
systemctl enable dnsmasq >/dev/null 2>&1 || true
systemctl restart dnsmasq || true

# ---------------------------------------------------------------------------
# 8. Optional: NAT so the connected host can reach the internet via wlan0
# ---------------------------------------------------------------------------
read -r -p "Enable IP forwarding + NAT (share Pi's Wi-Fi with the USB host)? [y/N] " NAT_ANS
if [[ "${NAT_ANS:-}" =~ ^[Yy]$ ]]; then
  echo "==> Enabling IP forwarding"
  sed -i 's/^#\s*net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/' /etc/sysctl.conf
  grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf || echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
  sysctl -w net.ipv4.ip_forward=1 >/dev/null

  echo "==> Installing NAT rules (wlan0 <-> usb0)"
  apt-get install -y iptables iptables-persistent
  iptables -t nat -C POSTROUTING -o wlan0 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o wlan0 -j MASQUERADE
  iptables -C FORWARD -i wlan0 -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i wlan0 -o usb0 -m state --state RELATED,ESTABLISHED -j ACCEPT
  iptables -C FORWARD -i usb0 -o wlan0 -j ACCEPT 2>/dev/null || \
    iptables -A FORWARD -i usb0 -o wlan0 -j ACCEPT
  netfilter-persistent save
fi

# ---------------------------------------------------------------------------
# Done
# ---------------------------------------------------------------------------
echo
echo "==> Configuration complete."
echo "    Pi will present as a USB NCM Ethernet gadget (usb0) at ${USB0_IP} after reboot."
echo "    Connected host (including iPhone) will get a DHCP lease in ${DHCP_RANGE_START}-${DHCP_RANGE_END}."
echo "    A reboot is required for the gadget mode changes to take effect."
echo
read -r -p "Reboot now? [y/N] " REBOOT_ANS
if [[ "${REBOOT_ANS:-}" =~ ^[Yy]$ ]]; then
  reboot
fi
