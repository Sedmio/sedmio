cmake_minimum_required(VERSION 3.22)
project(sedmio-session VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui Quick)
# Экран выхода — слой поверх всего на каждом мониторе (layer-shell).
find_package(LayerShellQt 6.0 REQUIRED)

qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-session-manager main.cpp manager.cpp manager.h shellwatch.cpp shellwatch.h)

qt_add_qml_module(sedmio-session-manager
    URI Sedmio.Session
    VERSION 1.0
    QML_FILES
        LogoutWindow.qml
        Fallback.qml
        ShellBanner.qml
)

target_link_libraries(sedmio-session-manager PRIVATE
    Qt6::DBus
    Qt6::Quick
    LayerShellQt::Interface
)

set_target_properties(sedmio-session-manager PROPERTIES OUTPUT_NAME session-manager)
install(TARGETS sedmio-session-manager RUNTIME DESTINATION lib/sedmio)

# Заставка при входе (вместо ksplashqml) — отдельная маленькая программа.
qt_add_executable(sedmio-splash splash.cpp)
target_link_libraries(sedmio-splash PRIVATE
    Qt6::DBus
    Qt6::Quick
    LayerShellQt::Interface
)
set_target_properties(sedmio-splash PROPERTIES OUTPUT_NAME splash)
install(TARGETS sedmio-splash RUNTIME DESTINATION lib/sedmio)
