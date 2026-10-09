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
if [ -d out/soong/.intermediates/system/sepolicy ]; then
  rm -rf out/soong/.intermediates/system/sepolicy
  say "fix-8 REMOVED stale intermediates: out/soong/.intermediates/system/sepolicy (single module, not rm -rf out)"
else say "fix-8 no stale intermediates dir present"; fi
FIXEOF
source build/envsetup.sh \
&& lunch rising_chenfeng-user \
&& (echo "[chenfeng-fix] fix-9 pre-build sepolicy proof:"; DLF="device/lineage/sepolicy/qcom/vendor/hal_lineage_livedisplay_qti.te"; md5sum "$DLF" 2>/dev/null || echo "fix-9 WARN: md5sum failed"; git -C device/lineage/sepolicy status --short 2>/dev/null | head -10 || echo "fix-9 WARN: git status unreadable"; if grep -q 'hal_lineage_livedisplay_server' "$DLF" 2>/dev/null; then echo "[chenfeng-fix] fix-9 RE-DIRTIED: line present at build time, neutralizing:"; grep -n 'hal_lineage_livedisplay_server' "$DLF"; sed -i 's/typeattribute hal_lineage_livedisplay_qti hal_lineage_livedisplay_server;/# fix-9: re-dirtied after fixes, neutralized pre-build/' "$DLF"; else echo "[chenfeng-fix] fix-9 CLEAN: no livedisplay_server in working-tree file at build time"; fi; echo "[chenfeng-fix] fix-9 stale-hunt in out/:"; STALE=$(grep -rl 'hal_lineage_livedisplay_server' out/ 2>/dev/null | head -20 || true); if [ -n "$STALE" ]; then echo "$STALE"; else echo "[chenfeng-fix] fix-9 hunt: string absent from out/"; fi; echo "[chenfeng-fix] fix-9 attribute-declared-anywhere:"; DECL=$(grep -rn --include='*.te' '^attribute hal_lineage_livedisplay_server;' device/lineage/sepolicy/ system/sepolicy/ device/xiaomi/chenfeng/sepolicy/ hardware/xiaomi/ 2>/dev/null | head -5 || true); if [ -n "$DECL" ]; then echo "$DECL"; else echo "[chenfeng-fix] fix-9: attribute declared nowhere in sepolicy inputs"; fi; true) \
&& mka bacon 2>&1 | tee build.log; BACON=${PIPESTATUS[0]};
if [ "$BACON" -ne 0 ] || grep -q -E "ninja failed|failed to build some targets" build.log; then echo CRAVE_BUILD_FAILED; else echo CRAVE_BUILD_DONE; fi;
ls out/target/product/chenfeng/*.zip 2>/dev/null || true
