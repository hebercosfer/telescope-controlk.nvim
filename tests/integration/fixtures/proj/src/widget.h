#pragma once

namespace ui {

enum class Mode { Idle, Busy };

struct Point {
    int x;
    int y;
};

class Widget {
public:
    Widget();
    void repaint();
    int width() const;

private:
    int m_width = 0;
};

} // namespace ui

int helperFunction(int a);
