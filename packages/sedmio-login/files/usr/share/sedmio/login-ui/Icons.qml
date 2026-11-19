pragma Singleton
import QtQuick

// Значки кнопок. Breeze рисует их тёмными — подходят к светлому фону.
QtObject {
    function path(name) { return "file:///usr/share/icons/breeze/actions/22/" + name + ".svg"; }
}
