"""Derive app texture maps from the Cycles bakes (numpy only, deterministic)."""
import numpy as np
from PIL import Image

def normal_from_height(h, strength):
    gy, gx = np.gradient(h)
    nx, ny, nz = -gx * strength, gy * strength, np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    rgb = np.stack([nx / l, ny / l, nz / l], -1) * 0.5 + 0.5
    return Image.fromarray((rgb * 255).round().astype(np.uint8), "RGB")

def periodic_noise(n, cutoff, seed):
    rng = np.random.default_rng(seed)
    f = np.fft.fft2(rng.standard_normal((n, n)))
    ky = np.fft.fftfreq(n)[:, None]; kx = np.fft.fftfreq(n)[None, :]
    k = np.sqrt(kx * kx + ky * ky)
    f *= np.exp(-(k / cutoff) ** 2)
    v = np.real(np.fft.ifft2(f))
    return (v - v.min()) / (v.max() - v.min())

oak = Image.open("bake/oak.png").convert("RGB")
oak.save("bake/PlatformOak.jpg", quality=90)
lum = np.asarray(oak.convert("L"), dtype=np.float32) / 255.0
# grain relief: high-pass of luminance along the grain
from PIL import ImageFilter
blur = np.asarray(oak.convert("L").filter(ImageFilter.GaussianBlur(6)), dtype=np.float32) / 255.0
normal_from_height(lum - blur, 6.0).save("bake/PlatformOakNormal.png")

mat = Image.open("bake/mat.png").convert("RGB")
mat.save("bake/PlatformMat.jpg", quality=90)
peb = periodic_noise(512, 0.08, 7) * 0.7 + periodic_noise(512, 0.25, 8) * 0.3
normal_from_height(peb, 5.0).save("bake/PlatformMatNormal.png")
print("maps ok")
