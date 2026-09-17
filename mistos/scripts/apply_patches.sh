#!/usr/bin/env bash
# Apply the per-repo patches in patches/rom to a synced ~/mistos tree.
# Usage: cd ~/mistos && bash apply_patches.sh /path/to/patches/rom
# Patch file names encode the repo path with '_' for '/', e.g.
#   device_google_shusky.patch -> device/google/shusky
# (repos whose own name contains '_' are handled by the explicit map below).
set -u
PDIR="${1:?patch dir}"
declare -A MAP=(
  [build_make]=build/make
  [build_soong]=build/soong
  [device_google_shusky]=device/google/shusky
  [device_google_zuma]=device/google/zuma
  [device_lineage_sepolicy]=device/lineage/sepolicy
  [frameworks_base]=frameworks/base
  [hardware_google_pixel]=hardware/google/pixel
  [packages_apps_Settings]=packages/apps/Settings
  [system_memory_libdmabufheap]=system/memory/libdmabufheap
  [vendor_JamesDSP]=vendor/JamesDSP
  [vendor_extras]=vendor/extras
  [vendor_gms]=vendor/gms
  [vendor_google_faceunlock]=vendor/google/faceunlock
  [vendor_google_husky]=vendor/google/husky
  [vendor_google_shiba]=vendor/google/shiba
  [vendor_lineage]=vendor/lineage
  [vendor_pixel-style]=vendor/pixel-style
)
ok=0; fail=0
for f in "$PDIR"/*.patch; do
  n=$(basename "$f" .patch)
  repo="${MAP[$n]:-}"
  if [ -z "$repo" ] || [ ! -d "$repo" ]; then echo "SKIP  $n (unknown repo path)"; continue; fi
  if git -C "$repo" apply --check "$f" 2>/dev/null && git -C "$repo" apply "$f"; then
    echo "OK    $repo"; ok=$((ok+1))
  elif git -C "$repo" apply --3way "$f" 2>/dev/null; then
    echo "OK3W  $repo (3-way merge, review 'git -C $repo status')"; ok=$((ok+1))
  else
    echo "FAIL  $repo  -> re-apply by hand from files/ and HANDOFF.md"; fail=$((fail+1))
  fi
done
echo "applied=$ok failed=$fail"
echo "Remember: device/google/shusky-kernels/boot.img must be re-stamped separately (README section 4)."
