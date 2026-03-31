using System.Text;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Logging;
using Microsoft.Extensions.Options;
using DedgeAuth.Core.Models;
using DedgeAuth.Data;

namespace DedgeAuth.Services;

/// <summary>
/// Service to seed initial data into the database
/// </summary>
public class DatabaseSeeder
{
    private static readonly List<string> StandardAppRoles =
        new() { "ReadOnly", "User", "PowerUser", "Admin" };

    private readonly AuthDbContext _context;
    private readonly AuthConfiguration _config;
    private readonly ILogger<DatabaseSeeder> _logger;

    public DatabaseSeeder(
        AuthDbContext context,
        IOptions<AuthConfiguration> config,
        ILogger<DatabaseSeeder> logger)
    {
        _context = context;
        _config = config.Value;
        _logger = logger;
    }

    /// <summary>
    /// Seed the database with initial data
    /// </summary>
    public async Task SeedAsync()
    {
        await SeedDefaultTenantAsync();
        await SeedDefaultAppsAsync();
        await NormalizeLocalhostPortUrlsAsync();
        await NormalizeAllAppRolesAsync();
        await SeedAdminUsersAsync();
        await EnsureAllUsersHaveFullPermissionsAsync();
        await SeedDefaultAppGroupsAsync();
    }

    private static string MapRoleToStandard(string? role)
    {
        if (string.IsNullOrWhiteSpace(role))
            return "User";

        return role.Trim().ToLowerInvariant() switch
        {
            "admin" => "Admin",
            "globaladmin" => "Admin",
            "poweruser" => "PowerUser",
            "power_user" => "PowerUser",
            "read_only" => "ReadOnly",
            "readonly" => "ReadOnly",
            "viewer" => "ReadOnly",
            "operator" => "User", // Non-standard role maps to User by default.
            "user" => "User",
            _ => "User"
        };
    }

    /// <summary>
    /// Build the default URL for a new app: always uses http://localhost/{appId} (IIS virtual app format).
    /// Server-specific URLs are set via the admin UI "Update All" feature, not at seed time.
    /// </summary>
    private static string GetAppUrl(string appId)
    {
        return $"http://localhost/{appId}";
    }

    private static Dictionary<string, string> GetDefaultAppRouting()
    {
        return new Dictionary<string, string>
        {
            { "GenericLogHandler", GetAppUrl("GenericLogHandler") },
            { "ServerMonitorDashboard", GetAppUrl("ServerMonitorDashboard") },
            { "DocView", GetAppUrl("DocView") }
        };
    }

