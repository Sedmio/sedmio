import QtQuick
import QtQuick.Layouts
import Quickshell
import Sedmio.Style

// Календарь на месяц: неделя с понедельника, сегодня выделено.
// Стрелки листают месяцы, клик по названию — вернуться к сегодня.
ColumnLayout {
    id: root
    spacing: 6

    SystemClock { id: clock; precision: SystemClock.Minutes }
    readonly property date today: clock.date

    // Показываемый месяц
    property int year: today.getFullYear()
    property int month: today.getMonth()

    function reset() {
        year = today.getFullYear();
        month = today.getMonth();
    }

    function shift(delta) {
        const d = new Date(year, month + delta, 1);
        year = d.getFullYear();
        month = d.getMonth();
    }

    readonly property bool isCurrentMonth: year === today.getFullYear() && month === today.getMonth()

    // Первая ячейка сетки — понедельник той недели, где первое число.
    readonly property date gridStart: {
        const first = new Date(year, month, 1);
        const offset = (first.getDay() + 6) % 7;
        return new Date(year, month, 1 - offset);
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 4

        SText {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            text: {
                const name = Qt.locale().standaloneMonthName(root.month, Locale.LongFormat);
                return name.charAt(0).toUpperCase() + name.slice(1) + " " + root.year;
            }
            size: Theme.fontLarge
            weight: 600

            MouseArea {
                anchors.fill: parent
                enabled: !root.isCurrentMonth
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: root.reset()
            }
        }

        Repeater {
            model: [{ icon: "go-previous", delta: -1 }, { icon: "go-next", delta: 1 }]
            Rectangle {
                required property var modelData
                implicitWidth: 30
                implicitHeight: 30
                radius: 10
                color: arrowArea.containsMouse ? Theme.paperDeep : Qt.alpha(Theme.paperDeep, 0)
                SIcon { anchors.centerIn: parent; implicitSize: 16; name: parent.modelData.icon }
                MouseArea {
                    id: arrowArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: root.shift(parent.modelData.delta)
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 7
        rowSpacing: 2
        columnSpacing: 0

        // Дни недели
        Repeater {
            model: ["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"]
            SText {
                required property string modelData
                required property int index
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                horizontalAlignment: Text.AlignHCenter
                text: modelData
                size: Theme.fontSmall
                weight: 550
                color: index >= 5 ? Theme.terracotta : Theme.inkMuted
            }
        }

        Repeater {
            model: 42
            Item {
                id: cell
                required property int index
                readonly property date day: new Date(root.gridStart.getFullYear(), root.gridStart.getMonth(), root.gridStart.getDate() + index)
                readonly property bool inMonth: day.getMonth() === root.month
                readonly property bool isToday: day.getFullYear() === root.today.getFullYear()
                    && day.getMonth() === root.today.getMonth() && day.getDate() === root.today.getDate()

                Layout.fillWidth: true
                Layout.preferredWidth: 1
                implicitHeight: 34

                Rectangle {
                    anchors.centerIn: parent
                    width: 32
                    height: 32
                    radius: 16
                    color: cell.isToday ? Theme.green : Qt.alpha(Theme.green, 0)
                }
                SText {
                    anchors.centerIn: parent
                    text: cell.day.getDate()
                    size: 13
                    weight: cell.isToday ? 650 : 450
                    color: cell.isToday ? Theme.textOnGreen
                         : !cell.inMonth ? Theme.lineStrong
                         : (cell.index % 7 >= 5 ? Theme.terracotta : Theme.ink)
                }
            }
        }
    }
}
