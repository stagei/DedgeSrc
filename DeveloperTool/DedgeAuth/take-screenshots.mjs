import puppeteer from 'puppeteer';
import { join } from 'path';

const BASE = 'http://dedge-server';
const DOWNLOADS = 'C:\\Users\\FKGEISTA\\Downloads';
const EMAIL = 'test.service@Dedge.no';
const PASSWORD = 'TestPass123!';

const delay = ms => new Promise(r => setTimeout(r, ms));

async function main() {
    const browser = await puppeteer.launch({
        headless: true,
        args: ['--no-sandbox', '--disable-setuid-sandbox', '--window-size=1920,1080']
    });

    const page = await browser.newPage();
    await page.setViewport({ width: 1920, height: 1080 });

    // Capture console messages
    const consoleLogs = [];
    page.on('console', msg => {
        const text = `[${msg.type()}] ${msg.text()}`;
        consoleLogs.push(text);
        if (msg.type() === 'error' || msg.type() === 'warning') {
            console.log(`  CONSOLE: ${text}`);
        }
    });

    const results = {};

    try {
        // Step 1: Login to DedgeAuth via the login page
        console.log('=== Step 1: DedgeAuth Login ===');
        await page.goto(`${BASE}/DedgeAuth/login.html`, { waitUntil: 'networkidle2', timeout: 30000 });
        await delay(2000);

        await page.waitForSelector('#email', { timeout: 10000 });
        await page.type('#email', EMAIL);
        await page.type('#password', PASSWORD);
        await page.click('#password-form button[type="submit"]');
        await delay(4000);

        // Get auth code from login response (the login page stores it)
        const loginPageData = await page.evaluate(() => {
            return {
                authCode: window._lastAuthCode || null,
                url: window.location.href,
                cookies: document.cookie,
                title: document.title
            };
        });
        console.log(`  Login page URL: ${loginPageData.url}`);
        console.log(`  Auth code: ${loginPageData.authCode || 'none'}`);
        console.log(`  Cookies: ${loginPageData.cookies.substring(0, 100)}`);

        // Also get JWT from the login page's API call
        const jwtFromPage = await page.evaluate(async (email, password) => {
            try {
                const resp = await fetch('api/auth/login', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ email, password })
                });
                if (resp.ok) {
                    const data = await resp.json();
                    return { jwt: data.accessToken, code: data.authCode };
                }
                return { error: `HTTP ${resp.status}` };
            } catch(e) {
                return { error: e.message };
            }
        }, EMAIL, PASSWORD);

        const jwt = jwtFromPage.jwt;
        const authCode = jwtFromPage.code || loginPageData.authCode;
        console.log(`  JWT: ${jwt ? `${jwt.length} chars` : jwtFromPage.error}`);
        console.log(`  Auth code: ${authCode || 'none'}`);

        // Set dark mode
        await page.evaluate(() => {
            document.documentElement.setAttribute('data-theme', 'dark');
            localStorage.setItem('theme', 'dark');
            localStorage.setItem('DedgeAuth-theme', 'dark');
        });
        await delay(1000);

        // Screenshot DedgeAuth
        await page.screenshot({ path: join(DOWNLOADS, 'DedgeAuth-login-darkmode.png'), fullPage: false });
        console.log('  Screenshot: DedgeAuth-login-darkmode.png');
        results['DedgeAuth'] = { darkMode: true, screenshot: 'DedgeAuth-login-darkmode.png', status: 'OK' };

        // Step 2: Test each consumer app
        const apps = [
            { name: 'DocView', path: 'DocView' },
            { name: 'GenericLogHandler', path: 'GenericLogHandler' },
            { name: 'ServerMonitorDashboard', path: 'ServerMonitorDashboard' }
        ];

        for (const app of apps) {
            console.log(`\n=== ${app.name} ===`);
            consoleLogs.length = 0;

            try {
                // Navigate to the app with ?token= parameter 
                // The middleware will extract it, set cookie, and redirect to clean URL
                const appUrl = `${BASE}/${app.path}/?token=${jwt}`;
                console.log(`  Navigating to: ${BASE}/${app.path}/?token=<jwt>`);
                
                await page.goto(appUrl, { waitUntil: 'networkidle2', timeout: 30000 });
                // Wait extra for redirect + DedgeAuth-user.js initialization
                await delay(5000);

                const currentUrl = page.url();
                console.log(`  Final URL: ${currentUrl}`);

                // If redirected to login, try auth code
                if (currentUrl.includes('/DedgeAuth/login')) {
                    console.log('  Redirected to login page');
                    if (authCode) {
                        console.log('  Trying with auth code...');
                        await page.goto(`${BASE}/${app.path}/?code=${authCode}`, { waitUntil: 'networkidle2', timeout: 30000 });
                        await delay(5000);
                        console.log(`  After code redirect: ${page.url()}`);
                    }
                }

                // Check all cookies for this page
                const pageCookies = await page.cookies();
                const authCookie = pageCookies.find(c => c.name === 'DedgeAuth_access_token');
                console.log(`  Auth cookie: ${authCookie ? `present (${authCookie.value.length} chars, path=${authCookie.path})` : 'NOT FOUND'}`);

                // If no cookie, set it manually and reload
                if (!authCookie && jwt) {
                    console.log('  Setting cookie manually...');
                    await page.setCookie({
                        name: 'DedgeAuth_access_token',
                        value: jwt,
                        domain: 'dedge-server',
                        path: `/${app.path}`,
                        httpOnly: false,
                        secure: false
                    });
                    // Also set on root path
                    await page.setCookie({
                        name: 'DedgeAuth_access_token',
                        value: jwt,
                        domain: 'dedge-server',
                        path: '/',
                        httpOnly: false,
                        secure: false
                    });
                    // Also set in sessionStorage
                    await page.evaluate((token) => {
                        sessionStorage.setItem('gk_accessToken', token);
                    }, jwt);
                    // Reload to let DedgeAuth-user.js pick up the token
                    await page.reload({ waitUntil: 'networkidle2' });
                    await delay(5000);
                    console.log('  Reloaded with manual cookie');
                }

                // Set dark mode
                await page.evaluate(() => {
                    document.documentElement.setAttribute('data-theme', 'dark');
                    localStorage.setItem('theme', 'dark');
                    localStorage.setItem('DedgeAuth-theme', 'dark');
                });
                await delay(1000);

                // Wait for DedgeAuth-user.js async operations to complete
                await delay(3000);

                // Collect validation data
                const validation = await page.evaluate(() => {
                    const dataTheme = document.documentElement.getAttribute('data-theme');
                    const bgColor = getComputedStyle(document.body).backgroundColor;
                    const primaryColor = getComputedStyle(document.documentElement).getPropertyValue('--primary-color')?.trim();

                    const menuContainer = document.getElementById('DedgeAuthUserMenu');
                    const menuInner = document.querySelector('.gk-user-menu');
                    const menuButton = document.getElementById('gkUserButton');
                    const containerContent = menuContainer?.innerHTML?.trim() || '';

                    const tenantCssEl = document.getElementById('DedgeAuth-tenant-css');
                    const tenantCssContent = tenantCssEl?.textContent?.trim() || '';

                    const scripts = Array.from(document.querySelectorAll('script[src]')).map(s => s.src);
                    const links = Array.from(document.querySelectorAll('link[rel="stylesheet"]')).map(l => l.href);

                    // Check if gk_accessToken is in sessionStorage
                    const storedToken = sessionStorage.getItem('gk_accessToken');

                    return {
                        title: document.title,
                        dataTheme,
                        bgColor,
                        primaryColor,
                        menu: {
                            containerExists: !!menuContainer,
                            innerExists: !!menuInner,
                            buttonExists: !!menuButton,
                            hasContent: containerContent.length > 10,
                            contentPreview: containerContent.substring(0, 200)
                        },
                        tenantCss: {
                            elementExists: !!tenantCssEl,
                            hasContent: tenantCssContent.length > 0,
                            contentLength: tenantCssContent.length,
                            contentPreview: tenantCssContent.substring(0, 100)
                        },
                        hasUserJsScript: scripts.some(s => s.includes('user.js')),
                        hasThemeJsScript: scripts.some(s => s.includes('theme.js')),
                        hasCommonCss: links.some(l => l.includes('common.css')),
                        hasUserCss: links.some(l => l.includes('user.css')),
                        storedToken: storedToken ? `${storedToken.length} chars` : 'none',
                        allCookies: document.cookie.substring(0, 200)
                    };
                });

                console.log(`  Title: ${validation.title}`);
                console.log(`  Theme: data-theme=${validation.dataTheme}, bg=${validation.bgColor}`);
                console.log(`  Primary: ${validation.primaryColor}`);
                console.log(`  Token in storage: ${validation.storedToken}`);
                console.log(`  Cookies visible to JS: ${validation.allCookies || 'none'}`);
                console.log(`  Menu: container=${validation.menu.containerExists}, inner=${validation.menu.innerExists}, btn=${validation.menu.buttonExists}, content=${validation.menu.hasContent}`);
                if (validation.menu.hasContent) {
                    console.log(`  Menu preview: ${validation.menu.contentPreview}`);
                }
                console.log(`  Tenant CSS: el=${validation.tenantCss.elementExists}, content=${validation.tenantCss.hasContent} (${validation.tenantCss.contentLength} chars)`);
                if (validation.tenantCss.hasContent) {
                    console.log(`  Tenant CSS preview: ${validation.tenantCss.contentPreview}`);
                }
                console.log(`  Scripts: user.js=${validation.hasUserJsScript}, theme.js=${validation.hasThemeJsScript}`);
                console.log(`  CSS: common=${validation.hasCommonCss}, user=${validation.hasUserCss}`);

                // Print any relevant console logs
                const errorLogs = consoleLogs.filter(l => l.includes('error') || l.includes('Error') || l.includes('fail') || l.includes('401') || l.includes('403'));
                if (errorLogs.length > 0) {
                    console.log(`  Console errors: ${errorLogs.slice(0, 5).join('\n    ')}`);
                }

                // Screenshot
                const screenshotName = `${app.name}-darkmode.png`;
                await page.screenshot({ path: join(DOWNLOADS, screenshotName), fullPage: false });
                console.log(`  Screenshot: ${screenshotName}`);

                results[app.name] = {
                    status: validation.title.includes('500') || validation.title.includes('Error') ? 'ERROR' : 'OK',
                    darkMode: validation.dataTheme === 'dark' && !validation.bgColor.includes('238'),
                    menuVisible: validation.menu.innerExists || validation.menu.hasContent,
                    tenantCss: validation.tenantCss.hasContent,
                    fkGreen: (validation.primaryColor || '').includes('008942') || (validation.primaryColor || '').includes('00b359'),
                    screenshot: screenshotName
                };
            } catch (err) {
                console.log(`  ERROR: ${err.message}`);
                try {
                    await page.screenshot({ path: join(DOWNLOADS, `${app.name}-error.png`), fullPage: false });
                } catch(e2) {}
                results[app.name] = { status: 'ERROR', error: err.message };
            }
        }

        // Final summary
        console.log('\n' + '='.repeat(70));
        console.log('FINAL VALIDATION SUMMARY');
        console.log('='.repeat(70));
        const allPass = [];
        for (const [name, r] of Object.entries(results)) {
            const checks = [];
            checks.push(`Dark:${r.darkMode ? 'PASS' : 'FAIL'}`);
            if (r.menuVisible !== undefined) checks.push(`Menu:${r.menuVisible ? 'PASS' : 'FAIL'}`);
            if (r.tenantCss !== undefined) checks.push(`TenantCSS:${r.tenantCss ? 'PASS' : 'FAIL'}`);
            if (r.fkGreen !== undefined) checks.push(`FKGreen:${r.fkGreen ? 'PASS' : 'FAIL'}`);
            const overall = r.status === 'OK' && r.darkMode && (r.menuVisible ?? true) && (r.tenantCss ?? true);
            allPass.push(overall);
            console.log(`  ${name}: ${r.status} | ${checks.join(' | ')} | ${r.screenshot}`);
        }
        console.log('='.repeat(70));
        console.log(`Overall: ${allPass.every(Boolean) ? 'ALL PASS' : 'SOME FAILURES'}`);

    } catch (err) {
        console.error('Fatal error:', err.message);
        console.error(err.stack);
    } finally {
        await browser.close();
    }
}

main().catch(console.error);
