#include "stdafx.h"
#include "TextEditor.h"
#include "CaptureSession.h"
#include "AppMessages.h"
#include "Shapes.h"
#include "Dpi.h"

namespace {

constexpr int kEditId = 1;

// A multiline EDIT with ES_AUTOVSCROLL reserves a vertical scrollbar's width in
// the width it breaks lines at, whether or not a scrollbar is showing: measured,
// a 32px client put a 23px string on two lines. The label has no such reserve —
// it draws at box.Width - 2*PadX — so the editor has to hand the same width back
// when it decides where lines break, or the control wraps earlier than the box is
// tall enough for and the caret's line falls outside it. Wrapping at the
// narrower width is the safe direction: the box is then a line taller than the
// control needs rather than a line short.
int WrapSlack() {
    static const int px = ::GetSystemMetrics(SM_CXVSCROLL);
    return px;
}

}  // namespace

BEGIN_MESSAGE_MAP(CTextEditBox, CEdit)
    ON_WM_CHAR()
    ON_WM_LBUTTONUP()
END_MESSAGE_MAP()

void CTextEditBox::OnChar(UINT nChar, UINT nRepCnt, UINT nFlags) {
    CTextEditor* ed = static_cast<CTextEditor*>(GetParent());
    if (nChar == VK_ESCAPE) {
        ed->Finish(false);
        return;
    }
    // Enter belongs to the control: a multiline EDIT inserts a newline, which is
    // what the 文字 box needs rather than what a dialog's default button wants.
    // The control reports Ctrl+Enter as a line feed and plain Enter as a carriage
    // return, so the commit is the line feed plus the carriage return with Ctrl
    // held, which leaves plain Enter alone either way.
    const bool ctrl = (GetKeyState(VK_CONTROL) & 0x8000) != 0;
    if (nChar == 10 || (nChar == VK_RETURN && ctrl)) {
        ed->Finish(true);
        return;
    }
    // The common control has no Ctrl+A of its own; re-editing a label means
    // selecting the old string first.
    if (nChar == 1) {
        SetSel(0, -1);
        return;
    }
    CEdit::OnChar(nChar, nRepCnt, nFlags);
}

void CTextEditBox::OnLButtonUp(UINT nFlags, CPoint pt) {
    CEdit::OnLButtonUp(nFlags, pt);
    if (!m_placeAtEnd) return;
    m_placeAtEnd = false;
    // SetSel(-1, -1) selects; the caret at the end of the text is (len, len).
    const int len = GetWindowTextLength();
    SetSel(len, len);
}

BEGIN_MESSAGE_MAP(CTextEditor, CWnd)
    ON_WM_CTLCOLOR()
    ON_WM_ERASEBKGND()
    ON_EN_KILLFOCUS(kEditId, &CTextEditor::OnEnKillFocus)
    ON_EN_CHANGE(kEditId, &CTextEditor::OnEnChange)
END_MESSAGE_MAP()

