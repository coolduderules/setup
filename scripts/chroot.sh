#!/usr/bin/bash
# shellcheck source=scripts/config.conf
source "$(dirname "${BASH_SOURCE[0]}")/config.conf"
rsync -axHAWXSR