#!/bin/sh
# Выгружает модули kded, чью работу делает оболочка:
#   networkmanagement — агент паролей Wi‑Fi из plasma-nm (спорил бы с нашим);
#   donationmessage   — просьба KDE о пожертвованиях.
# При входе kded грузит модули в два этапа и на втором загружает их снова,
# даже если их уже выгрузили, — поэтому скрипт первые две минуты сеанса
# следит за списком и выгружает их при каждом появлении.
# В настройки kded ничего не пишется: без оболочки (use-plasmashell)
# модули снова работают как в обычной Plasma.
modules="$*"
[ -n "$modules" ] || modules="networkmanagement donationmessage"

for _ in $(seq 60); do
    loaded=$(busctl --user call org.kde.kded6 /kded org.kde.kded6 loadedModules 2>/dev/null)
    for m in $modules; do
        case "$loaded" in
            *"\"$m\""*) busctl --user call org.kde.kded6 /kded org.kde.kded6 unloadModule s "$m" >/dev/null ;;
        esac
    done
    sleep 2
done
