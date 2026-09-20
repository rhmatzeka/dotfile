# dotfiles

Dotfiles pribadi rhmatzeka yang bisa dipasang orang lain dengan satu perintah.
*Personal dotfiles you can install with a single command (English summary at the bottom).*

```bash
bash <(curl -fsSL https://dotfiles.rahmateka.my.id)
```

Pakai `bash <(...)`, bukan `curl | bash`, supaya terminal tetap terhubung dan menu serta kata sandi `sudo` berfungsi.
Sebelum menjalankan skrip dari internet, **baca dulu isinya**. Ini bisa dilihat dengan
`curl -fsSL https://dotfiles.rahmateka.my.id | less`, dan semua langkah bisa dicoba tanpa mengubah apa pun dengan `--dry-run`.

## Isi

| Komponen | Isinya |
|---|---|
| `base` | Paket dasar (git, fzf, ripgrep, eza, zoxide, ...) dan font JetBrainsMono Nerd |
| `shell` | zsh, Oh My Zsh (autosuggestions, syntax highlighting), prompt starship |
| `tmux` | tmux dengan tema cyan/Dracula |
| `nvim` | Neovim + NvChad, parser tree-sitter (html, css, js, php, ...) dan LSP lewat Mason |
| `terminal` | Konfigurasi Ghostty (tema gelap, tombol ala Vim) |
| `browsers` | Browser terminal: Browsh (Firefox di terminal), elinks, w3m |
| `desktop` | Hyprland + Caelestia shell. **Hanya Debian 13.** Qt 6.11 dibangun dari source (1 sampai 2 jam) |

## Sistem yang didukung

| OS | Status |
|---|---|
| Debian 13 (trixie) | `base`, `shell`, `tmux`, `nvim`, `terminal`, `browsers` **teruji dari nol** di Debian 13 minimal yang bersih. `desktop`: daftar paketnya tervalidasi, build dari source belum dijalankan ulang (beta) |
| Ubuntu / turunan Debian lain | CI GitHub (Ubuntu) lulus: dry-run semua komponen selain `desktop`, serta pemasangan asli `shell`, `tmux`, `terminal` dan uninstall. `nvim` dan `browsers` belum teruji di Ubuntu |
| Arch, Fedora, macOS | **Belum didukung.** Kontribusi sangat diterima (lihat bawah) |

Yang benar-benar dijalankan:

- **Debian 13 bersih** (rootfs minimal, hanya 119 paket): pemasangan `base shell tmux nvim terminal browsers` lewat `apt`
  sampai selesai dengan exit 0. Hasilnya diperiksa: versi semua alat, font Nerd, tmux dan zsh membaca config,
  Neovim dengan 18 parser dan 7 LSP, serta warna sintaks pada file PHP/HTML/JS.
- **HOME kosong** (mesin yang paketnya sudah ada): `--dry-run`, pemasangan saat pengguna sudah punya file sendiri
  (dibackup), pemasangan ulang (tidak mengulang backup), `uninstall` (file asli kembali), dan seluruh alur lewat
  URL mentah GitHub.
- **Debian 13, `desktop`**: 79 paket utama dan 5 paket backports disimulasikan (`apt-get -s`), semuanya dapat
  di-resolve (373 paket total). Yang **belum** dijalankan ulang dari nol adalah build Qt 6.11, quickshell, dan
  Caelestia dari source lewat skrip ini. Versinya dikunci ke kombinasi yang pernah berhasil dibangun dan dijalankan
  manual, tapi anggap `desktop` sebagai **beta**.

## Pemakaian

```bash
./install.sh                    # menu interaktif
./install.sh --all              # semua komponen, termasuk desktop
./install.sh --only shell,nvim  # pilih sendiri
./install.sh --dry-run --all    # lihat apa yang akan terjadi, tanpa mengubah apa pun
./install.sh --yes              # tanpa pertanyaan (jawaban bawaan)
./install.sh --list             # daftar komponen
```

Lewat `curl`, tambahkan opsinya setelah perintah, misalnya
`bash <(curl -fsSL https://dotfiles.rahmateka.my.id) --dry-run --all`.

## Keamanan

