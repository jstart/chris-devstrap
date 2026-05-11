# `headshot.png`

Save your account photo here as **`headshot.png`** (PNG or JPEG; square **512–1024 px** works well).

On macOS, **`scripts/headshot.sh`** (run from `./bootstrap.sh`) will:

1. Copy it to **`~/Downloads/headshot.png`**.
2. Install a stable copy under **`~/Library/Application Support/chris-devstrap/`** and point the **local user** login picture at it (`dscl` **Picture** / **JPEGPhoto** cleanup), which updates **Users & Groups** / login avatar for this Mac account.

Optional: use the same photo in **Apple ID**, **Chrome**, **Messages**, etc. via each service’s own settings — not automated here.
