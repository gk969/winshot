#include "stdafx.h"
#include "TextEditor.h"
#include "CaptureSession.h"
#include "AppMessages.h"
#include "Shapes.h"
#include "Dpi.h"

namespace {

constexpr int kEditId = 1;

}  // namespace

BEGIN_MESSAGE_MAP(CTextEditBox, CEdit)
    ON_WM_CHAR()
END_MESSAGE_MAP()

void CTextEditBox::OnChar(UINT nChar, UINT nRepCnt, UINT nFlags) {
    if (nChar == VK_RETURN) {
        static_cast<CTextEditor*>(GetParent())->Finish(true);
        return;
    }
    if (nChar == VK_ESCAPE) {
        static_cast<CTextEditor*>(GetParent())->Finish(false);
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

BEGIN_MESSAGE_MAP(CTextEditor, CWnd)
    ON_WM_CTLCOLOR()
    ON_WM_ERASEBKGND()
    ON_EN_KILLFOCUS(kEditId, &CTextEditor::OnEnKillFocus)
    ON_EN_CHANGE(kEditId, &CTextEditor::OnEnChange)
END_MESSAGE_MAP()

BOOL CTextEditor::Create(CWnd* parent, CaptureSession* session, CPoint at,
                         const CString& text, int fontPx, Gdiplus::Color ink,
                         COLORREF back, annot::ShapeText* target) {
    m_session = session;
    m_at = at;
    m_fontPx = fontPx;
    m_ink = ink;
    m_target = target;
    m_backColor = back;

    const HWND ph = parent->GetSafeHwnd();
    const CRect box(at.x, at.y, at.x + Dpi::S(ph, annot::kTextMinW),
                    at.y + fontPx + Dpi::S(ph, annot::kTextPadY));

    LPCTSTR cls = AfxRegisterWndClass(0, ::LoadCursor(nullptr, IDC_IBEAM));
    if (!cls) return FALSE;
    if (!CreateEx(0, cls, L"WinShotTextEditor", WS_CHILD | WS_VISIBLE, box, parent, 0))
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
    if (!m_edit.CreateEx(0, L"EDIT", text,
                         WS_CHILD | WS_VISIBLE | ES_MULTILINE | ES_AUTOVSCROLL |
                             ES_WANTRETURN,
                         CRect(0, 0, box.Width(), box.Height()), this, kEditId))
        return FALSE;

    m_edit.SetFont(&m_font, TRUE);
    m_edit.SetSel(-1, -1);
    m_edit.SetFocus();
    int s = 0, e = 0;
    m_edit.GetSel(s, e);
    m_lastGood = text;
    m_lastSelStart = s;
    m_lastSelEnd = e;

    FitToText();
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

CRect CTextEditor::Frame() const {
    CRect r;
    if (!GetSafeHwnd()) return r;
    GetWindowRect(&r);
    if (CWnd* parent = GetParent()) parent->ScreenToClient(r);
    return r;
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

CSize CTextEditor::BoxFor(const CString& text, int maxW) const {
    const HWND hw = GetSafeHwnd();
    const int pad = Dpi::S(hw, annot::kTextPadX);
    const int minW = Dpi::S(hw, annot::kTextMinW);
    const Gdiplus::REAL fontPx = (Gdiplus::REAL)m_fontPx;

    // One line if the frame is wide enough for it, otherwise as many as the
    // frame's width forces — with the same wrap the committed label will use, so
    // the text does not move when the edit closes.
    const int oneLine =
        (int)std::ceil(annot::MeasureTextWidth(text, fontPx)) + 2 * pad;
    const int w = std::max(minW, std::min(maxW, oneLine));
    const int lines = (int)annot::WrapLines(text, fontPx,
                                            (Gdiplus::REAL)std::max(w - 2 * pad, 1))
                          .size();
    const int lineH = (int)std::ceil(annot::MeasureTextLineHeight(fontPx));
    return CSize(w, m_fontPx + Dpi::S(hw, annot::kTextPadY) +
                       (lines - 1) * lineH);
}

bool CTextEditor::FitsText(const CString& text) const {
    const CRect here = Frame();
    const CRect lim = Limit();
    return here.top + BoxFor(text, (int)(lim.right - here.left)).cy <= lim.bottom;
}

void CTextEditor::FitToText() {
    const CRect here = Frame();
    CRect cl;
    GetClientRect(&cl);

    const CSize want = BoxFor(Text(), (int)(Limit().right - here.left));
    if (want.cx == cl.Width() && want.cy == cl.Height()) return;

    // The overlay strokes the red frame 2px outside us, so it has to repaint
    // both the band we leave and the band we take.
    CRect was = here;
    was.InflateRect(3, 3);
    CRect now(here.left - 3, here.top - 3, here.left + want.cx + 3,
              here.top + want.cy + 3);
    now.UnionRect(now, was);

    // Frame() is already in the parent's client space, which is what a child
    // MoveWindow wants; the inner edit keeps (0,0) because its parent is us.
    MoveWindow(here.left, here.top, want.cx, want.cy);
    m_edit.MoveWindow(0, 0, want.cx, want.cy);
    RebuildBackdrop();
    GetParent()->InvalidateRect(&now, FALSE);
}

void CTextEditor::RebuildBackdrop() {
    CRect cl;
    GetClientRect(&cl);
    if (cl.IsRectEmpty() || !m_session || !m_session->Overlay().GetSafeHwnd())
        return;

    CPoint src = cl.TopLeft();
    ::ClientToScreen(GetSafeHwnd(), &src);
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
    }
    FitToText();
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
