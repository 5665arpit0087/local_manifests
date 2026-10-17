#!/bin/bash
# RisingOS sixteen-qpr2 for Xiaomi 14 Civi (chenfeng) — vanilla first-green build.
# Runs ON the Crave builder as the whole `crave run` command body.
# Host this file in a GitHub repo and trigger with a one-liner, e.g.:
#   crave run --projectID 99 --no-patch -- "curl -sf https://raw.githubusercontent.com/<you>/<repo>/refs/heads/main/crave_build_chenfeng_vanilla.sh | bash"
# Rules-compliant: only .repo/local_manifests is re-cloned, no installclean/--clean,
# mka (parallel), one build at a time.
set -o pipefail
BACON=127

rm -rf .repo/local_manifests
repo init -u https://github.com/RisingOS-Revived/android -b sixteen-qpr2 --git-lfs --depth 1 \
&& git clone https://github.com/kanup4m/local_manifests.git --depth 1 -b rising-16 .repo/local_manifests \
&& /opt/crave/resync.sh \
&& bash device/xiaomi/chenfeng/vendorsetup.sh \
&& (git -C vendor/xiaomi/chenfeng-miuicamera lfs pull || echo WARN_MIUICAMERA_LFS_PULL_FAILED) \
&& bash <<'FIXEOF' &&
set -u
say() { echo "[chenfeng-fix] $*"; }
say "fix-0 vanilla GMS off"
if [ -f device/xiaomi/chenfeng/rising_chenfeng.mk ]; then
  grep -n 'WITH_GMS\|PICO_GAPPS' device/xiaomi/chenfeng/rising_chenfeng.mk || true
  sed -i 's/^WITH_GMS := true/WITH_GMS := false/' device/xiaomi/chenfeng/rising_chenfeng.mk || true
  sed -i 's/^TARGET_USES_PICO_GAPPS := true/#TARGET_USES_PICO_GAPPS := true  # vanilla first-green: disabled/' device/xiaomi/chenfeng/rising_chenfeng.mk || true
else say "fix-0 SKIP: rising_chenfeng.mk not found"; fi
SB="packages/providers/ContactsProvider/src/com/android/providers/contacts/util/SelectionBuilder.java"
if [ -f "$SB" ]; then
  if grep -q 'OPTION_CHECK_BRACKETS' "$SB"; then
    sed -i 's/SQLiteTokenizer\.OPTION_CHECK_BRACKETS, null/SQLiteTokenizer.OPTION_NONE, token -> {}/' "$SB"
    say "fix-1 APPLIED: OPTION_CHECK_BRACKETS -> OPTION_NONE"
  else say "fix-1 SKIP"; fi
else say "fix-1 SKIP: $SB not found"; fi
for f in packages/apps/Settings/src/com/android/settings/applications/specialaccess/deviceadmin/DeviceAdminAdd.java \
         packages/apps/Settings/src/com/android/settings/applications/specialaccess/deviceadmin/DeviceAdminListItem.java; do
  if [ -f "$f" ]; then
    if grep -q 'loadDescriptionSafe(' "$f"; then
      sed -i 's/loadDescriptionSafe(/loadDescription(/g' "$f"
      say "fix-2 APPLIED in $(basename "$f")"
    else say "fix-2 SKIP in $(basename "$f")"; fi
  else say "fix-2 SKIP: $f not found"; fi
done
for f in frameworks/libs/systemui/tracinglib/Android.bp \
         frameworks/libs/systemui/tracinglib/benchmark/Android.bp; do
  if [ -f "$f" ]; then
    if grep -q 'trendy_team_performance' "$f"; then
      sed -i '/default_team: "trendy_team_performance",/d' "$f"
      say "fix-3 APPLIED in $f"
    else say "fix-3 SKIP in $f"; fi
  else say "fix-3 SKIP: $f not found"; fi
