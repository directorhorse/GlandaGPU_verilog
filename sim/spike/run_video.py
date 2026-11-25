#!/usr/bin/env python3
"""Run the demo against a fresh capture path. Optionally watch completed frames via WSLg."""
import argparse
import os
from pathlib import Path
import subprocess
import sys
from tempfile import TemporaryDirectory


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('--build', type=Path, required=True)
    p.add_argument('--spike', default='spike')
    p.add_argument('--window', action='store_true')
    p.add_argument('--auto-close-ms', type=int, help='close after displaying the verified frame')
    args = p.parse_args()
    build = args.build.resolve()
    root = None
    if args.window:
        import tkinter as tk
        try:
            root = tk.Tk()
        except tk.TclError as exc:
            raise SystemExit(f'Cannot open display ({exc}); use make video for headless capture')
        root.title('GlandaGPU — Spike / Verilator VGA')
        label = tk.Label(root, text='Waiting for complete VGA frame...', borderwidth=0)
        label.pack()

    with TemporaryDirectory(prefix='vga-', dir=build) as tmp:
        capture = Path(tmp) / 'frame.ppm'
        cmd = ['timeout', '60s', args.spike, '--isa=rv64i', '-m64',
               f'--extlib={build}/model/libglandagpu.so', '--device=glandagpu', str(build/'video.elf')]
        proc = subprocess.Popen(cmd, env=dict(os.environ, GLANDA_VGA_PPM=str(capture)))
        def publish():
            subprocess.run([sys.executable, str(Path(__file__).with_name('check_video.py')),
                            str(capture), str(Path(tmp)/'frame.png')], check=True)
            capture.replace(build/'vga.ppm')
            (Path(tmp)/'frame.png').replace(build/'vga.png')
            print(f'Verified VGA output: {build}/vga.png', flush=True)

        try:
            if root is None:
                proc.wait()
                if proc.returncode:
                    return proc.returncode
                publish()
                return 0

            previous = None
            result = 1  # closing before completion is not a passing test
            def redraw():
                nonlocal previous, result
                try:
                    status = proc.poll()
                    if capture.exists():
                        stat = capture.stat()
                        key = (stat.st_ino, stat.st_mtime_ns)
                        if key != previous:
                            image = tk.PhotoImage(file=str(capture), format='PPM')
                            label.configure(image=image, text='')
                            label.image = image
                            previous = key
                    if status is None:
                        root.after(16, redraw)
                    elif status == 0:
                        publish()
                        result = 0
                        root.title('GlandaGPU — verified VGA frame (close to exit)')
                        if args.auto_close_ms is not None:
                            root.after(args.auto_close_ms, root.destroy)
                    else:
                        print(f'Spike exited with status {status}', file=sys.stderr)
                        root.destroy()
                except Exception as exc:
                    print(exc, file=sys.stderr)
                    root.destroy()
            root.after(0, redraw)
            root.mainloop()
            return result
        finally:
            if proc.poll() is None:
                proc.terminate()
                proc.wait()


if __name__ == '__main__':
    sys.exit(main())
