#include "stdafx.h"
#include "TextEditor.h"
#include "CaptureSession.h"
#include "AppMessages.h"
#include "Shapes.h"
#include "Dpi.h"

namespace {

constexpr int kEditId = 1;
// The box hugs the text: 4px of padding either side of the caret, and the
// vertical padding that makes 文字-点击位置-输入时红色文本框.png's frame read as
// a box rather than an underline.
constexpr int kPadX = 4;
constexpr int kPadY = 20;
constexpr int kMinW = 40;

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
    const CRect box(at.x, at.y, at.x + Dpi::S(ph, kMinW),
                    at.y + fontPx + Dpi::S(ph, kPadY));

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

    if (!m_edit.CreateEx(0, L"EDIT", text,
                         WS_CHILD | WS_VISIBLE | ES_AUTOHSCROLL | ES_WANTRETURN,
                         CRect(0, 0, box.Width(), box.Height()), this, kEditId))
        return FALSE;

    m_edit.SetFont(&m_font, TRUE);
    m_edit.SetSel(-1, -1);
    m_edit.SetFocus();
    FitToText();
    return TRUE;
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

void CTextEditor::FitToText() {
    const int pad = Dpi::S(GetSafeHwnd(), kPadX);
    const int minW = Dpi::S(GetSafeHwnd(), kMinW);
    const int want =
        std::max(minW, (int)std::ceil(annot::MeasureTextWidth(Text(),
                                                              (Gdiplus::REAL)m_fontPx)) +
                           2 * pad);

    CRect cl;
    GetClientRect(&cl);
    if (cl.Width() == want) return;

    CWnd* parent = GetParent();
    CRect pcl;
    parent->GetClientRect(&pcl);
    const CRect here = Frame();
    // The box grows rightwards from the press point but never past the edge.
    // CRect members are LONG, so the comparison has to be too.
    const LONG w = std::min<LONG>(want, pcl.right - here.left);
    // Frame() is already in the parent's client space, which is what a child
    // MoveWindow wants; the inner edit keeps (0,0) because its parent is us.
    MoveWindow(here.left, here.top, w, cl.Height());
    m_edit.MoveWindow(0, 0, w, cl.Height());

    // The overlay strokes the red frame 2px outside us, so it has to repaint
    // both the band we left and the band we now hold.
    CRect now(here.left - 3, here.top - 3, here.left + w + 3,
              here.top + cl.Height() + 3);
    CRect was = here;
    was.InflateRect(3, 3);
    now.UnionRect(now, was);
    parent->InvalidateRect(&now, FALSE);
}

HBRUSH CTextEditor::OnCtlColor(CDC* dc, CWnd* wnd, UINT nCtlColor) {
    // MFC hands the handler a CTLCOLOR_* code, not the WM_CTLCOLOR* message it
    // came from — comparing against WM_CTLCOLOREDIT silently never matches.
    if (wnd == &m_edit && nCtlColor == CTLCOLOR_EDIT) {
        dc->SetTextColor(RGB(m_ink.GetR(), m_ink.GetG(), m_ink.GetB()));
        dc->SetBkColor(m_backColor);
        return (HBRUSH)m_back.GetSafeHandle();
    }
    return CWnd::OnCtlColor(dc, wnd, nCtlColor);
}

BOOL CTextEditor::OnEraseBkgnd(CDC*) {
    return TRUE;
}

void CTextEditor::OnEnChange() {
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
