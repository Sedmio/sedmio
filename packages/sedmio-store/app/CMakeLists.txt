cmake_minimum_required(VERSION 3.22)
project(sedmio-store VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
# GLib (libflatpak, appstream) называет поле «signals» — без ключевых слов Qt.
add_compile_definitions(QT_NO_KEYWORDS)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Network Quick QuickControls2)
# Поднять уже открытое окно (токен активации Wayland).
find_package(KF6WindowSystem 6.10 REQUIRED)
# Открыть установленную программу по её .desktop.
find_package(KF6Service 6.10 REQUIRED)
find_package(KF6CoreAddons 6.10 REQUIRED)
# Каталог программ: репозитории Arch и Flathub.
find_package(AppStreamQt 1.0 REQUIRED)
find_package(PkgConfig REQUIRED)
pkg_check_modules(Flatpak REQUIRED IMPORTED_TARGET flatpak)
pkg_check_modules(AppStream REQUIRED IMPORTED_TARGET appstream)
pkg_check_modules(Alpm REQUIRED IMPORTED_TARGET libalpm)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-store main.cpp)

qt_add_qml_module(sedmio-store
    URI Sedmio.Store
    VERSION 1.0
    SOURCES
        catalog.cpp catalog.h
        flatpakops.cpp flatpakops.h
        jobs.cpp jobs.h
        preview.cpp preview.h
        packages.cpp packages.h
        storehost.cpp storehost.h
        textmatch.cpp textmatch.h
        keyedmodel.cpp keyedmodel.h
        aur.cpp aur.h
        aurbuild.cpp aurbuild.h
    QML_FILES
        qml/StoreWindow.qml
        qml/HomePage.qml
        qml/ListPage.qml
        qml/AppPage.qml
        qml/AppTile.qml
        qml/AppIcon.qml
        qml/SourceCard.qml
        qml/UpdatesPage.qml
        qml/AurPage.qml
        qml/AurResults.qml
        qml/AurRow.qml
        qml/AurInstalled.qml
        qml/NavItem.qml
        qml/SText.qml
        qml/SIcon.qml
        qml/SButton.qml
        qml/Card.qml
        qml/SField.qml
)

target_link_libraries(sedmio-store PRIVATE
    Qt6::DBus
    Qt6::Network
    Qt6::Quick
    Qt6::QuickControls2
    KF6::WindowSystem
    KF6::Service
    KF6::CoreAddons
    AppStreamQt
    PkgConfig::Flatpak
    PkgConfig::AppStream
    PkgConfig::Alpm
)

install(TARGETS sedmio-store RUNTIME DESTINATION bin)
install(FILES sedmio-store.desktop DESTINATION share/applications)