    /// <summary>
    /// Dedge logo SVG stored as an embedded constant.
    /// Served from the database via GET /tenants/{domain}/logo endpoint.
    /// </summary>
    private static string GetDedgeLogoSvg() =>
        """<svg xmlns="http://www.w3.org/2000/svg" id="Layer_1" width="237" height="42" data-name="Layer 1" viewBox="0 0 237 42"><defs><style>.cls-1{fill:#ffe500;isolation:isolate}.cls-2{fill:#008d44}</style></defs><circle cx="19.75" cy="20.75" r="16.907" class="cls-1"/><rect width="4.317" height="24.725" x="95.854" y="8.191" class="cls-2"/><rect width="4.317" height="24.725" x="103.446" y="8.191" class="cls-2"/><polygon points="154.643 22.693 161.652 15.003 156.042 15.003 149.645 22.24 149.645 8.191 145.327 8.191 145.327 32.916 149.645 32.916 149.645 28.145 151.694 25.937 156.624 32.916 161.947 32.916 154.643 22.693" class="cls-2"/><path d="M 199.413 14.678 C 198.231 14.655 197.064 14.938 196.026 15.502 C 195.061 16.034 194.292 16.861 193.833 17.862 L 193.833 15.003 L 189.614 15.003 L 189.614 39.6 L 193.931 39.6 L 193.931 30.307 C 195.058 32.152 196.85 33.067 199.315 33.067 C 201.444 33.121 203.495 32.259 204.948 30.701 C 206.46 29.123 207.216 26.84 207.216 23.85 C 207.216 20.861 206.475 18.593 204.993 17.045 C 203.563 15.485 201.528 14.622 199.413 14.678 Z M 201.553 27.85 C 200.741 28.742 199.583 29.241 198.377 29.219 C 197.16 29.241 195.989 28.753 195.148 27.873 C 194.203 26.784 193.729 25.364 193.833 23.926 C 193.728 22.49 194.202 21.072 195.148 19.986 C 195.987 19.103 197.159 18.615 198.377 18.64 C 199.582 18.619 200.737 19.115 201.553 20.001 C 202.484 21.088 202.952 22.498 202.853 23.926 C 202.952 25.354 202.484 26.763 201.553 27.85 Z" class="cls-2"/><path d="M 234.822 29.09 C 234.296 29.158 233.768 28.989 233.378 28.629 C 233.101 28.232 232.971 27.751 233.008 27.268 L 233.008 18.897 L 236.577 18.897 L 236.577 15.003 L 233.008 15.003 L 233.008 9.779 L 228.69 10.981 L 228.69 15.003 L 225.416 15.003 L 225.416 18.897 L 228.69 18.897 L 228.69 27.071 C 228.69 29.324 229.144 30.862 230.051 31.684 C 230.966 32.508 232.32 32.916 234.172 32.916 L 237 32.916 L 237 29.09 Z" class="cls-2"/><path d="M 85.518 14.678 C 83.223 14.628 81.008 15.519 79.386 17.143 C 77.722 18.792 76.89 21.086 76.89 24.024 C 76.89 26.963 77.732 29.256 79.416 30.905 C 81.035 32.474 83.21 33.336 85.465 33.302 C 87.347 33.331 89.187 32.744 90.705 31.631 C 92.135 30.603 93.11 29.061 93.427 27.328 L 89.457 27.328 C 89.234 27.997 88.777 28.564 88.172 28.924 C 87.416 29.368 86.552 29.594 85.677 29.574 C 84.493 29.617 83.337 29.218 82.433 28.455 C 81.533 27.638 81.034 26.471 81.064 25.257 L 93.525 25.257 L 93.525 23.502 C 93.525 20.674 92.769 18.489 91.257 16.969 C 89.743 15.444 87.665 14.615 85.518 14.678 Z M 81.17 22.111 C 81.272 21.018 81.819 20.015 82.682 19.336 C 83.498 18.717 84.5 18.392 85.525 18.414 C 86.533 18.37 87.519 18.723 88.27 19.397 C 88.995 20.11 89.388 21.095 89.351 22.111 Z" class="cls-2"/><path d="M 217.038 14.678 C 214.743 14.627 212.526 15.518 210.906 17.143 C 209.237 18.792 208.403 21.086 208.403 24.024 C 208.403 26.963 209.247 29.256 210.936 30.905 C 212.554 32.474 214.731 33.337 216.985 33.302 C 218.867 33.331 220.708 32.744 222.225 31.631 C 223.672 30.611 224.665 29.068 224.993 27.328 L 220.985 27.328 C 220.76 27.996 220.304 28.562 219.7 28.924 C 217.864 29.938 215.599 29.754 213.953 28.455 C 213.059 27.635 212.563 26.469 212.592 25.257 L 225.053 25.257 L 225.053 23.502 C 225.053 20.674 224.297 18.489 222.785 16.969 C 221.271 15.44 219.189 14.61 217.038 14.678 Z M 212.691 22.111 C 212.784 21.024 213.316 20.022 214.165 19.336 C 214.981 18.717 215.983 18.392 217.008 18.414 C 218.014 18.371 218.996 18.724 219.745 19.397 C 220.47 20.111 220.864 21.095 220.834 22.111 Z" class="cls-2"/><path d="M 118.379 14.678 C 116.084 14.628 113.869 15.519 112.247 17.143 C 110.583 18.792 109.752 21.086 109.752 24.024 C 109.752 26.963 110.593 29.256 112.277 30.905 C 113.904 32.498 116.102 33.373 118.379 33.332 C 120.261 33.361 122.101 32.775 123.619 31.661 C 125.043 30.63 126.013 29.089 126.326 27.359 L 122.356 27.359 C 122.133 28.028 121.676 28.594 121.071 28.954 C 120.315 29.399 119.451 29.624 118.576 29.604 C 117.396 29.633 116.248 29.224 115.355 28.455 C 114.455 27.638 113.956 26.471 113.986 25.257 L 126.447 25.257 L 126.447 23.502 C 126.447 20.674 125.691 18.489 124.179 16.969 C 122.65 15.428 120.547 14.597 118.379 14.678 Z M 114.031 22.111 C 114.124 21.024 114.657 20.022 115.506 19.336 C 116.33 18.71 117.344 18.384 118.379 18.414 C 119.387 18.37 120.372 18.723 121.124 19.397 C 121.849 20.11 122.241 21.095 122.205 22.111 Z" class="cls-2"/><path d="M 140.851 23.404 C 139.335 22.798 137.742 22.405 136.118 22.24 C 135.132 22.131 134.162 21.908 133.229 21.574 C 132.68 21.376 132.323 20.842 132.352 20.259 C 132.358 19.692 132.64 19.164 133.108 18.845 C 133.782 18.414 134.579 18.214 135.377 18.277 C 137.259 18.277 138.333 19.034 138.583 20.448 L 142.817 20.448 C 142.71 18.798 141.904 17.271 140.602 16.251 C 139.064 15.147 137.199 14.593 135.309 14.678 C 133.509 14.61 131.734 15.11 130.235 16.107 C 128.865 17.089 128.097 18.705 128.201 20.387 C 128.201 20.516 128.201 20.637 128.201 20.758 C 128.177 22.408 129.091 23.929 130.56 24.682 C 131.207 25 131.889 25.239 132.594 25.393 L 133.123 25.521 L 134.159 25.733 L 134.484 25.793 L 135.687 26.005 C 136.594 26.11 137.484 26.334 138.333 26.67 C 138.76 26.875 139.023 27.316 138.999 27.79 C 138.999 29.09 137.955 29.733 135.883 29.733 C 133.615 29.733 132.337 28.931 132.035 27.328 L 127.657 27.328 C 127.711 28.241 127.97 29.13 128.413 29.929 C 128.866 30.741 129.519 31.423 130.311 31.91 C 131.085 32.384 131.926 32.738 132.806 32.961 C 133.73 33.194 134.68 33.308 135.634 33.302 C 137.553 33.383 139.448 32.854 141.048 31.789 C 142.483 30.796 143.306 29.133 143.225 27.389 C 143.327 25.699 142.385 24.119 140.851 23.404 Z" class="cls-2"/><path d="M 163.656 33.952 C 163.692 34.437 163.561 34.921 163.285 35.321 C 162.893 35.676 162.365 35.842 161.841 35.774 L 160.382 35.774 L 160.382 39.6 L 162.491 39.6 C 164.331 39.6 165.705 39.19 166.612 38.368 C 167.52 37.547 167.973 36.012 167.973 33.763 L 167.973 15.003 L 163.656 15.003 Z" class="cls-2"/><path d="M 184.737 16.909 L 186.083 15.041 L 186.083 15.041 L 184.721 14.066 L 183.406 15.896 C 181.987 15.062 180.363 14.641 178.718 14.678 C 176.365 14.599 174.087 15.513 172.442 17.196 C 170.809 18.87 169.992 21.139 169.992 24.001 C 169.861 26.507 170.744 28.959 172.442 30.806 L 172.578 30.935 L 171.141 32.931 L 172.502 33.914 L 173.886 31.994 C 175.328 32.902 177.005 33.368 178.71 33.332 C 181.074 33.42 183.366 32.509 185.024 30.822 C 186.721 28.974 187.604 26.522 187.474 24.016 C 187.474 21.158 186.657 18.89 185.024 17.211 Z M 174.4 24.122 C 174.307 22.692 174.719 21.273 175.565 20.115 C 176.322 19.18 177.477 18.656 178.68 18.701 C 179.48 18.682 180.269 18.897 180.948 19.321 L 175.187 27.321 C 174.631 26.349 174.359 25.241 174.4 24.122 Z M 181.894 27.903 C 181.132 28.834 179.979 29.354 178.778 29.309 C 177.907 29.317 177.057 29.053 176.344 28.553 L 181.516 21.378 L 182.166 20.478 C 182.807 21.485 183.122 22.665 183.066 23.858 C 183.156 25.292 182.741 26.713 181.894 27.873 Z" class="cls-2"/><polygon points="59.235 32.916 63.741 32.916 63.741 22.723 75 22.723 75 18.474 63.741 18.474 63.741 12.796 75.59 12.796 75.59 8.576 59.235 8.576 59.235 32.916" class="cls-2"/><path d="M 0 40.5 L 39.5 40.5 L 39.5 1 L 0 1 Z M 19.75 3.843 C 32.764 3.843 40.899 17.933 34.392 29.203 C 27.884 40.475 11.616 40.475 5.108 29.203 C 3.624 26.633 2.843 23.718 2.843 20.75 C 2.843 11.413 10.412 3.843 19.75 3.843 Z" class="cls-2"/><polygon points="9.724 21.536 13.777 21.536 13.777 19.669 9.724 19.669 9.724 17.415 13.996 17.415 13.996 15.555 7.856 15.555 7.856 25.998 9.724 25.998 9.724 21.536" class="cls-2"/><polygon points="27.372 23.464 28.498 21.672 30.782 25.998 32.891 25.998 29.738 20.047 32.566 15.555 30.366 15.555 27.372 20.319 27.372 15.555 25.512 15.555 25.512 25.998 27.372 25.998 27.372 23.464" class="cls-2"/><path d="M 19.75 29.468 C 19.428 29.463 19.108 29.417 18.797 29.332 L 18.57 30.179 C 18.818 30.24 19.072 30.283 19.327 30.307 L 19.327 34.844 L 20.204 34.844 L 20.204 30.307 C 20.458 30.281 20.711 30.236 20.96 30.171 L 20.748 29.324 C 20.423 29.416 20.087 29.464 19.75 29.468 Z" class="cls-2"/><path d="M 19.75 28.878 C 21.479 28.879 22.892 27.499 22.933 25.771 L 22.933 25.771 L 22.933 8.712 L 22.064 8.712 L 22.064 15.654 C 22.064 16.47 21.829 16.833 20.914 17.423 C 20.623 17.573 20.365 17.781 20.158 18.036 L 20.158 17.068 L 20.158 17.068 L 20.158 6.694 L 19.327 6.694 L 19.327 16.879 L 19.327 16.879 L 19.327 18.036 C 19.116 17.793 18.859 17.595 18.57 17.453 C 17.77 17.111 17.299 16.274 17.421 15.412 L 17.421 8.712 L 16.567 8.712 L 16.567 25.771 L 16.567 25.771 C 16.604 27.501 18.019 28.883 19.75 28.878 Z M 20.189 20.319 C 20.141 19.431 20.605 18.594 21.383 18.164 C 21.631 18.003 21.86 17.812 22.064 17.597 L 22.064 18.86 C 22.184 19.724 21.71 20.561 20.907 20.901 C 20.615 21.051 20.357 21.26 20.151 21.514 Z M 20.189 23.79 C 20.145 22.903 20.607 22.068 21.383 21.635 C 21.633 21.479 21.862 21.291 22.064 21.075 L 22.064 22.338 C 22.184 23.202 21.71 24.039 20.907 24.379 C 20.613 24.527 20.355 24.736 20.151 24.992 Z M 20.189 27.26 C 20.201 26.388 20.649 25.579 21.383 25.105 C 21.634 24.946 21.862 24.756 22.064 24.538 L 22.064 25.695 C 22.061 26.803 21.276 27.754 20.189 27.963 Z M 17.444 17.597 C 17.645 17.815 17.874 18.005 18.124 18.164 C 18.904 18.594 19.37 19.431 19.327 20.319 L 19.327 21.514 C 19.119 21.26 18.862 21.051 18.57 20.901 C 17.77 20.559 17.299 19.722 17.421 18.86 Z M 17.444 21.075 C 17.643 21.292 17.873 21.48 18.124 21.635 C 18.901 22.067 19.367 22.902 19.327 23.79 L 19.327 25.015 C 19.122 24.758 18.864 24.55 18.57 24.402 C 17.77 24.06 17.299 23.223 17.421 22.361 Z M 17.444 24.538 C 17.643 24.758 17.873 24.949 18.124 25.105 C 18.868 25.58 19.321 26.401 19.327 27.283 L 19.327 27.986 C 18.232 27.79 17.441 26.83 17.459 25.718 Z" class="cls-2"/><path d="M 165.818 7.457 C 163.815 7.457 162.564 9.625 163.565 11.359 C 164.566 13.093 167.07 13.093 168.071 11.359 C 168.299 10.963 168.419 10.515 168.419 10.058 C 168.419 8.622 167.254 7.457 165.818 7.457 Z" class="cls-2"/></svg>""";