BOOL CTextEditor::Create(CWnd* parent, CaptureSession* session,
                         annot::ShapeText* label, COLORREF back) {
    m_session = session;
    m_label = label;
    m_fontPx = (int)label->FontPx();
    m_ink = label->Ink();
    m_backColor = back;

    const CString text = label->Text();
    const Gdiplus::RectF box = label->Box();
    // The window stops short of the box edge by the same padding the ink is inset
    // by, because that is how far the eight square markers reach inward: a window
    // that covered them would clip the overlay's paint there and each marker would
    // read as an L instead of a square. The control inside is placed back out to
    // the box's own top edge, so the ink still lands exactly where the committed
    // label puts it.
    const int padX = (int)label->PadX();
    const CRect host((int)box.X + padX, (int)box.Y + padX,
                     (int)(box.X + box.Width) - padX,
                     (int)(box.Y + box.Height) - padX);

    LPCTSTR cls = AfxRegisterWndClass(0, ::LoadCursor(nullptr, IDC_IBEAM));
    if (!cls) return FALSE;
    if (!CreateEx(0, cls, L"WinShotTextEditor", WS_CHILD | WS_VISIBLE, host, parent, 0))
        return FALSE;

    m_back.CreateSolidBrush(m_backColor);

    LOGFONT lf{};
    lf.lfHeight = -m_fontPx;
    lf.lfWeight = FW_NORMAL;
    lf.lfCharSet = DEFAULT_CHARSET;
    wcscpy_s(lf.lfFaceName, annot::kTextFace);
    m_font.CreateFontIndirect(&lf);

    // Multiline because the box stops at the 选区's right edge and the text has
    // to wrap into more lines rather than run past it. ES_AUTOHSCROLL is out for
    // the same reason: it would scroll the text sideways inside the box instead.
    // ES_AUTOVSCROLL has to stay in: without it the control cannot bring the
    // caret's line into view, and it answers a character that would land past the
    // last visible line by refusing it outright — the box then never learns the
    // text grew and stops following it. The scrollbar width it reserves in the
    // control's wrap width is what WrapSlack() gives back.
    // Screen-wise this is the same rectangle as before: the host moved in by padX
    // on every side, so the control moves back out by padX at the top and spans
    // the host's whole width. Its own height is the box's, which is what the
    // control needs to lay out and scroll its lines by.
    if (!m_edit.CreateEx(0, L"EDIT", text,
                         WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL |
                             ES_WANTRETURN,
                         CRect(0, -padX, std::max(host.Width(), 1),
                               host.Height() + 2 * padX),
                         this, kEditId))
        return FALSE;

    m_edit.SetFont(&m_font, TRUE);
    // Caret at the end, and armed again against the second press of the double
    // click that opened this edit, which the control is about to answer.
    m_edit.SetSel(text.GetLength(), text.GetLength());
    m_edit.PlaceCaretAtEnd();
    m_edit.SetFocus();
    int s = 0, e = 0;
    m_edit.GetSel(s, e);
    m_lastGood = text;
    m_lastSelStart = s;
    m_lastSelEnd = e;

    RebuildBackdrop();
    return TRUE;
}

CTextEditor::~CTextEditor() {
    // The brush holds its own copy of the tile, but keeping the handle costs one
    // box-sized DIB and means the copy question never comes up.
    if (m_backBmp) ::DeleteObject(m_backBmp);
}

CString CTextEditor::Text() const {
    CString t;
    if (m_edit.GetSafeHwnd()) m_edit.GetWindowText(t);
    return t;
}

void CTextEditor::Finish(bool commit) {
    if (m_finishing) return;
    m_finishing = true;
    // The caret would otherwise sit on the frozen image after the box goes.
    if (m_edit.GetSafeHwnd()) ::HideCaret(m_edit.GetSafeHwnd());
    ::PostMessage(GetParent()->GetSafeHwnd(), WM_APP_EDITDONE, commit ? 1 : 0, 0);
}

// The 选区, in the parent's client space — the same space this window lives in.
// The frame is what the text must stay inside, not the screen.
CRect CTextEditor::Limit() const {
    CRect pcl;
    if (CWnd* parent = GetParent()) parent->GetClientRect(&pcl);
    if (!m_session) return pcl;
    CRect sel(m_session->Sel().Rect());
    sel.IntersectRect(&sel, &pcl);
    return sel.IsRectEmpty() ? pcl : sel;
}

Gdiplus::REAL CTextEditor::NeededHeight(const CString& text,
                                        Gdiplus::REAL width) const {
    const int lines =
        (int)annot::WrapLines(text, m_label->FontPx(),
                              std::max(width - 2.0f * m_label->PadX() -
                                             (Gdiplus::REAL)WrapSlack(),
                                         1.0f))
            .size();
    return m_label->FontPx() + m_label->PadY() +
           (lines - 1) * m_label->LineHeight();
}

Gdiplus::RectF CTextEditor::BoxFor(const CString& text) const {
    const Gdiplus::RectF now = m_label->Box();
    const CRect lim = Limit();

    Gdiplus::RectF want = now;
    // The width grows only while the text has no width of its own. A label whose
    // handle has been dragged carries the width the user gave it, and re-opening
    // it must re-wrap at that width rather than stretch back to one line.
    if (!m_label->UserSized()) {
        // Wide enough that the control keeps the whole line on one line, which
        // means room for the scrollbar width it reserves on top of the ink and
        // the padding. NeededHeight subtracts the same amount, so the two agree.
        const Gdiplus::REAL oneLine =
            annot::MeasureTextWidth(text, m_label->FontPx()) +
            2.0f * m_label->PadX() + (Gdiplus::REAL)WrapSlack();
        want.Width = std::max(want.Width,
                              std::min(oneLine, (Gdiplus::REAL)lim.right - now.X));
    }
    want.Height = std::max(want.Height, NeededHeight(text, want.Width));
    want.Height = std::min(want.Height, (Gdiplus::REAL)lim.bottom - now.Y);
    return want;
}

