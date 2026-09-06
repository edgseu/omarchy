#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# These assertions pin the face-authentication contracts that routing and the
# PAM flow depend on. Routing itself (omarchy setup security face) is covered
# by test/cli.

SETUP="$ROOT/bin/omarchy-setup-security-face"
REMOVE="$ROOT/bin/omarchy-remove-security-face"
SERVICE="$ROOT/shell/plugins/lock/Service.qml"
VIEW="$ROOT/shell/plugins/lock/LockView.qml"
MANIFEST="$ROOT/shell/plugins/lock/manifest.json"

# The wizard must install the maintained Howdy build. ArchWiki marks the plain
# howdy package as outdated, and it does not ship the compiled PAM module.
if ! grep -q "omarchy-pkg-add howdy-git" "$SETUP"; then
  fail "setup installs howdy-git from the AUR"
fi
pass "setup installs howdy-git from the AUR"

if grep -qE "omarchy-pkg-add howdy( |$)" "$SETUP"; then
  fail "setup must not install the outdated plain howdy package"
fi
pass "setup does not install the outdated plain howdy package"

# The PAM context may only reference the compiled module howdy-git actually
# ships at /lib/security/pam_howdy.so — never a module nothing installs.
if grep -rq "pam_howdy_face_only" "$ROOT/bin" "$ROOT/shell"; then
  fail "no reference to the nonexistent pam_howdy_face_only module may remain"
fi
pass "no reference to the nonexistent pam_howdy_face_only module may remain"

if ! grep -qE "auth\s+sufficient\s+/lib/security/pam_howdy\.so" "$SETUP"; then
  fail "setup writes the documented pam_howdy.so sufficient line"
fi
pass "setup writes the documented pam_howdy.so sufficient line"

if ! grep -q "pam_howdy.so is missing" "$SETUP"; then
  fail "setup refuses to enable face PAM when the module is absent"
fi
pass "setup refuses to enable face PAM when the module is absent"

# Howdy's config lives under /lib/security/howdy on Arch, not /etc/howdy.
if ! grep -q 'HOWDY_DIR="/lib/security/howdy"' "$SETUP" || ! grep -q 'HOWDY_DIR="/lib/security/howdy"' "$REMOVE"; then
  fail "setup and remove target the real Howdy config directory"
fi
pass "setup and remove target the real Howdy config directory"

if ! grep -q '"$HOWDY_DIR/config.ini"' "$SETUP"; then
  fail "setup tunes the Howdy config under that directory"
fi
pass "setup tunes the Howdy config under that directory"

if grep -q '"/etc/howdy' "$SETUP" "$REMOVE"; then
  fail "the nonexistent /etc/howdy config root must not be referenced"
fi
pass "the nonexistent /etc/howdy config root must not be referenced"

# Some Howdy builds write config and models to /usr/local/etc/howdy while the
# PAM module only reads /lib/security/howdy — the wizard must normalize that
# after enrollment or authentication silently never works.
if ! grep -q "normalize_howdy_paths" "$SETUP"; then
  fail "setup normalizes Howdy config/model paths after enrollment"
fi
pass "setup normalizes Howdy config/model paths after enrollment"

# Stored face snapshots are a documented spoofing hole; never capture them.
if ! grep -q "capture_failed = false" "$SETUP" || ! grep -q "capture_successful = false" "$SETUP"; then
  fail "setup disables Howdy face snapshots"
fi
pass "setup disables Howdy face snapshots"

if ! grep -q "dark_threshold = 90" "$SETUP"; then
  fail "setup applies the IR-friendly dark_threshold exactly once"
fi
pass "setup applies the IR-friendly dark_threshold exactly once"

if grep -q "dark_threshold = 60" "$SETUP"; then
  fail "no contradictory second dark_threshold rewrite may remain"
fi
pass "no contradictory second dark_threshold rewrite may remain"

# Removal tears everything down: PAM context, packages, the IR emitter unit,
# and the enrolled biometric models.
if ! grep -q "omarchy-pkg-drop howdy-git" "$REMOVE"; then
  fail "remove drops the howdy-git package"
fi
pass "remove drops the howdy-git package"

if ! grep -q 'rm -rf "$HOWDY_DIR/models"' "$REMOVE"; then
  fail "remove deletes the enrolled face models"
fi
pass "remove deletes the enrolled face models"

if ! grep -q "/usr/local/etc/howdy/models" "$REMOVE"; then
  fail "remove deletes models left under /usr/local/etc/howdy"
fi
pass "remove deletes models left under /usr/local/etc/howdy"

if ! grep -q "disable --now linux-enable-ir-emitter" "$REMOVE"; then
  fail "remove disables the IR emitter unit"
fi
pass "remove disables the IR emitter unit"

if ! grep -q "omarchy-lock-howdy" "$REMOVE"; then
  fail "remove tears down the face PAM context"
fi
pass "remove tears down the face PAM context"

# The lock service keeps the face flow bounded: attempts are rate-limited so
# motion wake cannot turn every mouse movement into a camera-on PAM attempt.
if ! grep -q "faceCooldownTimer" "$SERVICE"; then
  fail "lock service rate-limits face attempts with a cooldown"
fi
pass "lock service rate-limits face attempts with a cooldown"

if ! sed -n '/function startFace/,/^  }/p' "$SERVICE" | grep -q "faceCooldownTimer.running"; then
  fail "startFace honors the attempt cooldown"
fi
pass "startFace honors the attempt cooldown"

if ! grep -q "running: root.lockRequested && facePamConfigured" "$SERVICE"; then
  fail "resume detection only runs when face auth is configured"
fi
pass "resume detection only runs when face auth is configured"

if ! grep -q 'config: "omarchy-lock-howdy"' "$SERVICE"; then
  fail "lock service declares the omarchy-lock-howdy PAM context"
fi
pass "lock service declares the omarchy-lock-howdy PAM context"

# The view keeps exactly one hover area (the existing one, extended with
# motion wake) so an added overlay cannot steal hover or cursor styling.
mouse_areas=$(grep -c "MouseArea {" "$VIEW")
if (( mouse_areas != 1 )); then
  fail "lock view keeps a single hover area (found $mouse_areas)"
fi
pass "lock view keeps a single hover area"

if grep -q "acceptedButtons: Qt.NoButton" "$VIEW"; then
  fail "no click-swallowing overlay MouseArea may remain"
fi
pass "no click-swallowing overlay MouseArea may remain"

if ! grep -q "onPositionChanged: root.wakeRequested()" "$VIEW"; then
  fail "lock view wakes on mouse motion"
fi
pass "lock view wakes on mouse motion"

# Indicator spacing is measured from the glyphs, not hardcoded.
if ! grep -q "fingerprintIcon.implicitWidth" "$VIEW" || ! grep -q "faceIcon.implicitWidth" "$VIEW"; then
  fail "indicator reserve is measured from the rendered glyphs"
fi
pass "indicator reserve is measured from the rendered glyphs"

if ! grep -q "faceIndicator" "$VIEW"; then
  fail "lock view contains the face indicator"
fi
pass "lock view contains the face indicator"

if ! grep -q "separate password, fingerprint, and face PAM flows" "$MANIFEST"; then
  fail "lock manifest documents the face PAM flow"
fi
pass "lock manifest documents the face PAM flow"

[[ -x $ROOT/bin/omarchy-hw-face ]] || fail "omarchy-hw-face is executable"
[[ -x $SETUP ]] || fail "omarchy-setup-security-face is executable"
[[ -x $REMOVE ]] || fail "omarchy-remove-security-face is executable"
pass "face authentication tools are executable"
