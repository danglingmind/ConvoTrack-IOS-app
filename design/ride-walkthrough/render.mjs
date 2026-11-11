// render.mjs — steps index.html frame by frame with Playwright and pipes PNGs into ffmpeg.
//   node render.mjs                      → ride-walkthrough.mp4 (1080x1920, 60 fps, with soundtrack.wav)
//   node render.mjs --contact            → contact.png (one frame per second, 5 across)
// Frame count and contact-sheet length follow window.DURATION. Time is set only through window.renderAt(t), so frame N is always identical.
import { chromium } from 'playwright';
import { spawn } from 'node:child_process';
import { fileURLToPath, pathToFileURL } from 'node:url';
import path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));
const FPS = 60, W = 1080, H = 1920;
const contact = process.argv.includes('--contact');
const fi = process.argv.indexOf('--frame');   // --frame <t> <out.png>: one full-size frame

const browser = await chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto(pathToFileURL(path.join(dir, 'index.html')).href);
await page.evaluate(() => window.ready);
const duration = await page.evaluate(() => window.DURATION);

const frame = async t => { await page.evaluate(t => window.renderAt(t), t); return page.screenshot({ type: 'png' }); };
const run = (args, feed) => new Promise((ok, fail) => {
  const p = spawn('ffmpeg', args, { cwd: dir, stdio: ['pipe', 'inherit', 'inherit'] });
  p.on('close', c => c === 0 ? ok() : fail(new Error('ffmpeg exited ' + c)));
  feed(p.stdin).then(() => p.stdin.end());
});

if (fi > 0) {
  const { writeFileSync } = await import('node:fs');
  writeFileSync(path.resolve(process.argv[fi + 2]), await frame(parseFloat(process.argv[fi + 1])));
} else if (contact) {
  // One frame per second (t = 0.5, 1.5 … mid-second), tiled left to right, top to bottom.
  const times = Array.from({ length: Math.ceil(duration) }, (_, i) => i + 0.5).filter(t => t < duration);
  await run(['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', '1', '-i', '-',
    '-vf', `scale=360:-1,tile=5x${Math.ceil(times.length / 5)}:padding=8:color=0x404040`,
    '-frames:v', '1', 'contact.png'], async s => { for (const t of times) s.write(await frame(t)); });
} else {
  const n = Math.round(duration * FPS);
  await run(['-v', 'error', '-y', '-f', 'image2pipe', '-framerate', String(FPS), '-i', '-', '-i', 'soundtrack.wav',
    '-c:v', 'libx264', '-pix_fmt', 'yuv420p', '-crf', '16', '-preset', 'slow', '-r', String(FPS),
    '-c:a', 'aac', '-b:a', '192k', '-shortest', '-movflags', '+faststart', 'ride-walkthrough.mp4'],
    async s => {
      for (let i = 0; i < n; i++) {
        const png = await frame(i / FPS);
        if (!s.write(png)) await new Promise(r => s.once('drain', r));
        if (i % 120 === 0) process.stdout.write(`frame ${i}/${n}\n`);
      }
    });
}
await browser.close();
