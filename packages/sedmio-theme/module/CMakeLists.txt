cmake_minimum_required(VERSION 3.22)
project(sedmio-theme VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml)

qt_standard_project_setup(REQUIRES 6.8)

# Модуль Sedmio.Style: синглтон Theme для всех наших программ (QML).
# Модуль и есть плагин: один .so в каталоге модуля.
qt_add_qml_module(sedmiostyle
    URI Sedmio.Style
    VERSION 1.0
    PLUGIN_TARGET sedmiostyle
    OUTPUT_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/Sedmio/Style
    SOURCES theme.cpp theme.h
)

# Тема по умолчанию — внутрь модуля: подкладка под любую тему.
qt_add_resources(sedmiostyle "builtin-theme"
    PREFIX /sedmio/theme
    BASE ${CMAKE_CURRENT_SOURCE_DIR}/../themes/sedmio
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/../themes/sedmio/theme.json
)

target_link_libraries(sedmiostyle PRIVATE Qt6::Gui Qt6::Qml)

set(QML_DEST ${QT6_INSTALL_QML}/Sedmio/Style)
install(TARGETS sedmiostyle LIBRARY DESTINATION ${QML_DEST})
install(FILES
    ${CMAKE_CURRENT_BINARY_DIR}/Sedmio/Style/qmldir
    ${CMAKE_CURRENT_BINARY_DIR}/Sedmio/Style/sedmiostyle.qmltypes
    DESTINATION ${QML_DEST}
)
install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../themes/ DESTINATION share/sedmio/themes)
