# Builds res\winshot.ico, the one icon that feeds both the exe's file icon (through
# winshot.rc) and the tray (through LoadImage), so the two cannot drift apart.
#
# The art is the crop-mark drawing in res\, kept exactly as drawn with its stroke
# recoloured to the product's own selection blue, annot::kFrame = 0xFF1E9FD4 =
# (30,159,212). Measured before this was chosen: the source stroke is (51,51,51),
# which against the real tray strip (38,32,38) is a 1.24:1 contrast ratio -- invisible
# at 16px -- where the blue is 5.2:1. The recolour only applies where the source pixel
# is achromatic, so replacing the drawing with a genuinely coloured one later changes
# the icon rather than flattening it to blue by accident.
#
# There is no ImageMagick on this box (the convert on PATH is the FAT-to-NTFS disk
# tool) and .NET's Icon.Save writes one size, so the .ico is written by hand: ICONDIR,
# one ICONDIRENTRY per size, and for each a 32bpp BGRA DIB whose biHeight is twice the
# width -- the second half being the 1bpp AND mask, all zero, because the alpha channel
# is what carries the shape.
#
# The source is globbed rather than named: a .ps1 saved without a BOM is read as ANSI
# by PowerShell 5.1, and the file's name is not ASCII.
Add-Type -AssemblyName System.Drawing

# Named $file rather than $src: PowerShell variable names are case-insensitive, and
# $src below holds the pixel buffer, so the two would be one variable and the second
# assignment would silently empty the first.
$file = @(Get-ChildItem -LiteralPath 'D:\Project\winshot\res' -Filter '*.png')
if ($file.Count -ne 1) {
    "FAIL: res\ has $($file.Count) png files, want exactly the one drawing"
    exit 1
}
$DST = 'D:\Project\winshot\res\winshot.ico'
# annot::kFrame, as bytes in the order a BGRA pixel wants them.
$BLUE = @(212, 159, 30)
# Explorer asks for 16 and 32, the taskbar's own list for 24 and 48, and 256 covers a
# monitor at a different scale or a copy onto a desktop where the icon is drawn large.
$SIZES = @(16, 24, 32, 48, 64, 128, 256)

