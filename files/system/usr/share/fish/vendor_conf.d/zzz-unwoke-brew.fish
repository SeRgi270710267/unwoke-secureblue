if not test -f /etc/unwoke/allow-brew
if set -q PATH
    set -l cleaned
    for p in $PATH
        if not string match -q '*linuxbrew*' $p; and not string match -q '*homebrew*' $p
            set -a cleaned $p
        end
    end
    set -gx PATH $cleaned
end
function brew
    echo "Homebrew is off on Unwoke SecureBlue. Enable: ujust set-brew on" >&2
    return 127
end
end
