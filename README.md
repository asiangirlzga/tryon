# TryOn 3D Photo Avatar

Godot 4.5+ project.

## Changes
- Replaced the primitive procedural mannequin with a transparent, full-body image-based avatar in the 3D scene.
- The avatar rotates, zooms and scales with the 3D figure.
- Kept bra/panty image loading, background removal, garment size and position controls, auto-turn and front view.
- Avatar artwork: `assets/avatar_3d.png`.

## Limitation
This is a front-facing image-based 3D display, not a fully rigged 3D human mesh. It does not have independently modelled side/back anatomy or cloth simulation. Bust/waist/hips controls adjust garment fit, not the image's anatomy.

## Run
Open `project.godot` in Godot 4.5 or newer and run the project.
