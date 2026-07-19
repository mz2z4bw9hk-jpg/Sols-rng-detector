using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;

namespace BiomeAlertPro;

/// <summary>
/// Win32 interop: locating the Discord window, capturing it, synthesizing
/// clicks, and registering global hotkeys. All standard user32/gdi32 —
/// nothing third-party.
/// </summary>
internal static class Native
{
    // MARK: Window enumeration / geometry

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc proc, IntPtr lParam);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowTextLength(IntPtr hWnd);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
    public const int SW_RESTORE = 9;

    // MARK: Window capture (PrintWindow renders even occluded / background windows)

    [DllImport("user32.dll")] public static extern IntPtr GetWindowDC(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr hWnd, IntPtr hDC);
    [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr hWnd, IntPtr hdcBlt, uint nFlags);
    public const uint PW_RENDERFULLCONTENT = 0x00000002;

    /// <summary>Finds the largest visible top-level Discord window, or IntPtr.Zero.</summary>
    public static IntPtr FindDiscordWindow()
    {
        IntPtr best = IntPtr.Zero;
        long bestArea = 0;
        EnumWindows((hWnd, _) =>
        {
            if (!IsWindowVisible(hWnd)) return true;
            int len = GetWindowTextLength(hWnd);
            if (len == 0) return true;
            var sb = new StringBuilder(len + 1);
            GetWindowText(hWnd, sb, sb.Capacity);
            string title = sb.ToString();
            // Discord window titles look like "#channel | Server - Discord" or "Discord".
            if (title.IndexOf("Discord", StringComparison.OrdinalIgnoreCase) < 0) return true;
            if (!GetWindowRect(hWnd, out RECT r)) return true;
            long w = r.Right - r.Left, h = r.Bottom - r.Top;
            if (w < 400 || h < 300) return true;
            long area = w * h;
            if (area > bestArea) { bestArea = area; best = hWnd; }
            return true;
        }, IntPtr.Zero);
        return best;
    }

    /// <summary>Captures a window's pixels into a Bitmap via PrintWindow.</summary>
    public static Bitmap? CaptureWindow(IntPtr hWnd, out RECT rect)
    {
        rect = default;
        if (hWnd == IntPtr.Zero || !GetWindowRect(hWnd, out rect)) return null;
        int width = rect.Right - rect.Left, height = rect.Bottom - rect.Top;
        if (width <= 0 || height <= 0) return null;

        var bmp = new Bitmap(width, height);
        using var g = Graphics.FromImage(bmp);
        IntPtr hdc = g.GetHdc();
        bool ok = PrintWindow(hWnd, hdc, PW_RENDERFULLCONTENT);
        g.ReleaseHdc(hdc);
        if (!ok) { bmp.Dispose(); return null; }
        return bmp;
    }

    // MARK: Synthetic mouse click (SendInput, absolute virtual-desktop coords)

    [StructLayout(LayoutKind.Sequential)]
    public struct INPUT { public uint type; public MOUSEINPUT mi; }

    [StructLayout(LayoutKind.Sequential)]
    public struct MOUSEINPUT
    {
        public int dx, dy;
        public uint mouseData, dwFlags, time;
        public IntPtr dwExtraInfo;
    }

    [DllImport("user32.dll", SetLastError = true)]
    public static extern uint SendInput(uint nInputs, INPUT[] pInputs, int cbSize);

    [DllImport("user32.dll")] public static extern bool GetCursorPos(out System.Drawing.Point p);
    [DllImport("user32.dll")] public static extern int GetSystemMetrics(int index);

    private const uint INPUT_MOUSE = 0;
    private const uint MOUSEEVENTF_MOVE = 0x0001;
    private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
    private const uint MOUSEEVENTF_LEFTUP = 0x0004;
    private const uint MOUSEEVENTF_ABSOLUTE = 0x8000;
    private const uint MOUSEEVENTF_VIRTUALDESK = 0x4000;
    private const int SM_XVIRTUALSCREEN = 76;
    private const int SM_YVIRTUALSCREEN = 77;
    private const int SM_CXVIRTUALSCREEN = 78;
    private const int SM_CYVIRTUALSCREEN = 79;

    /// <summary>Left-clicks at a physical screen pixel, restoring the cursor.</summary>
    public static void ClickAt(int screenX, int screenY)
    {
        GetCursorPos(out var restore);

        int vx = GetSystemMetrics(SM_XVIRTUALSCREEN);
        int vy = GetSystemMetrics(SM_YVIRTUALSCREEN);
        int vw = GetSystemMetrics(SM_CXVIRTUALSCREEN);
        int vh = GetSystemMetrics(SM_CYVIRTUALSCREEN);
        if (vw <= 1 || vh <= 1) return;

        int absX = (int)((screenX - vx) * 65535.0 / (vw - 1));
        int absY = (int)((screenY - vy) * 65535.0 / (vh - 1));

        var inputs = new[]
        {
            MouseInput(absX, absY, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK),
            MouseInput(absX, absY, MOUSEEVENTF_LEFTDOWN | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK),
            MouseInput(absX, absY, MOUSEEVENTF_LEFTUP | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK),
        };
        SendInput((uint)inputs.Length, inputs, Marshal.SizeOf<INPUT>());

        // Restore the cursor so the pointer doesn't visibly stay moved.
        int rAbsX = (int)((restore.X - vx) * 65535.0 / (vw - 1));
        int rAbsY = (int)((restore.Y - vy) * 65535.0 / (vh - 1));
        var back = new[] { MouseInput(rAbsX, rAbsY, MOUSEEVENTF_MOVE | MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_VIRTUALDESK) };
        SendInput((uint)back.Length, back, Marshal.SizeOf<INPUT>());
    }

    private static INPUT MouseInput(int x, int y, uint flags) => new()
    {
        type = INPUT_MOUSE,
        mi = new MOUSEINPUT { dx = x, dy = y, dwFlags = flags }
    };

    /// <summary>Brings Discord to the foreground (so a click lands on it).</summary>
    public static void FocusWindow(IntPtr hWnd)
    {
        if (hWnd == IntPtr.Zero) return;
        ShowWindow(hWnd, SW_RESTORE);
        SetForegroundWindow(hWnd);
    }

    public static bool IsForeground(IntPtr hWnd) => GetForegroundWindow() == hWnd;

    // MARK: Global hotkeys

    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr hWnd, int id, uint fsModifiers, uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr hWnd, int id);

    public const uint MOD_ALT = 0x0001;
    public const uint MOD_CONTROL = 0x0002;
    public const int WM_HOTKEY = 0x0312;
}