bool CTextEditor::FitsText(const CString& text) const {
    // BoxFor caps the height at the 选区's bottom edge, so the question is whether
    // the text needed more than that: the box cannot scroll, so a change that
    // needs another line the frame has no room for is refused outright.
    const Gdiplus::RectF box = BoxFor(text);
    return box.Y + NeededHeight(text, box.Width) <= (Gdiplus::REAL)Limit().bottom;
}

void CTextEditor::SyncToBox() {
    if (!GetSafeHwnd() || !m_label) return;

    const int padX = (int)m_label->PadX();
    const Gdiplus::RectF box = m_label->Box();
    CRect now((int)box.X + padX, (int)box.Y + padX,
              (int)(box.X + box.Width) - padX, (int)(box.Y + box.Height) - padX);

    CRect was;
    GetWindowRect(&was);
    if (CWnd* parent = GetParent()) parent->ScreenToClient(was);

    if (now != was) {
        MoveWindow(now);
        // The control keeps the screen rectangle it had when this window was the
        // box itself: back out to the box's top edge and across its whole width,
        // so the caret starts where the committed label puts its ink and the text
        // wraps at the width it wraps at, and so the lines the control lays out
        // are the lines the label will draw.
        m_edit.MoveWindow(0, -padX, std::max(now.Width(), 1),
                          now.Height() + 2 * padX);
        RebuildBackdrop();
    }

    // The overlay strokes the red frame 2px outside the box and draws the markers
    // straddling its edge, so it has to repaint the band we leave and the band we
    // take — measured from the box, which is padX further out on every side.
    CRect dirty = now;
    dirty.InflateRect(padX + 3, padX + 3);
    CRect gone = was;
    gone.InflateRect(padX + 3, padX + 3);
    dirty.UnionRect(dirty, gone);
    if (CWnd* parent = GetParent()) parent->InvalidateRect(&dirty, FALSE);
}

void CTextEditor::SetInk(Gdiplus::Color ink) {
    m_ink = ink;
    // OnCtlColor runs again before the control draws its next line and hands back
    // the still as the background, so invalidating erases the old glyphs into the
    // frozen screen and repaints them in the new colour. Nothing else has to move:
    // the box is the size the font needs already.
    if (m_edit.GetSafeHwnd()) m_edit.Invalidate();
}

void CTextEditor::ApplyFontSize(int designPx) {
    if (!m_label || !m_edit.GetSafeHwnd()) return;

    m_label->SetFontSize(designPx);
    m_fontPx = (int)m_label->FontPx();

    // The label re-fit its own height, but it does not know where the 选区 ends.
    // A bigger font can ask for more room below than the frame has left, and the
    // box cannot scroll: it stops at the bottom edge and the lines that no longer
    // fit drop off, which is what happens to a character typed past the last line.
    Gdiplus::RectF box = m_label->Box();
    box.Height = std::min(box.Height, (Gdiplus::REAL)Limit().bottom - box.Y);
    m_label->AdoptBox(box);

    LOGFONT lf{};
    lf.lfHeight = -m_fontPx;
    lf.lfWeight = FW_NORMAL;
    lf.lfCharSet = DEFAULT_CHARSET;
    wcscpy_s(lf.lfFaceName, annot::kTextFace);
    m_font.DeleteObject();
    if (!m_font.CreateFontIndirect(&lf)) return;
    // TRUE so the control redraws with it at once; SyncToBox then moves the window
    // onto the box the new size needs and re-samples the pixels behind it.
    m_edit.SetFont(&m_font, TRUE);
    SyncToBox();
}

