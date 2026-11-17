# Unwoke SecureBlue. Not affiliated with secureblue.
# SPDX-License-Identifier: LicenseRef-Unwoke-SA-1.0. Copyright (c) 2026 SeRgi270710267.
# UNWOKE-SHIPPED-FIRST
if not test -f /etc/unwoke/allow-toolbox
    if test -d /usr/share/unwoke/blocked-bin
        set -gx PATH /usr/share/unwoke/blocked-bin $PATH
    end
end
