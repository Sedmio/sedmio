cmake_minimum_required(VERSION 3.22)
project(sedmio-screenshot VERSION 0.1.0 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 6.8 REQUIRED COMPONENTS Core DBus Gui)
qt_standard_project_setup(REQUIRES 6.8)

qt_add_executable(sedmio-capture capture.cpp)
target_link_libraries(sedmio-capture PRIVATE Qt6::DBus Qt6::Gui)

install(TARGETS sedmio-capture RUNTIME DESTINATION lib/sedmio)