void CTextEditor::RebuildBackdrop() {
    // Sampled over the control's own rectangle, not this window's: the tile is
    // applied with its origin at the control's client (0,0), so sampling it
    // anywhere else leaves the frozen screen under the caret offset by the gap.
    CRect cl;
    if (!m_edit.GetSafeHwnd()) return;
    m_edit.GetClientRect(&cl);
    if (cl.IsRectEmpty() || !m_session || !m_session->Overlay().GetSafeHwnd())
        return;

    CPoint src = cl.TopLeft();
    ::ClientToScreen(m_edit.GetSafeHwnd(), &src);
    if (CWnd* parent = GetParent()) parent->ScreenToClient(&src);
    const CRect srcRect(src, src + cl.Size());

    BITMAPINFO bi{};
    bi.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
    bi.bmiHeader.biWidth = cl.Width();
    bi.bmiHeader.biHeight = -cl.Height();  // top-down, like the base it copies
    bi.bmiHeader.biPlanes = 1;
    bi.bmiHeader.biBitCount = 32;
    bi.bmiHeader.biCompression = BI_RGB;
    void* bits = nullptr;
    HBITMAP dib = ::CreateDIBSection(nullptr, &bi, DIB_RGB_COLORS, &bits, nullptr, 0);
    if (!dib) return;

    CDC mem;
    if (!mem.CreateCompatibleDC(nullptr)) {
        ::DeleteObject(dib);
        return;
    }
    HDC md = mem.GetSafeHdc();
    HGDIOBJ old = ::SelectObject(md, dib);
    m_session->Overlay().BltBase(&mem, srcRect, CPoint(0, 0));
    // A pattern brush may not use a bitmap that is still selected somewhere.
    ::SelectObject(md, old);

    HBRUSH pat = ::CreatePatternBrush(dib);
    if (!pat) {
        ::DeleteObject(dib);
        return;
    }
    m_pattern.DeleteObject();
    m_pattern.Attach(pat);
    if (m_backBmp) ::DeleteObject(m_backBmp);
    m_backBmp = dib;
}

HBRUSH CTextEditor::OnCtlColor(CDC* dc, CWnd* wnd, UINT nCtlColor) {
    // MFC hands the handler a CTLCOLOR_* code, not the WM_CTLCOLOR* message it
    // came from — comparing against WM_CTLCOLOREDIT silently never matches.
    if (wnd == &m_edit && nCtlColor == CTLCOLOR_EDIT) {
        dc->SetTextColor(RGB(m_ink.GetR(), m_ink.GetG(), m_ink.GetB()));
        // The box reads as transparent while it is being typed into, as it does
        // once the edit commits: the tile the caret sits on is the frozen screen,
        // so the glyphs must not carry an opaque band of their own. The pattern
        // brush is aligned to the client origin, which is where it was sampled,
        // so erasing any part of it puts the right pixels back.
        dc->SetBkMode(TRANSPARENT);
        if (HBRUSH h = (HBRUSH)m_pattern.GetSafeHandle()) {
            ::SetBrushOrgEx(dc->GetSafeHdc(), 0, 0, nullptr);
            return h;
        }
        dc->SetBkColor(m_backColor);
        return (HBRUSH)m_back.GetSafeHandle();
    }
    return CWnd::OnCtlColor(dc, wnd, nCtlColor);
}

BOOL CTextEditor::OnEraseBkgnd(CDC* dc) {
    CRect cl;
    GetClientRect(&cl);
    if (m_session && m_session->Overlay().GetSafeHwnd() && !cl.IsRectEmpty()) {
        CPoint src = cl.TopLeft();
        ::ClientToScreen(GetSafeHwnd(), &src);
        if (CWnd* parent = GetParent()) parent->ScreenToClient(&src);
        m_session->Overlay().BltBase(dc, CRect(src, src + cl.Size()), cl.TopLeft());
    }
    return TRUE;
}

void CTextEditor::OnEnChange() {
    if (m_restoring) return;

    if (!FitsText(Text())) {
        // Not something to fix by cutting the tail off: a paste or an IME string
        // can be longer than the frame has room for, and a character typed in the
        // middle would otherwise cost everything after it. Put the box back
        // exactly as it was, text and caret both.
        m_restoring = true;
        m_edit.SetWindowText(m_lastGood);
        m_edit.SetSel(m_lastSelStart, m_lastSelEnd);
        m_restoring = false;
    } else {
        m_lastGood = Text();
        int s = 0, e = 0;
        m_edit.GetSel(s, e);
        m_lastSelStart = s;
        m_lastSelEnd = e;
        // The label carries the box the edit is typing into, so the frame the
        // overlay strokes and the box the label commits are one rect.
        m_label->AdoptBox(BoxFor(Text()));
    }
    SyncToBox();
}

void CTextEditor::OnEnKillFocus() {
    if (m_finishing) return;

    // An IME candidate window taking focus is not the user leaving the box —
    // committing then would drop half a composed word.
    const HWND eh = m_edit.GetSafeHwnd();
    if (HIMC imc = ::ImmGetContext(eh)) {
        const DWORD len = ::ImmGetCompositionStringW(imc, GCS_COMPSTR, nullptr, 0);
        ::ImmReleaseContext(eh, imc);
        if (len > 0) return;
    }
    Finish(true);
}
