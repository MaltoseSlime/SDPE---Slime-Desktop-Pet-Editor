// 視窗矩形列舉小工具(平臺來源 A,主企劃書第二章)。
// 每隔一段時間列舉桌面上「看得見的頂層視窗」的實際可視矩形(排除陰影),
// 只有在結果跟上一次不同時才輸出一行到 stdout,格式:  W:x,y,w,h;x,y,w,h;...
// 沒有任何視窗時輸出 "W:"。座標是虛擬桌面的實體像素(程序宣告為每螢幕 DPI 感知)。
//
// 用法: window_rects.exe <父程式 PID> [輪詢毫秒,預設 1000]
// 父程式消失(被關閉或當機)時自己結束,不會變成殘留的背景程序。
// 由 Godot 端在第一次使用時以 Windows 內建的 csc.exe 編譯,不需要另外安裝任何東西。

using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

static class WindowRects
{
    delegate bool EnumProc(IntPtr hwnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] static extern bool EnumWindows(EnumProc proc, IntPtr lParam);
    [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] static extern int GetWindowLong(IntPtr hwnd, int index);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetClassName(IntPtr hwnd, StringBuilder sb, int max);
    [DllImport("user32.dll")] static extern bool SetProcessDpiAwarenessContext(IntPtr context);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out RECT rect, int size);
    [DllImport("dwmapi.dll")] static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, out int value, int size);

    const int GWL_EXSTYLE = -20;
    const int WS_EX_TOOLWINDOW = 0x80;
    const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;
    const int DWMWA_CLOAKED = 14;
    const int MIN_WIDTH = 60;
    const int MIN_HEIGHT = 30;

    static uint excludedPid;

    static void Main(string[] args)
    {
        uint parentPid = args.Length > 0 ? uint.Parse(args[0]) : 0;
        int interval = args.Length > 1 ? int.Parse(args[1]) : 1000;
        excludedPid = parentPid;
        // -4 = DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2:讓座標是實體像素,跟 Godot 視窗一致。
        SetProcessDpiAwarenessContext(new IntPtr(-4));

        var stdout = Console.Out;
        string last = null;
        var sb = new StringBuilder();
        while (true)
        {
            if (parentPid != 0 && !ParentAlive(parentPid)) return;
            sb.Clear();
            sb.Append("W:");
            bool first = true;
            EnumWindows((hwnd, l) =>
            {
                RECT r;
                if (!TryGetRect(hwnd, out r)) return true;
                if (!first) sb.Append(';');
                first = false;
                sb.Append(r.Left).Append(',').Append(r.Top).Append(',')
                  .Append(r.Right - r.Left).Append(',').Append(r.Bottom - r.Top);
                return true;
            }, IntPtr.Zero);
            string now = sb.ToString();
            if (now != last)
            {
                stdout.WriteLine(now);
                stdout.Flush();
                last = now;
            }
            Thread.Sleep(interval);
        }
    }

    static bool ParentAlive(uint pid)
    {
        try { return !Process.GetProcessById((int)pid).HasExited; }
        catch { return false; }
    }

    static bool TryGetRect(IntPtr hwnd, out RECT rect)
    {
        rect = new RECT();
        if (!IsWindowVisible(hwnd) || IsIconic(hwnd)) return false;
        uint pid;
        GetWindowThreadProcessId(hwnd, out pid);
        if (pid == excludedPid) return false;
        int cloaked;
        if (DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED, out cloaked, 4) == 0 && cloaked != 0) return false;

        var cls = new StringBuilder(64);
        GetClassName(hwnd, cls, 64);
        string name = cls.ToString();
        // 桌面背景殼層視窗不是一般視窗,不能當平臺。
        if (name == "Progman" || name == "WorkerW") return false;
        // 工具視窗(提示框、浮動面板)不當平臺,但工作列預設納入。
        bool isTaskbar = name == "Shell_TrayWnd" || name == "Shell_SecondaryTrayWnd";
        if (!isTaskbar && (GetWindowLong(hwnd, GWL_EXSTYLE) & WS_EX_TOOLWINDOW) != 0) return false;

        // 用可視邊界(排除陰影),避免平臺線段比畫面上看到的視窗上緣高出一截。
        if (DwmGetWindowAttribute(hwnd, DWMWA_EXTENDED_FRAME_BOUNDS, out rect, Marshal.SizeOf(typeof(RECT))) != 0)
            return false;
        return (rect.Right - rect.Left) >= MIN_WIDTH && (rect.Bottom - rect.Top) >= MIN_HEIGHT;
    }
}
