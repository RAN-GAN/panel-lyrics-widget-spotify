import QtQuick
import QtQuick.Controls as QQC2
import org.kde.kirigami as Kirigami

Kirigami.FormLayout {
    id: page

    // Bound automatically to the matching <entry name="..."> in
    // contents/config/main.xml by the "cfg_" naming convention.
    property alias cfg_fontSize: fontSizeSpin.value
    property alias cfg_widgetWidth: widthSpin.value
    property string cfg_textAlignment: "left"

    QQC2.SpinBox {
        id: fontSizeSpin
        Kirigami.FormData.label: "Font size:"
        from: -1
        to: 72
        stepSize: 1
        textFromValue: (value) => value === -1 ? "Default" : (value + " pt")
        valueFromText: (text) => text === "Default" ? -1 : parseInt(text)
    }

    QQC2.SpinBox {
        id: widthSpin
        Kirigami.FormData.label: "Maximum width:"
        from: 60
        to: 1200
        stepSize: 10
        textFromValue: (value) => value + " px"
        valueFromText: (text) => parseInt(text)
    }

    QQC2.ComboBox {
        id: alignmentCombo
        Kirigami.FormData.label: "Text alignment:"
        model: ["left", "center", "right"]
        currentIndex: model.indexOf(page.cfg_textAlignment)
        onActivated: page.cfg_textAlignment = model[currentIndex]
    }
}
