namespace DedgeRemoteConnect;

public static class IconInverter
{
    public static void InvertIcon(string sourcePath, string destinationPath)
    {
        using Icon originalIcon = new(sourcePath);
        using Bitmap bitmap = originalIcon.ToBitmap();

        // Create inverted bitmap
        Bitmap invertedBitmap = new(bitmap.Width, bitmap.Height);

        for (int y = 0; y < bitmap.Height; y++)
        {
            for (int x = 0; x < bitmap.Width; x++)
            {
                Color pixel = bitmap.GetPixel(x, y);
                if (pixel.A > 0) // Only invert non-transparent pixels
                {
                    invertedBitmap.SetPixel(x, y, Color.FromArgb(
                        pixel.A,
                        255 - pixel.R,
                        255 - pixel.G,
                        255 - pixel.B
                    ));
                }
            }
        }

        // Save as icon
        using MemoryStream iconStream = new();
        nint handle = invertedBitmap.GetHicon();
        using Icon newIcon = Icon.FromHandle(handle);
        using FileStream fileStream = File.Create(destinationPath);
        newIcon.Save(fileStream);

        // Cleanup
        DestroyIcon(handle);
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", SetLastError = true)]
    private static extern bool DestroyIcon(IntPtr hIcon);
}