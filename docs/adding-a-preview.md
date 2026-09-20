# Adding a video preview to the README

The README has a **Preview** section with a placeholder image. Replace it with your clip. Pick whichever way suits you.

## A. Upload the video to GitHub (best: an inline player, no file in the repo)

1. Open `README.md` on github.com and click the pencil icon (Edit).
2. **Drag and drop** your `.mp4` or `.mov` into the editor. GitHub uploads it and inserts a link like
   `https://github.com/user-attachments/assets/xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`.
3. Make sure that link is on a **line of its own** (that is what turns it into a player), delete the placeholder
   image line under **Preview**, and commit.

Size limit for uploaded videos on GitHub: about 10 MB on free accounts (100 MB on paid). Keep the clip short
(30 to 60 seconds) and record at 1080p or lower.

## B. A GIF stored in the repo

Save it as `docs/demo.gif` and replace the placeholder line with:

```markdown
![Demo](docs/demo.gif)
```

Convert a screen recording with `ffmpeg -i demo.mp4 -vf "fps=12,scale=960:-1" docs/demo.gif`.
GIFs autoplay everywhere but are larger and lower quality than a video.

## C. A YouTube video (clickable thumbnail)

```markdown
[![Demo](https://img.youtube.com/vi/VIDEO_ID/maxresdefault.jpg)](https://www.youtube.com/watch?v=VIDEO_ID)
```

## What to show

A short run of `bash <(curl -fsSL ...)`, the component menu, and the result (terminal, Neovim, and the Hyprland desktop if
you install it). Blur or crop anything personal before you record.
