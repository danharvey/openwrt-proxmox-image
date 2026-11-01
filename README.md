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

The image records its own release tag (without the leading `v`) in
`/etc/openwrt_release_tag`, e.g. `25.12.5-2`. `/etc/openwrt_release` only
carries the OpenWrt version, so this is how a running system tells which build
revision it has, for example to skip an upgrade it already has. `sysupgrade`
replaces it with the new image's copy; don't add it to `/etc/sysupgrade.conf`,
or the old tag is restored over the new one.

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
  Renovate, see below)

Build locally with just docker: `./build.sh`

## Updates and releases

How a new image gets published:

1. [Renovate](https://docs.renovatebot.com) watches the
   `openwrt/imagebuilder` tag pinned in `build.sh` (see `renovate.json`).
2. **Point/minor releases** (e.g. `25.12.6` → `25.12.7`): Renovate opens a PR
   as soon as the tag appears and **automerges** it. These are bug-fix and
   security releases within a series, with the same package names.
3. **Major series bumps** (e.g. `25.12` → `26.x`) open a PR but are **not**
   automerged. Package names and defaults change between series (25.12
   replaced `acme` with `acme-acmesh`, for example), so `packages.txt` and
   `files/` need reviewing first.
4. **Digest-only updates** (the same tag rebuilt upstream) are disabled. They
   don't change the OpenWrt version and would only add new revisions.
5. Every push to `main` that touches `build.sh`, `packages.txt`, `files/` or
   the workflow runs `.github/workflows/build.yml`. That works out the next
   `v<version>-<build>` tag, builds the image with it baked in, and publishes
   the release.

Things to keep in mind when changing this:

- **Releases are immutable** (repository setting). A published release can't
  gain or replace assets, so the workflow creates a **draft**, uploads the
  image and checksums, then publishes. Don't split it into create-then-upload:
  that publishes an empty release that can't be repaired.
- If a build fails before publishing, a leftover draft can consume a revision
  number. Delete the draft and re-run the workflow (`workflow_dispatch`).
- The PR has no CI checks (the build only runs on `main`), so the automerge
  rule uses `ignoreTests`. A broken build shows up as a failed run on `main`
  with no release published. Previous releases are unaffected.
- This repo only **publishes** images. Rolling a release out to running
  routers is up to each user. Test a new image on a non-production VM first
  (snapshot, `sysupgrade`, check your config), since automerge here means no
  human has booted the image before it's released.

## Notes

- `ROOTFS_PARTSIZE` must stay constant across releases: x86 `sysupgrade`
  rewrites the partition table from the image.
- Image uses OpenSSH instead of dropbear and includes python3, so it is
  ansible-manageable out of the box.
