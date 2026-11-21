cmake_minimum_required(VERSION 3.22)
project(sedmio-preferences VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Widgets OpenGL Quick QuickControls2)
find_package(KF6CoreAddons 6.10 REQUIRED)
find_package(KF6WindowSystem 6.10 REQUIRED)
find_package(KF6Config 6.10 REQUIRED)
find_package(KF6Service 6.10 REQUIRED)
find_package(KF6Screen 6.3 REQUIRED)
# Окно выбора режима экранов — слой поверх всего (как у kscreen).
find_package(LayerShellQt 6.3 REQUIRED)
# «Звук»: устройства и громкость через PulseAudio API (pipewire-pulse).
find_package(KF6PulseAudioQt 1.5 REQUIRED)
# «Сеть»: сохранённые сети и их настройки — NetworkManager.
find_package(KF6NetworkManagerQt 6.10 REQUIRED)
# Русские названия городов в часовых поясах.
find_package(ICU REQUIRED COMPONENTS i18n uc)
# Названия раскладок клавиатуры.
find_package(PkgConfig REQUIRED)
pkg_check_modules(XKBREGISTRY REQUIRED IMPORTED_TARGET xkbregistry)
# Уровень микрофона — поток записи напрямую через libpulse.
pkg_check_modules(PULSE REQUIRED IMPORTED_TARGET libpulse)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-preferences main.cpp app.cpp app.h)

qt_add_qml_module(sedmio-preferences
    URI Sedmio.Preferences
    VERSION 1.0
    SOURCES
        displays.cpp displays.h
        system.cpp system.h
        wallpapers.cpp wallpapers.h
        themes.cpp themes.h
        keyboard.cpp keyboard.h
        pointers.cpp pointers.h
        defaults.cpp defaults.h
        power.cpp power.h
        displayswitcher.cpp displayswitcher.h
        sound.cpp sound.h
        account.cpp account.h
        nightlight.cpp nightlight.h
        network.cpp network.h
        keyedmodel.cpp keyedmodel.h
        autostart.cpp autostart.h
        updates.cpp updates.h
    QML_FILES
        qml/Main.qml
        qml/SText.qml
        qml/SIcon.qml
        qml/SButton.qml
        qml/SSwitch.qml
        qml/SField.qml
        qml/Choice.qml
        qml/Card.qml
        qml/Setting.qml
        qml/Page.qml
        qml/DisplayPage.qml
        qml/WallpaperPage.qml
        qml/ThemePage.qml
        qml/DesktopPreview.qml
        qml/KeyboardPage.qml
        qml/MousePage.qml
        qml/DefaultsPage.qml
        qml/PowerPage.qml
        qml/SoundPage.qml
        qml/BluetoothPage.qml
        qml/NetworkPage.qml
        qml/AutostartPage.qml
        qml/AccountPage.qml
        qml/DisplaySwitcher.qml
        qml/SSlider.qml
        qml/DateTimePage.qml
        qml/UpdatesPage.qml
        qml/AboutPage.qml
)

target_link_libraries(sedmio-preferences PRIVATE
    Qt6::DBus
    Qt6::Widgets
    Qt6::OpenGL
    Qt6::Quick
    Qt6::QuickControls2
    KF6::CoreAddons
    KF6::WindowSystem
    KF6::Screen
    KF6::ConfigCore
    KF6::Service
    LayerShellQt::Interface
    KF6::PulseAudioQt
    KF6::NetworkManagerQt
    PkgConfig::PULSE
    crypt  # хэш нового пароля (libxcrypt)
    PkgConfig::XKBREGISTRY
    ICU::i18n
    ICU::uc
)

install(TARGETS sedmio-preferences RUNTIME DESTINATION bin)
install(FILES sedmio-preferences.desktop DESTINATION share/applications)