# LockBits into a plain byte[]: BGRA in memory for Format32bppArgb, top-down, with
# rows padded to 4 bytes.
function Get-Bgra([System.Drawing.Bitmap]$bmp) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $d = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                       [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $d.Stride
    $buf = New-Object byte[] ($stride * $bmp.Height)
    [void][System.Runtime.InteropServices.Marshal]::Copy($d.Scan0, $buf, 0, $buf.Length)
    $bmp.UnlockBits($d)
    return @{ buf = $buf; stride = $stride; w = $bmp.Width; h = $bmp.Height }
}
function New-BgraBitmap([int]$w, [int]$h) {
    return New-Object System.Drawing.Bitmap $w, $h, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
}
function Set-Bgra([System.Drawing.Bitmap]$bmp, [byte[]]$buf, [int]$stride) {
    $rect = New-Object System.Drawing.Rectangle 0, 0, $bmp.Width, $bmp.Height
    $d = $bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite,
                       [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    [void][System.Runtime.InteropServices.Marshal]::Copy($buf, 0, $d.Scan0, $buf.Length)
    $bmp.UnlockBits($d)
}

# --- read the drawing and recolour the stroke ------------------------------------
$raw = New-Object System.Drawing.Bitmap ([string]$file[0].FullName)
# CopyInto a 32bpp bitmap first: the png could be 8bpp indexed or 24bpp without
# alpha, and the tint and the resample both assume BGRA.
$flat = New-BgraBitmap $raw.Width $raw.Height
$g = [System.Drawing.Graphics]::FromImage($flat)
$g.DrawImage($raw, 0, 0, $raw.Width, $raw.Height)
$g.Dispose(); $raw.Dispose()

$src = Get-Bgra $flat
$tinted = 0
for ($i = 0; $i -lt $src.buf.Length; $i += 4) {
    if ($src.buf[$i + 3] -eq 0) { continue }
    $b = [int]$src.buf[$i]; $gg = [int]$src.buf[$i + 1]; $r = [int]$src.buf[$i + 2]
    $mx = [Math]::Max($r, [Math]::Max($gg, $b)); $mn = [Math]::Min($r, [Math]::Min($gg, $b))
    if (($mx - $mn) -lt 24) {
        $src.buf[$i] = $BLUE[0]; $src.buf[$i + 1] = $BLUE[1]; $src.buf[$i + 2] = $BLUE[2]
        $tinted++
    }
}
Set-Bgra $flat $src.buf $src.stride
# The name is left out: it is not ASCII, and this output goes through a pipe that
# renders it as nothing. There is exactly one png in res\, so the size identifies it.
"source png in res\ : $($src.w)x$($src.h), $([int]$file[0].Length) bytes on disk; $tinted px recoloured to the selection blue"
if ($tinted -eq 0) { 'FAIL: nothing in the drawing was achromatic, so the recolour did nothing'; exit 1 }

# --- one image per size, written straight into the file --------------------------
# The AND mask row is 1bpp padded to a DWORD, so 4 bytes per 32 columns.
function Mask-Bytes([int]$size) { return [int]([Math]::Ceiling($size / 32.0) * 4) * $size }
function Dib-Bytes([int]$size) { return 40 + $size * $size * 4 + (Mask-Bytes $size) }

$ms = New-Object System.IO.MemoryStream
function U16([System.IO.MemoryStream]$s, [int]$v) {
    foreach ($x in [System.BitConverter]::GetBytes([uint16]$v)) { $s.WriteByte($x) }
}
function U32([System.IO.MemoryStream]$s, [int]$v) {
    foreach ($x in [System.BitConverter]::GetBytes([uint32]$v)) { $s.WriteByte($x) }
}

$off = 6 + 16 * $SIZES.Count
U16 $ms 0            # idReserved
U16 $ms 1            # idType: icons
U16 $ms $SIZES.Count # idCount
foreach ($s in $SIZES) {
    # Sizes of 256 and over are written as 0 in both width and height bytes; the real
    # size comes from the DIB header.
    $b = $s % 256
    $ms.WriteByte([byte]$b); $ms.WriteByte([byte]$b)
    $ms.WriteByte(0)      # bColorCount: unused for 32bpp
    $ms.WriteByte(0)      # bReserved
    U16 $ms 1             # wPlanes
    U16 $ms 32            # wBitCount
    U32 $ms (Dib-Bytes $s)
    U32 $ms $off
    $off += Dib-Bytes $s
}

foreach ($s in $SIZES) {
    $bmp = New-BgraBitmap $s $s
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    # SourceCopy, so the resample's own alpha lands in the buffer instead of being
    # composited over whatever the new bitmap happened to start out as.
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceCopy
    $g.DrawImage($flat, 0, 0, $s, $s)
    $g.Dispose()
    $d = Get-Bgra $bmp
    # BITMAPINFOHEADER, 40 bytes: biSize, biWidth, biHeight (twice the height, which
    # is how a .ico says the AND mask follows the pixels), biPlanes, biBitCount, and
    # BI_RGB with the six remaining fields left zero.
    U32 $ms 40
    U32 $ms $s
    U32 $ms (2 * $s)
    U16 $ms 1
    U16 $ms 32
    foreach ($k in 0, 1, 2, 3, 4, 5) { U32 $ms 0 }
    # A DIB is bottom-up: the last row of the bitmap is the first row of the file.
    for ($y = $s - 1; $y -ge 0; $y--) {
        $row = $y * $d.stride
        for ($x = 0; $x -lt $s; $x++) {
            $o = $row + $x * 4
            foreach ($k in 0, 1, 2, 3) { $ms.WriteByte($d.buf[$o + $k]) }
        }
    }
    for ($k = 0; $k -lt (Mask-Bytes $s); $k++) { $ms.WriteByte(0) }
    $bmp.Dispose()
    "  $s px image: $((Dib-Bytes $s)) bytes"
}
$flat.Dispose()

[System.IO.File]::WriteAllBytes($DST, $ms.ToArray())
$ms.Dispose()
"wrote $DST : $((Get-Item -LiteralPath $DST).Length) bytes"

# --- read it back -----------------------------------------------------------------
# Hand-written headers have no check other than this one: Explorer shows the default
# icon rather than an error when the directory is wrong, so "the build succeeded" says
# nothing about the icon. Read the entries out again and ask .NET to render one.
$bytes = [System.IO.File]::ReadAllBytes($DST)
$n = [System.BitConverter]::ToUInt16($bytes, 4)
"type $([System.BitConverter]::ToUInt16($bytes, 2)), $n entries"
if ([System.BitConverter]::ToUInt16($bytes, 0) -ne 0 -or
    [System.BitConverter]::ToUInt16($bytes, 2) -ne 1 -or $n -ne $SIZES.Count) {
    'FAIL: ICONDIR is not a 32bpp icon directory of the expected size'; exit 1
}
$bad = @()
for ($i = 0; $i -lt $n; $i++) {
    $e = 6 + 16 * $i
    $w = [int]$bytes[$e]; if ($w -eq 0) { $w = 256 }
    $h = [int]$bytes[$e + 1]; if ($h -eq 0) { $h = 256 }
    $len = [int][System.BitConverter]::ToUInt32($bytes, $e + 8)
    $o = [int][System.BitConverter]::ToUInt32($bytes, $e + 12)
    $hdr = [int][System.BitConverter]::ToUInt32($bytes, $o)
    $dw = [int][System.BitConverter]::ToUInt32($bytes, $o + 4)
    $dh = [int][System.BitConverter]::ToUInt32($bytes, $o + 8)
    $bpp = [int][System.BitConverter]::ToUInt16($bytes, $o + 14)
    "  entry $i : ${w}x$h len $len at $o, header $hdr ${dw}x$dh bpp $bpp"
    if ($w -ne $h -or $hdr -ne 40 -or $dw -ne $w -or $dh -ne (2 * $w) -or $bpp -ne 32) {
        $bad += "entry $i is not a ${w}x$h 32bpp DIB with a doubled height"
    }
    if ($len -ne (Dib-Bytes $w)) {
        $bad += "entry $i claims $len bytes, want $(Dib-Bytes $w)"
    }
    if ($o + $len -gt $bytes.Length) {
        $bad += "entry $i runs to $($o + $len) but the file is only $($bytes.Length) bytes"
    }
}
if ($bad.Count) { $bad | ForEach-Object { "FAIL: $_" }; exit 1 }
# The last independent check: .NET's own icon reader, which is close enough to
# Explorer's to catch a header that parses but is not what a shell expects. The
# Icon(Stream) constructor walks the directory and picks a size; the Icon(Bitmap, w, h)
# overload would only resample a bitmap and prove nothing about the file.
$ms2 = [System.IO.MemoryStream]::new($bytes)
$ico = New-Object System.Drawing.Icon $ms2
"System.Drawing's icon reader picked $($ico.Width)x$($ico.Height)"
$ico.Dispose(); $ms2.Dispose()
'PASS'