done
CLBP="packages/providers/CallLogProvider/Android.bp"
if [ -f "$CLBP" ]; then
  if grep -q 'name: "telecom-util-lib"' packages/services/Telecomm/Android.bp 2>/dev/null; then
    say "fix-4a provider telecom-util-lib present in packages/services/Telecomm"
    if grep -q 'telecom_utils' "$CLBP"; then
      sed -i 's/telecom_utils/telecom-util-lib/g' "$CLBP"
      say "fix-4a REVERTED: telecom_utils -> telecom-util-lib in CallLogProvider/Android.bp"
    else say "fix-4a KEEP: dep already telecom-util-lib"; fi
  elif grep -q 'telecom-util-lib' "$CLBP"; then
    say "fix-4a WARN: provider absent in-tree; leaving telecom-util-lib"
  else say "fix-4a SKIP"; fi
else say "fix-4a SKIP: $CLBP not found"; fi
CLBA="packages/providers/CallLogProvider/src/com/android/calllogbackup/CallLogBackupAgent.java"
if [ -f "$CLBA" ]; then
  if grep -q 'PREFERRED_DISPLAY_NAME' "$CLBA"; then
    sed -i '/call\.preferredDisplayName = cursor\.getString/,+1d' "$CLBA" || true
    sed -i '/^\s*Calls\/PREFERRED_DISPLAY_NAME\s*$/d' "$CLBA" || true
    sed -i 's/CallLog\.Calls\.UUID,$/CallLog.Calls.UUID/' "$CLBA" || true
    if grep -q 'PREFERRED_DISPLAY_NAME' "$CLBA"; then
      say "fix-4b WARN: residue remains"; grep -n 'PREFERRED_DISPLAY_NAME' "$CLBA" || true
    else say "fix-4b APPLIED"; fi
  else say "fix-4b SKIP"; fi
else say "fix-4b SKIP: $CLBA not found"; fi
# --- fix-5: SystemUI displaylib/mechanics deps (provider-aware) ---
# displaylib/ lives at frameworks/libs/systemui/displaylib (Lineage tree HAS it;
# Rising's fork does not). SystemUI genuinely imports com.android.app.displaylib.*
# so when the provider module exists in-tree the dep must be PRESENT; restore it
# if a previous run deleted it. mechanics-compose is needed by Rising's Kotlin
# sources (OverlayShade, QS Tile) -> restore it too when its provider exists.
DLBP="frameworks/libs/systemui/displaylib/Android.bp"
MCOM="frameworks/libs/systemui/mechanics/compose/Android.bp"
HAVE_DL=0; HAVE_MC=0
[ -f "$DLBP" ] && grep -q 'name: "displaylib"' "$DLBP" 2>/dev/null && HAVE_DL=1
[ -f "$MCOM" ] && grep -q 'name: "mechanics-compose"' "$MCOM" 2>/dev/null && HAVE_MC=1
say "fix-5 providers: displaylib=$HAVE_DL mechanics-compose=$HAVE_MC"
SUI="frameworks/base/packages/SystemUI/Android.bp"
if [ -f "$SUI" ]; then
  NEED_RESTORE=0
  if [ "$HAVE_DL" -eq 1 ]; then
    grep -q '"displaylib",' "$SUI" || NEED_RESTORE=1
  fi
  if [ "$HAVE_MC" -eq 1 ]; then
    grep -q 'mechanics/compose:mechanics-compose' "$SUI" || NEED_RESTORE=1
  fi
  if [ "$NEED_RESTORE" -eq 1 ]; then
    if git -C frameworks/base checkout -- packages/SystemUI/Android.bp 2>/dev/null; then
      say "fix-5 RESTORED: SystemUI/Android.bp from git"
    else
      say "fix-5 WARN: git checkout failed for SystemUI/Android.bp"
    fi
  else
    say "fix-5 KEEP: SystemUI deps present"
  fi
  if [ "$HAVE_DL" -eq 0 ] && grep -q '"displaylib",' "$SUI"; then
    sed -i '/"displaylib",/d' "$SUI"; say "fix-5 APPLIED: displaylib dropped (no provider)"
  fi
  if [ "$HAVE_MC" -eq 0 ] && grep -q 'mechanics/compose:mechanics-compose' "$SUI"; then
    sed -i '/mechanics\/compose:mechanics-compose/d' "$SUI"; say "fix-5 APPLIED: mechanics-compose dropped (no provider)"
  fi
  say "fix-5 state: displaylib_dep=$(grep -c '"displaylib",' "$SUI" || true) mechanics_dep=$(grep -c 'mechanics/compose:mechanics-compose' "$SUI" || true)"
