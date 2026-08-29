if not test -f /etc/unwoke/allow-toolbox
    if test -d /usr/share/unwoke/blocked-bin
        set -gx PATH /usr/share/unwoke/blocked-bin $PATH
    end
end
