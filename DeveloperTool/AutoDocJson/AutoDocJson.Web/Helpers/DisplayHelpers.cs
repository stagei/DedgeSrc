namespace AutoDocNew.Web.Helpers;

public static class DisplayHelpers
{
    /// <summary>
    /// Converts all-uppercase program names to title case while leaving
    /// mixed-case names untouched.
    /// E.g. "BDHSAST.CBL" -> "Bdhsast.Cbl", "Run-DBBLoad.ps1" unchanged.
    /// </summary>
    public static string ToTitleCase(string name)
    {
        if (string.IsNullOrEmpty(name)) return name;

        bool hasLower = false;
        foreach (char c in name)
        {
            if (char.IsLower(c)) { hasLower = true; break; }
        }
        if (hasLower) return name;

        var result = new char[name.Length];
        bool capitalizeNext = true;
        for (int i = 0; i < name.Length; i++)
        {
            char c = name[i];
            if (c == '.' || c == '-' || c == '_')
            {
                result[i] = c;
                capitalizeNext = true;
            }
            else if (capitalizeNext)
            {
                result[i] = char.ToUpper(c);
                capitalizeNext = false;
            }
            else
            {
                result[i] = char.ToLower(c);
            }
        }
        return new string(result);
    }
}