else say "fix-5 SKIP: $SUI not found"; fi
SDEMO="development/samples/SceneTransitionLayoutDemo/Android.bp"
if [ -f "$SDEMO" ]; then
  if [ "$HAVE_MC" -eq 1 ]; then
    if grep -q 'mechanics/compose:mechanics-compose' "$SDEMO"; then
      say "fix-5 KEEP: demo mechanics dep present"
    elif git -C development checkout -- samples/SceneTransitionLayoutDemo/Android.bp 2>/dev/null; then
      say "fix-5 RESTORED: demo Android.bp from git"
    else say "fix-5 WARN: git checkout failed for demo Android.bp"; fi
  elif grep -q 'mechanics/compose:mechanics-compose' "$SDEMO"; then
    sed -i '/mechanics\/compose:mechanics-compose/d' "$SDEMO"; say "fix-5 APPLIED: demo mechanics-compose dropped"
  else say "fix-5 SKIP: demo mechanics-compose"; fi
else say "fix-5 SKIP: $SDEMO not found"; fi
say "all inline fixes done"
# --- fix-6: lineage sepolicy rw_dir_file macro (never reaches M4 in Rising builds) ---
# device/lineage/sepolicy/common/public/te_macros defines rw_dir_file, but its
# include path is absent, so checkpolicy dies with 'syntax error'. Inline-expand
# with the exact upstream definition:
#   rw_dir_file(X, Y) -> allow X Y:dir r_dir_perms; + allow X Y:{ file lnk_file } rw_file_perms;
for f in device/lineage/sepolicy/qcom/vendor/hal_lineage_health_default.te \
         device/lineage/sepolicy/qcom/vendor/hal_perf_default.te \
         device/lineage/sepolicy/qcom/vendor/hal_power_default.te; do
  if [ -f "$f" ]; then
    if grep -q '^rw_dir_file(' "$f"; then
      sed -i -E 's/^rw_dir_file\(([A-Za-z0-9_]+), ([A-Za-z0-9_]+)\)$/allow \1 \2:dir r_dir_perms;\nallow \1 \2:{ file lnk_file } rw_file_perms;/' "$f"
      if grep -q '^rw_dir_file(' "$f"; then
        say "fix-6 WARN: residue in $(basename "$f"):"; grep -n '^rw_dir_file(' "$f" || true
      else
        say "fix-6 APPLIED: expanded rw_dir_file in $(basename "$f")"
      fi
    else
      say "fix-6 SKIP: no rw_dir_file in $(basename "$f")"
    fi
  else
    say "fix-6 SKIP: $f not found"
  fi
done
REMNANTS=$(grep -rn '^rw_dir_file(' device/lineage/sepolicy/ 2>/dev/null || true)
if [ -n "$REMNANTS" ]; then
  say "fix-6 WARN: other rw_dir_file users remain:"; echo "$REMNANTS" | head -20
else
  say "fix-6 sweep clean: no rw_dir_file left under device/lineage/sepolicy"
