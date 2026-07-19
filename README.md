# openwrt-proxmox-image

Generic [OpenWrt](https://openwrt.org) x86-64 image for Proxmox VE with
first-boot **cloud-init (NoCloud)** support, built with the official
[ImageBuilder](https://openwrt.org/docs/guide-user/additional-software/imagebuilder)
on GitHub Actions.

Nothing personal is baked into the image — hostname, SSH keys, and network
configuration are injected at provision time from the Proxmox cloud-init
drive by a small first-boot script (`files/etc/uci-defaults/90-cloud-init`).

## Downloads

Each build is published as an **immutable** GitHub Release tagged
`v<openwrt-version>-<build>` (e.g. `v25.12.5-1`), containing:

- `openwrt-<version>-proxmox-x86-64-generic-ext4-combined.img.gz`
- `sha256sums.txt`

The build revision distinguishes image rebuilds on the same OpenWrt version:
changing `packages.txt` or `files/` publishes the next revision
(`v25.12.5-1` → `v25.12.5-2`) rather than overwriting the previous image, so
provisioned VMs keep pointing at exactly the image they were built from. A new
OpenWrt version restarts the revision at `-1`. The OpenWrt version alone still
names the image file inside the release.

## Using with Proxmox

1. Download and unpack the image, import it as a VM disk
   (`qm disk import` / ansible `proxmox_disk` with `import_from`).
2. Add a **CloudInit drive** (`ide2: <storage>:cloudinit`, `citype: nocloud`).
3. Set cloud-init options: SSH public key, and a static IP on the NIC you want
   as management (`ipconfig<N>` matches `eth<N>` in the guest), e.g.:

   ```
   qm set <vmid> --ide2 local-zfs:cloudinit --citype nocloud \
     --ciuser root --sshkeys ~/.ssh/id_ed25519.pub \
     --ipconfig1 ip=192.0.2.10/24,gw=192.0.2.1 --nameserver 192.0.2.1
   ```

4. Boot. The first-boot script mounts the CIDATA volume and applies hostname,
   SSH authorized keys, and static/DHCP interface config, then deletes itself.
   The stock `192.168.1.1` LAN + DHCP server is removed when network config is
   provided. Without a cloud-init drive the image boots with stock OpenWrt
   defaults.

Only Proxmox-generated NoCloud data is supported (parsed line-wise); it is
not a general cloud-init implementation.

## Customising

- `packages.txt` — packages baked into the image (one per line, `-` removes)
- `build.sh` — profile, rootfs size, OpenWrt version pin (kept current by
  Renovate; merging the bump PR builds and publishes the new release)

Build locally with just docker: `./build.sh`

## Notes

- `ROOTFS_PARTSIZE` must stay constant across releases: x86 `sysupgrade`
  rewrites the partition table from the image.
- Image uses OpenSSH instead of dropbear and includes python3, so it is
  ansible-manageable out of the box.
