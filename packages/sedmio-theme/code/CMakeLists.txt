cmake_minimum_required(VERSION 3.22)
project(sedmio-theme VERSION 0.2.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core Gui Qml)

qt_standard_project_setup(REQUIRES 6.8)

# Чтение темы — общее для QML-модуля и рамок окон.
add_library(sedmio-themedata STATIC common/themedata.cpp common/themedata.h)
set_target_properties(sedmio-themedata PROPERTIES POSITION_INDEPENDENT_CODE ON)
target_include_directories(sedmio-themedata PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/common)
target_link_libraries(sedmio-themedata PUBLIC Qt6::Core Qt6::Gui)
# Тема по умолчанию — внутрь: подкладка под любую тему.
qt_add_resources(sedmio-themedata builtin_theme
    PREFIX /sedmio/theme
    BASE ${CMAKE_CURRENT_SOURCE_DIR}/../themes/sedmio
    FILES ${CMAKE_CURRENT_SOURCE_DIR}/../themes/sedmio/theme.json
)

add_subdirectory(style)
add_subdirectory(decoration)
add_subdirectory(sync)

install(DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}/../themes/ DESTINATION share/sedmio/themes)