- File yang akan diganti **dipindah dulu** ke `~/.dotfiles-backup/<waktu>/`, bukan ditimpa.
- Semua symlink yang dibuat dicatat, sehingga `uninstall` hanya membatalkan yang dibuat installer ini.
- `sudo` hanya dipakai untuk memasang paket dan (pada `desktop`) menulis ke `/opt` dan `/usr/local`.
- Jalankan sebagai pengguna biasa, bukan root.

## Uninstall

```bash
bash <(curl -fsSL https://dotfiles.rahmateka.my.id/uninstall.sh)
```

Symlink dibuang dan file asli dikembalikan. Paket, font, Oh My Zsh, dan hasil build di `/opt` tidak ikut dihapus;
daftarnya ditampilkan di akhir.

## Cara kerja

`install.sh` di root hanya mendeteksi OS, mengambil repo ke `~/.dotfiles`, lalu menjalankan installer platform
(`linux/debian/install.sh`). Konfigurasi ada di `config/` dan dipasang sebagai symlink, jadi mengeditnya di
`~/.dotfiles` langsung berlaku. Fungsi bersama (backup, symlink, dry-run) ada di `lib/common.sh`.

```
install.sh  uninstall.sh        titik masuk (deteksi OS)
lib/common.sh                   fungsi bersama
linux/debian/                   installer Debian: install.sh, uninstall.sh, desktop.sh
config/                         zsh, starship, tmux, nvim, ghostty, elinks, caelestia
bin/                            skrip kecil (web, firefox-for-browsh)
```

## Menambah OS lain

Buat `linux/<nama>/install.sh` dan `uninstall.sh` (contoh: `linux/debian/`), lalu tambahkan cabang OS-nya di
`install.sh`. Pakai fungsi di `lib/common.sh` supaya `--dry-run` dan backup ikut bekerja. Pull request diterima,
tapi mohon jelaskan di deskripsinya OS mana yang benar-benar diuji.

## Menyiapkan domain pendek (untuk pemilik repo)

URL mentah selalu jalan:
`bash <(curl -fsSL https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh)`

Untuk `dotfiles.rahmateka.my.id` lewat Cloudflare:

1. **DNS**: tambah record `AAAA`, nama `dotfiles`, isi `100::`, **Proxied** (awan oranye). Isinya bebas, tidak pernah dituju.
2. **Rules > Redirect Rules > Create rule** (dua aturan):
   - *URI Full* sama dengan `https://dotfiles.rahmateka.my.id/` maka *Static redirect* ke
     `https://raw.githubusercontent.com/rhmatzeka/dotfile/main/install.sh`, status 302.
   - *URI Full* sama dengan `https://dotfiles.rahmateka.my.id/uninstall.sh` maka redirect ke
     `https://raw.githubusercontent.com/rhmatzeka/dotfile/main/uninstall.sh`, status 302.
3. Uji: `curl -fsSL https://dotfiles.rahmateka.my.id | head -3` harus menampilkan `#!/usr/bin/env bash`.

Redirect ke file mentah (teks biasa) dipilih daripada GitHub Pages, karena Cloudflare bisa menyisipkan skrip ke
halaman HTML dan merusak installer.

## Lisensi dan kredit

Kode di repo ini: MIT. Palet warna: [Dracula](https://draculatheme.com) (MIT) dengan aksen cyan.
Yang diunduh saat instalasi dan **tidak** didistribusikan ulang oleh repo ini: Oh My Zsh (MIT), NvChad starter
(Unlicense), Browsh (LGPL-2.1), quickshell dan Caelestia shell/CLI (GPL-3.0, dibangun dari source), serta config
Hyprland dari `caelestia-dots/caelestia` (dikloning dari upstream).

---

### English summary

Personal dotfiles with a one-line installer, in the style of `bash <(curl -fsSL <url>)`.
`install.sh` detects the OS, fetches this repo to `~/.dotfiles`, and runs the platform installer, which offers
components (base, shell, tmux, nvim, terminal, browsers, desktop). Supported: **Debian 13** (all user-level components
installed and verified from scratch in a clean Debian 13 rootfs; the desktop component builds Qt 6.11 from source and is
beta). Ubuntu passes the CI dry run and a partial real run; Arch, Fedora and macOS are not supported yet.
Files it would replace are moved to `~/.dotfiles-backup/`, every link is recorded so `uninstall.sh` restores your
originals, and `--dry-run` shows everything without changing anything. Please read a script before piping it to
a shell.
