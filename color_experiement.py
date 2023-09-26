import random

GOLDEN_RATIO_CONJUGATE = 0.618033988749895


def hsv_to_rgb(h, s, v):
    h_i = int(h * 6)
    f = h * 6 - h_i
    p = v * (1 - s)
    q = v * (1 - f * s)
    t = v * (1 - (1 - f) * s)
    r = 0
    g = 0
    b = 0
    if h_i == 0:
        r, g, b = v, t, p
    if h_i == 1:
        r, g, b = q, v, p
    if h_i == 2:
        r, g, b = p, v, t
    if h_i == 3:
        r, g, b = p, q, v
    if h_i == 4:
        r, g, b = t, p, v
    if h_i == 5:
        r, g, b = v, p, q
    return f"#{int(r * 256):02x}{int(g * 256):02x}{int(b * 256):02x}".upper()


h = 0
for _ in range(20):
    h = (h + GOLDEN_RATIO_CONJUGATE) % 1
    print(hsv_to_rgb(h, 0.9, 0.97))