    /// <summary>
    /// Dedge tenant theme CSS.
    /// Sets brand colors and app-specific variables used by all consumer apps
    /// (DocView, GenericLogHandler, ServerMonitorDashboard).
    /// Loaded into #DedgeAuth-tenant-css via /tenants/{domain}/theme.css endpoint.
    /// </summary>
    private static string GetDedgeThemeCss() => """
        /* ═══════════════════════════════════════════════════════════════════
           Dedge Tenant Theme
           Comprehensive CSS variables for all DedgeAuth consumer apps:
           DedgeAuth, DocView, GenericLogHandler, ServerMonitorDashboard.
           Loaded AFTER each app's local CSS to enforce consistent theming.
           ═══════════════════════════════════════════════════════════════════ */

        /* ── Light Theme ─────────────────────────────────────────────────── */
        :root {
            /* Brand Colors - FK Green */
            --primary-color: #008942;
            --primary-hover: #00b359;

            /* Backgrounds (shared across all apps) */
            --bg-primary: #f8fafc;
            --bg-secondary: #ffffff;
            --bg-tertiary: #f1f5f9;
            --bg-card: #ffffff;
            --bg-hover: #f1f5f9;
            --bg-input: #ffffff;

            /* Text */
            --text-primary: #0f172a;
            --text-secondary: #475569;
            --text-muted: #94a3b8;

            /* Borders */
            --border-color: #cbd5e1;
            --border-focus: #008942;
            --card-border: 1px solid #e2e8f0;

            /* Accent */
            --accent-color: #0369a1;
            --accent-hover: #0284c7;

            /* Status */
            --success-color: #059669;
            --warning-color: #d97706;
            --error-color: #dc2626;
            --info-color: #0284c7;
            --danger-color: #dc2626;
            --critical-color: #dc2626;

            /* Shadows */
            --shadow: 0 1px 3px rgba(0, 0, 0, 0.12), 0 1px 2px rgba(0, 0, 0, 0.08);
            --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.05);
            --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.1);
            --shadow-lg: 0 4px 12px rgba(0, 0, 0, 0.15), 0 2px 6px rgba(0, 0, 0, 0.1);

            /* Shape */
            --radius: 8px;
            --font-mono: 'JetBrains Mono', 'Fira Code', 'Consolas', monospace;

            /* ServerMonitor: gauge, panels */
            --gauge-bg: #e2e8f0;
            --panel-header-bg: linear-gradient(135deg, #f8fafc, #f1f5f9);

            /* Config/form editors: selection */
            --selection-bg: #0369a1;
            --selection-text: #ffffff;

            /* DocView: tree, code blocks */
            --tree-hover: #f0f0f5;
            --code-bg: #f6f8fa;
        }

        /* ── Dark Theme ──────────────────────────────────────────────────── */
        [data-theme="dark"] {
            --primary-color: #00b359;
            --primary-hover: #00cc66;

            --bg-primary: #1f1f1f;
            --bg-secondary: #2a2a2a;
            --bg-tertiary: #333333;
            --bg-card: #000000;
            --bg-hover: #333333;
            --bg-input: #333333;

            --text-primary: #f8fafc;
            --text-secondary: #e4e4e7;
            --text-muted: #d4d4d8;

            --border-color: #444444;
            --border-focus: #60a5fa;
            --card-border: 1px solid #444444;

            --accent-color: #60a5fa;
            --accent-hover: #3b82f6;

            --success-color: #34d399;
            --warning-color: #fbbf24;
            --error-color: #f87171;
            --info-color: #38bdf8;
            --danger-color: #f87171;
            --critical-color: #f87171;

            --shadow: 0 1px 3px rgba(0, 0, 0, 0.4), 0 1px 2px rgba(0, 0, 0, 0.3);
            --shadow-sm: 0 1px 2px rgba(0, 0, 0, 0.3);
            --shadow-md: 0 4px 6px -1px rgba(0, 0, 0, 0.4);
            --shadow-lg: 0 4px 12px rgba(0, 0, 0, 0.5), 0 2px 6px rgba(0, 0, 0, 0.4);

            --gauge-bg: #333333;
            --panel-header-bg: linear-gradient(135deg, #2a2a2a, #333333);

            --selection-bg: #60a5fa;
            --selection-text: #ffffff;

            --tree-hover: #2d2d30;
            --code-bg: #24292e;
        }

        /* ── Utility Classes ────────────────────────────────────────────── */

        /* Tenant logo sizing */
        .tenant-logo {
            max-width: 200px;
            height: auto;
        }

        /* ── Search / Modal Dialog (shared pattern) ─────────────────────── */
        .modal-overlay {
            position: fixed;
            top: 0;
            left: 0;
            right: 0;
            bottom: 0;
            background: rgba(0, 0, 0, 0.75);
            display: flex;
            align-items: center;
            justify-content: center;
            z-index: 1000;
            padding: 2rem;
        }
        .modal-overlay.hidden { display: none; }
        .modal-container {
            background: var(--bg-card);
            border-radius: var(--radius);
            max-width: 800px;
            width: 100%;
            max-height: 90vh;
            display: flex;
            flex-direction: column;
            box-shadow: 0 25px 50px rgba(0, 0, 0, 0.5);
            border: 1px solid var(--border-color);
        }
        .modal-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 1rem 1.5rem;
            border-bottom: 1px solid var(--border-color);
            background: var(--bg-secondary);
            border-radius: var(--radius) var(--radius) 0 0;
        }
        .modal-header h2, .modal-header .modal-title { margin: 0; font-size: 1.1rem; }
        .modal-close {
            background: none;
            border: none;
            font-size: 1.5rem;
            cursor: pointer;
            color: var(--text-muted);
            padding: 0.25rem 0.5rem;
            border-radius: 4px;
            line-height: 1;
        }
        .modal-close:hover { background: var(--bg-primary); color: var(--text-primary); }
        .modal-body {
            padding: 1.5rem;
            overflow-y: auto;
            flex: 1;
        }
        .modal-footer {
            display: flex;
            justify-content: flex-end;
            gap: 0.5rem;
            padding: 1rem 1.5rem;
            border-top: 1px solid var(--border-color);
            background: var(--bg-secondary);
            border-radius: 0 0 var(--radius) var(--radius);
        }
        .modal-sm { max-width: 400px; }
        .modal-md { max-width: 600px; }
        .modal-lg { max-width: 900px; }
        .modal-fullscreen { max-width: calc(100vw - 2rem); max-height: calc(100vh - 2rem); }
        .search-history-container { position: relative; display: inline-block; }
        .search-history-dropdown {
            position: absolute;
            top: 100%;
            left: 0;
            margin-top: 0.25rem;
            min-width: 280px;
            max-width: 400px;
            background: var(--bg-card);
            border: 1px solid var(--border-color);
            border-radius: var(--radius);
            box-shadow: var(--shadow-lg);
            z-index: 1000;
            max-height: 400px;
            overflow-y: auto;
        }
        .search-history-dropdown.hidden { display: none; }
        .search-history-empty {
            padding: 1rem;
            text-align: center;
            color: var(--text-muted);
            font-size: 0.9rem;
        }
        .search-history-item {
            display: flex;
            justify-content: space-between;
            align-items: center;
            padding: 0.6rem 0.75rem;
            border-bottom: 1px solid var(--border-color);
            cursor: pointer;
            transition: background 0.15s ease;
        }
        .search-history-item:hover { background: var(--bg-tertiary); }
        .search-history-item:last-of-type { border-bottom: none; }
        .search-history-text {
            flex: 1;
            font-size: 0.85rem;
            color: var(--text-primary);
            overflow: hidden;
            text-overflow: ellipsis;
            white-space: nowrap;
        }
        .search-history-time {
            font-size: 0.75rem;
            color: var(--text-muted);
            margin-left: 0.5rem;
            white-space: nowrap;
        }
        .search-history-clear {
            padding: 0.6rem 0.75rem;
            text-align: center;
            color: var(--error-color);
            font-size: 0.85rem;
            cursor: pointer;
            border-top: 1px solid var(--border-color);
        }
        .search-history-clear:hover { background: var(--bg-tertiary); }
        """;

