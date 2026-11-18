int add(int, int);

int main(int argc, char **) {
    (void)argc;
    return add(1, 2) == 3 ? 0 : 1;
}