fi
# --- fix-7: lineage sepolicy undeclared attributes (same include-path root cause) ---
# checkpolicy fails 'attribute X is not declared' for typeattribute lines whose
# attribute exists nowhere in the compiled inputs (e.g. hal_lineage_livedisplay
# server attribute; neither upstream declares it). Diagnose repo state (builder
# copy has differed from upstream HEAD before: stale checkout / mid-rebase),
# then comment out the offending line if the attribute is truly absent.
SP_LIVE="device/lineage/sepolicy/qcom/vendor/hal_lineage_livedisplay_qti.te"
if [ -d device/lineage/sepolicy ]; then
  say "fix-7 sepolicy repo state:"; git -C device/lineage/sepolicy log --oneline -3 2>/dev/null || say "fix-7 WARN: git log unreadable"; git -C device/lineage/sepolicy diff --stat 2>/dev/null | head -10 || true
  if [ -f "$SP_LIVE" ]; then
    if grep -q '^typeattribute hal_lineage_livedisplay_qti hal_lineage_livedisplay_server;' "$SP_LIVE"; then
      if grep -rq '^attribute hal_lineage_livedisplay_server;' device/lineage/sepolicy/ 2>/dev/null || grep -rq '^attribute hal_lineage_livedisplay_server;' system/sepolicy/ 2>/dev/null; then
        say "fix-7 KEEP: hal_lineage_livedisplay_server declared somewhere"
      else
        sed -i 's/^typeattribute hal_lineage_livedisplay_qti hal_lineage_livedisplay_server;/# fix-7: hal_lineage_livedisplay_server never declared in-tree/' "$SP_LIVE"
        say "fix-7 APPLIED: neutralized undeclared-attribute typeattribute in hal_lineage_livedisplay_qti.te"
      fi
    else
      say "fix-7 SKIP: no livedisplay_server typeattribute line"
    fi
  else say "fix-7 SKIP: $SP_LIVE not found"; fi
  say "fix-7 sweep: typeattribute lines in lineage qcom/vendor:"; grep -rhn '^typeattribute ' device/lineage/sepolicy/qcom/vendor/ 2>/dev/null | head -20 || true
else say "fix-7 SKIP: device/lineage/sepolicy not found"; fi
# --- fix-8: livedisplay attribute gone from source but still compiled => stale sepolicy intermediates ---
# 304256 and 304473 both failed at the SAME concatenated position (line 69857) even
# though the working-tree .te no longer contains the line (fix-7 verified clean,
# upstream HEAD verified clean). Identical offset across runs means the compiled
# input did not change -> out/soong/.intermediates/system/sepolicy/* is stale.
say "fix-8 workspace-wide hunt for livedisplay_server references:"
HUNT=$(grep -rn --include='*.te' 'hal_lineage_livedisplay_server' device/ vendor/ hardware/ system/ frameworks/ packages/ 2>/dev/null | head -30 || true)
if [ -n "$HUNT" ]; then echo "$HUNT"; else say "fix-8 hunt: no .te references anywhere in tree"; fi
DLFILE="device/lineage/sepolicy/qcom/vendor/hal_lineage_livedisplay_qti.te"
if [ -f "$DLFILE" ]; then
  say "fix-8 first 3 lines (cat -A, reveals CR/hidden chars):"; cat -A "$DLFILE" | sed -n '1,3p' | head -5
  if grep -q 'hal_lineage_livedisplay_server' "$DLFILE"; then
    sed -i 's/typeattribute hal_lineage_livedisplay_qti hal_lineage_livedisplay_server;/# fix-8: undeclared attribute neutralized/' "$DLFILE"
    say "fix-8 APPLIED: neutralized in $DLFILE"
  fi
