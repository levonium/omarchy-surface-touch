import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "levonium.osk"

  // wvkbd toggles its visibility on SIGRTMIN; start it if it isn't running yet.
  readonly property string toggleCommand: "pkill --signal RTMIN -x wvkbd-deskintl || exec wvkbd-deskintl"

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "\uf11c" // nf-fa-keyboard
    tooltipText: "On-screen keyboard"
    onPressed: function(b) {
      if (root.bar) root.bar.run(root.toggleCommand)
    }
  }
}
