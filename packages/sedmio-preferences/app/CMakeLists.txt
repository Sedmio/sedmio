cmake_minimum_required(VERSION 3.22)
project(sedmio-preferences VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Widgets OpenGL Quick QuickControls2)
find_package(KF6CoreAddons 6.10 REQUIRED)
find_package(KF6WindowSystem 6.10 REQUIRED)
find_package(KF6Config 6.10 REQUIRED)
find_package(KF6Screen 6.3 REQUIRED)
# Русские названия городов в часовых поясах.
find_package(ICU REQUIRED COMPONENTS i18n uc)
# Названия раскладок клавиатуры.
find_package(PkgConfig REQUIRED)
pkg_check_modules(XKBREGISTRY REQUIRED IMPORTED_TARGET xkbregistry)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-preferences main.cpp app.cpp app.h)

set_source_files_properties(qml/Theme.qml PROPERTIES QT_QML_SINGLETON_TYPE TRUE)

qt_add_qml_module(sedmio-preferences
    URI Sedmio.Preferences
    VERSION 1.0
    SOURCES
        displays.cpp displays.h
        system.cpp system.h
        wallpapers.cpp wallpapers.h
        keyboard.cpp keyboard.h
    QML_FILES
        qml/Main.qml
        qml/Theme.qml
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
        qml/KeyboardPage.qml
        qml/DateTimePage.qml
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
    PkgConfig::XKBREGISTRY
    ICU::i18n
    ICU::uc
)

install(TARGETS sedmio-preferences RUNTIME DESTINATION bin)
install(FILES sedmio-preferences.desktop DESTINATION share/applications)