fi
# fix-12: the stale-intermediates theory is disproven -- the identical failure offset
# (line 69857) is deterministic m4 output, not stale files. rm disabled so we stop
# forcing a full sepolicy rebuild every run (ninja tracks the inputs anyway).
# if [ -d out/soong/.intermediates/system/sepolicy ]; then
#   rm -rf out/soong/.intermediates/system/sepolicy
#   say "fix-8 REMOVED stale intermediates: out/soong/.intermediates/system/sepolicy (single module, not rm -rf out)"
# else say "fix-8 no stale intermediates dir present"; fi
say "fix-8 stale-intermediates rm disabled (root cause fixed by fix-12)"
# --- fix-12: lineage common sepolicy dirs (ROOT CAUSE of every sepolicy-stage failure) ---
# This device builds vendor.img from source (BOARD_VENDORIMAGE_FILE_SYSTEM_TYPE=ext4 ->
# TARGET_USES_PREBUILT_VENDOR_SEPOLICY stays unset -> device/lineage/sepolicy/qcom/sepolicy.mk
# takes its else-branch), so device/lineage/sepolicy/qcom/{dynamic,vendor} ARE compiled into
# vendor_sepolicy.conf -- but nothing in the tree ever registers device/lineage/sepolicy/common,
# which those files depend on:
#   common/public  -> SYSTEM_EXT_PUBLIC (attributes + te_macros; also flows into vendor conf)
#   common/dynamic -> BOARD_VENDOR      (same conf as the qcom files that use them)
#   common/vendor  -> BOARD_VENDOR      (defines hal_lineage_health/touch/powershare domains)
# Fixes BOTH error classes: 'rw_dir_file' syntax error (304075) and 'attribute
# hal_lineage_livedisplay_server is not declared' (304256..305174 -- that typeattribute line
# is generated by hal_server_domain() at build time, which is why fix-7/8/9/10 greps could
# never find it).
BC=device/xiaomi/chenfeng/BoardConfig.mk
if [ -f "$BC" ]; then
  if grep -q 'device/lineage/sepolicy/common/public' "$BC"; then
    say "fix-12 KEEP: lineage common sepolicy dirs already registered"
  else
    sed -i '/^include device\/qcom\/sepolicy_vndr\/SEPolicy\.mk$/a SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device/lineage/sepolicy/common/public' "$BC" || true
    sed -i '/^SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device\/lineage\/sepolicy\/common\/public$/a BOARD_VENDOR_SEPOLICY_DIRS += device/lineage/sepolicy/common/dynamic device/lineage/sepolicy/common/vendor' "$BC" || true
    if grep -q 'device/lineage/sepolicy/common/dynamic' "$BC"; then
      say "fix-12 APPLIED: registered lineage common sepolicy dirs in BoardConfig.mk"
    else
      say "fix-12 WARN: sed anchor missed; appending to end of BoardConfig.mk"
      printf '\nSYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device/lineage/sepolicy/common/public\nBOARD_VENDOR_SEPOLICY_DIRS += device/lineage/sepolicy/common/dynamic device/lineage/sepolicy/common/vendor\n' >> "$BC"
    fi
  fi
  grep -n 'lineage/sepolicy/common' "$BC" || true
else
  say "fix-12 SKIP: $BC not found"
fi
# The device tree declares vendor_persist_camera_prop in system_ext-private as a workaround
# for the missing common/public. It now duplicates what common/public/property.te brings
# (system_ext public -> visible in BOTH the system_ext conf and the vendor conf where
# common/vendor/hal_camera_default.te needs it). Required exactly once; the file returns on
# every resync, so drop it on every build (guarded: only when the dirs got registered).
WP="device/xiaomi/chenfeng/sepolicy/system_ext-private/vendor_persist_camera_prop.te"
if grep -q 'device/lineage/sepolicy/common/public' "$BC" 2>/dev/null; then
  if [ -f "$WP" ]; then
    rm -f "$WP"
    say "fix-12 REMOVED duplicate workaround: $(basename "$WP") (common/public now declares the prop)"
  else
    say "fix-12 workaround already absent: $(basename "$WP")"
  fi
else
  say "fix-12 WARN: keeping $WP (common dirs not registered)"
