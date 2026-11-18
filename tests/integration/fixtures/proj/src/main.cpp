#include "widget.h"

int helperFunction(int a) { return a * 2; }

int main() {
    ui::Widget w;
    w.repaint();
    return helperFunction(1);
}
