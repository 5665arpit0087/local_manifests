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
# if a previous run deleted it. mechanics-compose is a stale dep (no source
# imports it) -> always drop it.
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
FIXEOF
source build/envsetup.sh \
&& lunch rising_chenfeng-user \
&& mka bacon 2>&1 | tee build.log; BACON=${PIPESTATUS[0]};
if [ "$BACON" -ne 0 ] || grep -q -E "ninja failed|failed to build some targets" build.log; then echo CRAVE_BUILD_FAILED; else echo CRAVE_BUILD_DONE; fi;
ls out/target/product/chenfeng/*.zip 2>/dev/null || true
