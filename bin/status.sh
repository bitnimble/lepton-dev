#!/bin/bash
# Host-side: one-shot status of a Lepton context in lepton-runner.
CTX="$1"
docker exec lepton-runner bash -c "
cd /var/lib/containers/lepton/run
echo '--- driver'; tail -4 '$CTX.driver.log' 2>/dev/null
echo '--- launcher'; grep -v 'appmanifest_\|Installation marker' '$CTX.log' 2>/dev/null | tail -6
echo '--- android'
podman exec 'lepton-$CTX' /system/bin/sh -c 'echo boot_completed=\$(getprop sys.boot_completed) zygote=\$(getprop init.svc.zygote) sf=\$(getprop init.svc.surfaceflinger); logcat -d -b crash | grep -E \"Cmdline|Abort message\" | tail -4' 2>/dev/null || echo 'container not running'
"