fi
# --- fix-13: lineage mosey sepolicy dirs (mosey_app was never declared) ---
# Rising's private/compat/34.0/34.0.cil adds the mapping 'mosey_app_34_0 -> mosey_app'
# (commit 64fe3aff33 "sepolicy: Add mosey_app to compat mapping") and MoseyApp ships in
# this build (vendor/gms/system_ext/packages/privileged_apps/MoseyApp), but nothing ever
# registered device/lineage/sepolicy/mosey, so 34.0_compat_test died at:
#   Failed to resolve typeattributeset statement at .../plat_34.0.cil:2068
# Only the 34.0 test failed because combine_maps() propagates a mapping only into
# version maps that already carry the name, and mosey_app appears solely in the 34.0 map.
# Rising's own device_lineage_sepolicy/common/sepolicy.mk registers all three dirs for
# every non-Pixel-buds target, so mirror it:
#   mosey/system_ext/public  -> SYSTEM_EXT_PUBLIC  (declares 'type mosey_app, domain;')
#   mosey/system_ext/private -> SYSTEM_EXT_PRIVATE (app_domain/net_domain/coredomain,
#                                                   seapp_contexts for the Mosey app)
#   mosey/vendor             -> BOARD_VENDOR       (mosey_server/mosey_service domains)
if [ -f "$BC" ]; then
  if grep -q 'device/lineage/sepolicy/mosey' "$BC"; then
    say "fix-13 KEEP: lineage mosey sepolicy dirs already registered"
  else
    sed -i '/^SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device\/lineage\/sepolicy\/common\/public$/a SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device/lineage/sepolicy/mosey/system_ext/public' "$BC" || true
    sed -i '/^SYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device\/lineage\/sepolicy\/mosey\/system_ext\/public$/a SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device/lineage/sepolicy/mosey/system_ext/private' "$BC" || true
    sed -i '/^SYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device\/lineage\/sepolicy\/mosey\/system_ext\/private$/a BOARD_VENDOR_SEPOLICY_DIRS += device/lineage/sepolicy/mosey/vendor' "$BC" || true
    if grep -q 'device/lineage/sepolicy/mosey' "$BC"; then
      say "fix-13 APPLIED: registered lineage mosey sepolicy dirs in BoardConfig.mk"
    else
      say "fix-13 WARN: sed anchor missed; appending to end of BoardConfig.mk"
      printf '\nSYSTEM_EXT_PUBLIC_SEPOLICY_DIRS += device/lineage/sepolicy/mosey/system_ext/public\nSYSTEM_EXT_PRIVATE_SEPOLICY_DIRS += device/lineage/sepolicy/mosey/system_ext/private\nBOARD_VENDOR_SEPOLICY_DIRS += device/lineage/sepolicy/mosey/vendor\n' >> "$BC"
    fi
  fi
  for d in device/lineage/sepolicy/mosey/system_ext/public device/lineage/sepolicy/mosey/system_ext/private device/lineage/sepolicy/mosey/vendor; do
    if [ -d "$d" ]; then say "fix-13 dir present: $d"; else say "fix-13 WARN: dir missing: $d"; fi
  done
  grep -n 'lineage/sepolicy/mosey' "$BC" || true
else
  say "fix-13 SKIP: $BC not found"
