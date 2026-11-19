# Модуль Sedmio.Style: синглтон Theme для всех наших программ (QML).
# Модуль и есть плагин: один .so в каталоге модуля.
qt_add_qml_module(sedmiostyle
    URI Sedmio.Style
    VERSION 1.0
    PLUGIN_TARGET sedmiostyle
    OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/Sedmio/Style
    SOURCES theme.cpp theme.h
)
target_link_libraries(sedmiostyle PRIVATE Qt6::Qml sedmio-themedata)

set(QML_DEST ${QT6_INSTALL_QML}/Sedmio/Style)
install(TARGETS sedmiostyle LIBRARY DESTINATION ${QML_DEST})
install(FILES
    ${CMAKE_BINARY_DIR}/Sedmio/Style/qmldir
    ${CMAKE_BINARY_DIR}/Sedmio/Style/sedmiostyle.qmltypes
    DESTINATION ${QML_DEST}
)
