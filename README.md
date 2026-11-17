# TryOn Mannequin

A stylized 3D mannequin (Godot 4.5) with body-shape sliders. Load a bra or panty photo and the
app removes the plain background and wraps the garment around the mannequin.

## Get the APK
GitHub builds it automatically on every push to `main`.

1. Open the **Releases** page of this repo and open the release called **Latest APK**.
2. Download `tryon.apk` on your phone.
3. Open it and allow "Install unknown apps" for your browser when Android asks.

You can also run the build by hand: **Actions > Build Android APK > Run workflow**.

## Tips for cloth photos
- Use product photos on a plain, evenly lit background.
- A white garment on a white background will lose parts. Lower the "Background removal strength" slider or use a darker background.
- Gaps between straps stay filled, because the cutout starts from the photo edges.