    /// <summary>
    /// Load dedge.ico from known filesystem locations.
    /// Returns null if not found (icon seeding will be skipped gracefully).
    /// </summary>
    private byte[]? LoadFkIcon()
    {
        var candidates = new[]
        {
            Path.Combine(Environment.GetEnvironmentVariable("OptPath") ?? @"C:\opt", "data", "DedgeCommon", "_Configfiles", "Resources", "dedge.ico"),
            @"C:\opt\data\DedgeCommon\_Configfiles\Resources\dedge.ico",
            @"C:\opt\DedgePshApps\AutoDoc\_images\dedge.ico"
        };

        foreach (var path in candidates)
        {
            if (File.Exists(path))
            {
                var data = File.ReadAllBytes(path);
                _logger.LogInformation("Loaded dedge.ico from {Path} ({Size} bytes)", path, data.Length);
                return data;
            }
        }

        _logger.LogWarning("dedge.ico not found in any known location, icon seeding skipped");
        return null;
    }

    private async Task SeedDefaultTenantAsync()
    {
        var domain = _config.AllowedDomain;
        if (string.IsNullOrEmpty(domain))
        {
            domain = "Dedge.no";
        }

        var appRouting = GetDefaultAppRouting();

        var logoSvg = GetDedgeLogoSvg();
        var logoData = Encoding.UTF8.GetBytes(logoSvg);
        const string logoContentType = "image/svg+xml";
        var themeCss = GetDedgeThemeCss();
        var iconData = LoadFkIcon();
        const string iconContentType = "image/x-icon";

        if (!await _context.Tenants.AnyAsync())
        {
            var tenant = new Tenant
            {
                Domain = domain,
                DisplayName = "Dedge",
                LogoData = logoData,
                LogoContentType = logoContentType,
                IconData = iconData,
                IconContentType = iconData != null ? iconContentType : null,
                PrimaryColor = "#008942",
                CssOverrides = themeCss,
                AdDomain = domain.Equals("Dedge.no", StringComparison.OrdinalIgnoreCase) ? "DEDGE" : null,
                WindowsSsoEnabled = domain.Equals("Dedge.no", StringComparison.OrdinalIgnoreCase)
            };
            tenant.SetAppRouting(appRouting);

            _context.Tenants.Add(tenant);
            await _context.SaveChangesAsync();
            _logger.LogInformation("Default tenant created: {Domain} (first-time setup)", domain);
        }
        else if (!await _context.Tenants.AnyAsync(t => t.Domain == domain))
        {
            var tenant = new Tenant
            {
                Domain = domain,
                DisplayName = "Dedge",
                LogoData = logoData,
                LogoContentType = logoContentType,
                IconData = iconData,
                IconContentType = iconData != null ? iconContentType : null,
                PrimaryColor = "#008942",
                CssOverrides = themeCss,
                AdDomain = domain.Equals("Dedge.no", StringComparison.OrdinalIgnoreCase) ? "DEDGE" : null,
                WindowsSsoEnabled = domain.Equals("Dedge.no", StringComparison.OrdinalIgnoreCase)
            };
            tenant.SetAppRouting(appRouting);

            _context.Tenants.Add(tenant);
            await _context.SaveChangesAsync();
            _logger.LogInformation("Additional tenant created: {Domain}", domain);
        }
        else
        {
            var existingTenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain == domain);
            if (existingTenant != null)
            {
                bool updated = false;
                
                if (existingTenant.LogoData == null || existingTenant.LogoData.Length == 0)
                {
                    _logger.LogInformation("Migrating tenant {Domain} logo to database storage (was: {OldUrl})",
                        domain, existingTenant.LogoUrl ?? "none");
                    existingTenant.LogoData = logoData;
                    existingTenant.LogoContentType = logoContentType;
                    existingTenant.LogoUrl = null;
                    updated = true;
                }
                
                // Seed icon if not yet stored
                if ((existingTenant.IconData == null || existingTenant.IconData.Length == 0) && iconData != null)
                {
                    _logger.LogInformation("Seeding tenant {Domain} icon from dedge.ico ({Size} bytes)",
                        domain, iconData.Length);
                    existingTenant.IconData = iconData;
                    existingTenant.IconContentType = iconContentType;
                    updated = true;
                }
                
                // Update CSS if empty, a legacy path reference, or a stub shorter than the
                // full Dedge theme (< 500 chars means it is the old 4-variable minimal CSS).
                var cssIsStub = string.IsNullOrEmpty(existingTenant.CssOverrides)
                    || existingTenant.CssOverrides.StartsWith("/")
                    || existingTenant.CssOverrides.Length < 500;

                if (cssIsStub)
                {
                    _logger.LogInformation("Setting tenant {Domain} CssOverrides from seeder theme (previous: {Length} chars)", domain, existingTenant.CssOverrides?.Length ?? 0);
                    existingTenant.CssOverrides = themeCss;
                    updated = true;
                }

                if (domain.Equals("Dedge.no", StringComparison.OrdinalIgnoreCase) && !existingTenant.WindowsSsoEnabled)
                {
                    _logger.LogInformation("Enabling WindowsSsoEnabled for tenant {Domain}", domain);
                    existingTenant.WindowsSsoEnabled = true;
                    updated = true;
                }

                if (domain.Equals("Dedge.no", StringComparison.OrdinalIgnoreCase)
                    && string.IsNullOrEmpty(existingTenant.AdDomain))
                {
                    _logger.LogInformation("Setting AdDomain=DEDGE for tenant {Domain}", domain);
                    existingTenant.AdDomain = "DEDGE";
                    updated = true;
                }
                
                if (updated)
                {
                    await _context.SaveChangesAsync();
                    _logger.LogInformation("Updated tenant settings for: {Domain}", domain);
                }
            }
        }
    }

    private async Task SeedDefaultAppsAsync()
    {
        var apps = new[]
        {
            new App
            {
                AppId = "GenericLogHandler",
                DisplayName = "Generic Log Handler",
                Description = "Log aggregation and analysis tool",
                BaseUrl = GetAppUrl("GenericLogHandler"),
                AvailableRolesJson = "[\"ReadOnly\", \"User\", \"PowerUser\", \"Admin\"]"
            },
            new App
            {
                AppId = "ServerMonitorDashboard",
                DisplayName = "Server Monitor Dashboard",
                Description = "Server monitoring and alerting",
                BaseUrl = GetAppUrl("ServerMonitorDashboard"),
                AvailableRolesJson = "[\"ReadOnly\", \"User\", \"PowerUser\", \"Admin\"]"
            },
            new App
            {
                AppId = "DocView",
                DisplayName = "Doc View",
                Description = "Document viewing and management",
                BaseUrl = GetAppUrl("DocView"),
                AvailableRolesJson = "[\"ReadOnly\", \"User\", \"PowerUser\", \"Admin\"]"
            }
        };

        foreach (var app in apps)
        {
            if (!await _context.Apps.AnyAsync(a => a.AppId == app.AppId))
            {
                _context.Apps.Add(app);
                _logger.LogInformation("App registered: {AppId}", app.AppId);
            }
        }

        await _context.SaveChangesAsync();
    }

    /// <summary>
    /// Enforce the standard DedgeAuth app role model across all apps and permissions.
    /// Unknown/non-standard roles are mapped to User.
    /// </summary>
    private async Task NormalizeAllAppRolesAsync()
    {
        var apps = await _context.Apps.ToListAsync();
        foreach (var app in apps)
        {
            app.SetAvailableRoles(StandardAppRoles);
        }

        var permissions = await _context.AppPermissions.ToListAsync();
        foreach (var permission in permissions)
        {
            permission.Role = MapRoleToStandard(permission.Role);
        }

        await _context.SaveChangesAsync();
        _logger.LogInformation("Normalized app role definitions and permission roles to DedgeAuth standard set.");
    }

    /// <summary>
    /// Normalize localhost:PORT URLs to localhost-only (IIS virtual app format) and
    /// add any missing app routes to tenants. Does NOT auto-migrate to a specific server --
    /// that is handled by the admin UI "Update All" feature so the user stays in control.
    /// </summary>
    private async Task NormalizeLocalhostPortUrlsAsync()
    {
        var migrated = false;

        // Normalize app BaseUrl: "http://localhost:8110" -> "http://localhost/GenericLogHandler"
        var apps = await _context.Apps.ToListAsync();
        foreach (var app in apps)
        {
            if (string.IsNullOrEmpty(app.BaseUrl)) continue;

            // Only normalize localhost URLs that have an explicit port (old Kestrel-style)
            if (app.BaseUrl.Contains("localhost:"))
            {
                var newUrl = $"http://localhost/{app.AppId}";
                _logger.LogInformation("Normalizing app {AppId} BaseUrl: {OldUrl} -> {NewUrl}", app.AppId, app.BaseUrl, newUrl);
                app.BaseUrl = newUrl;
                migrated = true;
            }
        }

        // Normalize tenant appRouting and add any missing default routes
        var tenants = await _context.Tenants.ToListAsync();
        foreach (var tenant in tenants)
        {
            var routing = tenant.GetAppRouting() ?? new Dictionary<string, string>();
            var updated = false;

            // Normalize existing localhost:PORT entries
            var newRouting = new Dictionary<string, string>();
            foreach (var kvp in routing)
            {
                if (kvp.Value.Contains("localhost:"))
                {
                    var newUrl = $"http://localhost/{kvp.Key}";
                    _logger.LogInformation("Normalizing tenant {Domain} route {AppId}: {OldUrl} -> {NewUrl}",
                        tenant.Domain, kvp.Key, kvp.Value, newUrl);
                    newRouting[kvp.Key] = newUrl;
                    updated = true;
                }
                else
                {
                    newRouting[kvp.Key] = kvp.Value;
                }
            }

            // Add any missing apps from defaults
            var defaults = GetDefaultAppRouting();
            foreach (var kvp in defaults)
            {
                if (!newRouting.ContainsKey(kvp.Key))
                {
                    _logger.LogInformation("Adding missing app route for tenant {Domain}: {AppId} -> {Url}",
                        tenant.Domain, kvp.Key, kvp.Value);
                    newRouting[kvp.Key] = kvp.Value;
                    updated = true;
                }
            }

            if (updated)
            {
                tenant.SetAppRouting(newRouting);
                migrated = true;
            }
        }

        if (migrated)
        {
            await _context.SaveChangesAsync();
            _logger.LogInformation("Localhost URL normalization completed");
        }
    }

    private async Task SeedAdminUsersAsync()
    {
        var allApps = await _context.Apps.ToListAsync();

        foreach (var email in _config.AdminEmails ?? new List<string>())
        {
            var normalizedEmail = email.ToLowerInvariant();
            var user = await _context.Users.FirstOrDefaultAsync(u => u.Email.ToLower() == normalizedEmail);

            if (user == null)
            {
                // Resolve tenant
                var domain = email.Split('@').LastOrDefault()?.ToLower();
                var tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain.ToLower() == domain);

                user = new User
                {
                    Email = normalizedEmail,
                    DisplayName = email.Split('@')[0].Replace(".", " "),
                    GlobalAccessLevel = AccessLevel.Admin,
                    EmailVerified = true, // Pre-verified for seeded admins
                    TenantId = tenant?.Id
                };

                _context.Users.Add(user);
                _logger.LogInformation("Admin user seeded: {Email}", email);
            }

            // Ensure admin flags even for existing users.
            user.GlobalAccessLevel = AccessLevel.Admin;
            user.EmailVerified = true;
            user.IsActive = true;

            // Ensure app-level admin permission on ALL apps for configured admins.
            foreach (var app in allApps)
            {
                var existingPermission = await _context.AppPermissions
                    .FirstOrDefaultAsync(p => p.UserId == user.Id && p.AppId == app.Id);

                if (existingPermission == null)
                {
                    _context.AppPermissions.Add(new AppPermission
                    {
                        UserId = user.Id,
                        AppId = app.Id,
                        Role = "Admin",
                        GrantedBy = "System"
                    });
                }
                else
                {
                    existingPermission.Role = "Admin";
                    existingPermission.GrantedAt = DateTime.UtcNow;
                    existingPermission.GrantedBy = "System";
                }
            }
        }

        await _context.SaveChangesAsync();
        
        // Seed test user with known password for automated testing
        await SeedTestUserAsync();
    }
    
    private async Task SeedTestUserAsync()
    {
        const string testEmail = "test.service@Dedge.no";
        const string testPassword = "TestPass123!";
        
        if (!await _context.Users.AnyAsync(u => u.Email.ToLower() == testEmail))
        {
            var tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain.ToLower() == "Dedge.no");
            
            var user = new User
            {
                Email = testEmail,
                DisplayName = "Test Service User",
                GlobalAccessLevel = AccessLevel.Admin,
                EmailVerified = true,
                IsActive = true,
                TenantId = tenant?.Id,
                PasswordHash = BCrypt.Net.BCrypt.HashPassword(testPassword)
            };
            
            _context.Users.Add(user);
            await _context.SaveChangesAsync();
            
            // Assign admin role to all apps
            var allApps = await _context.Apps.ToListAsync();
            foreach (var app in allApps)
            {
                var permission = new AppPermission
                {
                    UserId = user.Id,
                    AppId = app.Id,
                    Role = "Admin",
                    GrantedBy = "System"
                };
                _context.AppPermissions.Add(permission);
            }
            await _context.SaveChangesAsync();
            
            _logger.LogInformation("Test user seeded: {Email} with password: {Password}", testEmail, testPassword);
        }
    }

    /// <summary>
    /// Ensures every existing user has permissions for every registered app.
    /// Missing permissions default to Admin role. Users below Admin access level
    /// are upgraded to Admin. Also ensures tenant assignment for orphaned users.
    /// Runs on every startup so new apps automatically get permissions for all users.
    /// </summary>
    private async Task EnsureAllUsersHaveFullPermissionsAsync()
    {
        var allApps = await _context.Apps.ToListAsync();
        if (allApps.Count == 0) return;

        var allUsers = await _context.Users
            .Include(u => u.AppPermissions)
            .ToListAsync();

        if (allUsers.Count == 0) return;

        var defaultTenant = await _context.Tenants.FirstOrDefaultAsync();
        var changes = 0;

        foreach (var user in allUsers)
        {
            // Ensure tenant assignment
            if (user.TenantId == null && defaultTenant != null)
            {
                user.TenantId = defaultTenant.Id;
                _logger.LogInformation("Assigned user {Email} to default tenant {Domain}",
                    user.Email, defaultTenant.Domain);
                changes++;
            }

            // Upgrade any user below Admin to Admin (per policy: "if in doubt, set to admin")
            if (user.GlobalAccessLevel != AccessLevel.Admin
                && user.GlobalAccessLevel != AccessLevel.TenantAdmin)
            {
                _logger.LogInformation("Upgrading user {Email} from {Old} to Admin (migration policy)",
                    user.Email, user.GlobalAccessLevel);
                user.GlobalAccessLevel = AccessLevel.Admin;
                changes++;
            }

            var existingAppIds = user.AppPermissions
                .Select(p => p.AppId)
                .ToHashSet();

            foreach (var app in allApps)
            {
                if (existingAppIds.Contains(app.Id))
                    continue;

                _context.AppPermissions.Add(new AppPermission
                {
                    UserId = user.Id,
                    AppId = app.Id,
                    Role = "Admin",
                    GrantedBy = "Migration"
                });
                _logger.LogInformation("Granted Admin on {AppId} to {Email} (migration)",
                    app.AppId, user.Email);
                changes++;
            }
        }

        if (changes > 0)
        {
            await _context.SaveChangesAsync();
            _logger.LogInformation("User migration completed: {Changes} changes across {Users} users and {Apps} apps",
                changes, allUsers.Count, allApps.Count);
        }
        else
        {
            _logger.LogDebug("All users already have full app permissions — no migration needed");
        }
    }

    private async Task SeedDefaultAppGroupsAsync()
    {
        var tenant = await _context.Tenants.FirstOrDefaultAsync(t => t.Domain == "Dedge.no");
        if (tenant == null) return;

        if (await _context.AppGroups.AnyAsync(g => g.TenantId == tenant.Id))
        {
            _logger.LogDebug("App groups already exist for Dedge.no — skipping seed");
            return;
        }

        var groups = new (string Name, string Slug, string? Description)[]
        {
            ("Infrastructure", "infrastructure", "Server infrastructure and monitoring tools"),
            ("Documents", "documents", "Document management and viewing"),
            ("Development", "development", "Developer tools and documentation"),
            ("Agriculture", "agriculture", "Agricultural business applications"),
        };

        var childGroups = new (string ParentSlug, string Name, string Slug, string? Description)[]
        {
            ("infrastructure", "Monitoring", "monitoring", "Server and service monitoring"),
            ("infrastructure", "Logging", "logging", "Log aggregation and analysis"),
        };

        foreach (var g in groups)
        {
            _context.AppGroups.Add(new AppGroup
            {
                TenantId = tenant.Id,
                Name = g.Name,
                Slug = g.Slug,
                Description = g.Description,
                SortOrder = Array.IndexOf(groups, g)
            });
        }
        await _context.SaveChangesAsync();

        foreach (var cg in childGroups)
        {
            var parent = await _context.AppGroups.FirstOrDefaultAsync(
                g => g.TenantId == tenant.Id && g.Slug == cg.ParentSlug);
            if (parent == null) continue;

            _context.AppGroups.Add(new AppGroup
            {
                TenantId = tenant.Id,
                Name = cg.Name,
                Slug = cg.Slug,
                Description = cg.Description,
                ParentId = parent.Id,
                SortOrder = Array.IndexOf(childGroups, cg)
            });
        }
        await _context.SaveChangesAsync();

        _logger.LogInformation("Seeded {Count} default app groups for Dedge.no", groups.Length + childGroups.Length);
    }
}
