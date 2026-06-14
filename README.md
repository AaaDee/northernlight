# northernlight

A small Rust + [wgpu](https://wgpu.rs/) demo that renders the northern lights
(aurora) as a fullscreen volumetric raymarch in WGSL.

![northernlight demo](demo.png)

## How it works

- `src/main.rs` — sets up the window ([winit](https://github.com/rust-windowing/winit)),
  GPU surface, render pipeline, and a per-frame uniform buffer (resolution +
  time). It draws a single fullscreen triangle each frame.
- `src/aurora.wgsl` — the vertex shader emits the fullscreen triangle; the
  fragment shader does all the work, raymarching the aurora and compositing the
  foreground.

## Build & run

```bash
cargo run --release
```

The demo opens in **borderless fullscreen** on the current monitor and animates
immediately. Press **Escape** (or close the window) to exit.

## Running on another machine

The release build is a single self-contained executable — the target machine
does **not** need Rust, cargo, or the source code. These instructions assume
similar hardware (same OS and CPU architecture).

1. Build the binary:

   ```bash
   cargo build --release
   ```

   The executable is written to `target/release/northernlight`.

2. Copy just that file to the other machine (scp, USB, etc.) and run it:

   ```bash
   ./northernlight
   ```

The target machine still needs:

- The **same OS and CPU architecture** (e.g. a Linux x86-64 build only runs on
  Linux x86-64).
- A **compatible glibc** — the binary dynamically links the system C library, so
  the target's glibc must be the same version or newer than the build machine's.
  Building on the oldest machine you'll deploy to avoids version mismatches.
- Working **GPU drivers** (Vulkan, or the GL fallback) and a graphical session —
  it opens a window and cannot run headless over plain SSH.