fi
FIXEOF
source build/envsetup.sh \
&& lunch rising_chenfeng-user \
&& (echo "[chenfeng-fix] fix-9 pre-build sepolicy proof:"; DLF="device/lineage/sepolicy/qcom/vendor/hal_lineage_livedisplay_qti.te"; md5sum "$DLF" 2>/dev/null || echo "fix-9 WARN: md5sum failed"; git -C device/lineage/sepolicy status --short 2>/dev/null | head -10 || echo "fix-9 WARN: git status unreadable"; if grep -q 'hal_lineage_livedisplay_server' "$DLF" 2>/dev/null; then echo "[chenfeng-fix] fix-9 RE-DIRTIED: line present at build time, neutralizing:"; grep -n 'hal_lineage_livedisplay_server' "$DLF"; sed -i 's/typeattribute hal_lineage_livedisplay_qti hal_lineage_livedisplay_server;/# fix-9: re-dirtied after fixes, neutralized pre-build/' "$DLF"; else echo "[chenfeng-fix] fix-9 CLEAN: no livedisplay_server in working-tree file at build time"; fi; echo "[chenfeng-fix] fix-9 stale-hunt in out/:"; STALE=$(timeout 120 grep -rl 'hal_lineage_livedisplay_server' out/soong/.intermediates/system/sepolicy out/target/product/chenfeng/obj/ETC 2>/dev/null | head -20 || true); if [ -n "$STALE" ]; then echo "$STALE"; else echo "[chenfeng-fix] fix-9 hunt: string absent from sepolicy intermediates"; fi; echo "[chenfeng-fix] fix-9 attribute-declared-anywhere:"; DECL=$(grep -rn --include='*.te' '^attribute hal_lineage_livedisplay_server;' device/lineage/sepolicy/ system/sepolicy/ device/xiaomi/chenfeng/sepolicy/ hardware/xiaomi/ 2>/dev/null | head -5 || true); if [ -n "$DECL" ]; then echo "$DECL"; else echo "[chenfeng-fix] fix-9: attribute declared nowhere in sepolicy inputs"; fi; true) \
&& (echo "[chenfeng-fix] fix-10 unrestricted hunt (no --include; .repo/.git/out excluded):"; timeout 300 grep -rnI --exclude-dir=.repo --exclude-dir=.git --exclude-dir=out 'hal_lineage_livedisplay_server' device/ vendor/ hardware/ system/ frameworks/ packages/ 2>/dev/null | head -30 || true; echo "[chenfeng-fix] fix-10 symlinks under sepolicy inputs:"; find device/lineage/sepolicy device/xiaomi/chenfeng/sepolicy hardware/xiaomi system/sepolicy -type l 2>/dev/null | head -20 || true; echo "[chenfeng-fix] fix-10 cwd/TOP:"; pwd; echo "TOP=$TOP"; readlink -f device/lineage/sepolicy 2>/dev/null || true; echo "[chenfeng-fix] fix-10 leftover conf from previous build:"; CONF10="out/soong/.intermediates/system/sepolicy/vendor_sepolicy.conf/android_common/chenfeng/vendor_sepolicy.conf"; DLF10="device/lineage/sepolicy/qcom/vendor/hal_lineage_livedisplay_qti.te"; if [ -f "$CONF10" ]; then ls --full-time "$CONF10" "$DLF10" 2>/dev/null || true; grep -n 'hal_lineage_livedisplay_server' "$CONF10" 2>/dev/null | head -10 || echo "[chenfeng-fix] fix-10: string absent from leftover conf"; else echo "[chenfeng-fix] fix-10: no leftover conf present"; fi; true) \
&& mka bacon 2>&1 | tee build.log; BACON=${PIPESTATUS[0]};
if [ "$BACON" -ne 0 ] || grep -q -E "ninja failed|failed to build some targets" build.log; then echo CRAVE_BUILD_FAILED; else echo CRAVE_BUILD_DONE; fi;
ls out/target/product/chenfeng/*.zip 2>/dev/null || true;
echo "[chenfeng-fix] fix-10 post-mortem:"; CONF10="out/soong/.intermediates/system/sepolicy/vendor_sepolicy.conf/android_common/chenfeng/vendor_sepolicy.conf"; DLF10="device/lineage/sepolicy/qcom/vendor/hal_lineage_livedisplay_qti.te"; ls --full-time "$CONF10" "$DLF10" 2>/dev/null || true; grep -n 'hal_lineage_livedisplay_server' "$CONF10" 2>/dev/null | head -10 || echo "[chenfeng-fix] fix-10 post: string absent from conf"; sed -n '69850,69862p' "$CONF10" 2>/dev/null || true; echo "[chenfeng-fix] fix-10 post: scoped stale-hunt:"; timeout 120 grep -rl 'hal_lineage_livedisplay_server' out/soong/.intermediates/system/sepolicy out/target/product/chenfeng/obj/ETC 2>/dev/null | head -20 || echo "[chenfeng-fix] fix-10 post: absent from sepolicy intermediates"; true
