import puppeteer from 'puppeteer';

const BASE = 'http://dedge-server';
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

    // Capture all network requests and responses
    const requests404 = [];
    page.on('response', response => {
        if (response.status() >= 400) {
            requests404.push({ url: response.url(), status: response.status() });
        }
    });

    page.on('console', msg => {
        if (msg.type() === 'error' || msg.type() === 'warning') {
            console.log(`  [${msg.type()}] ${msg.text()}`);
        }
    });

    try {
        // Login to get JWT
        console.log('=== Login ===');
        await page.goto(`${BASE}/DedgeAuth/login.html`, { waitUntil: 'networkidle2', timeout: 30000 });
        await delay(1000);

        await page.waitForSelector('#email', { timeout: 10000 });
        await page.type('#email', EMAIL);
        await page.type('#password', PASSWORD);
        await page.click('#password-form button[type="submit"]');
        await delay(3000);

        // Get JWT from page context
        const jwt = await page.evaluate(async (email, password) => {
            const resp = await fetch('api/auth/login', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({ email, password })
            });
            const data = await resp.json();
            return data.accessToken;
        }, EMAIL, PASSWORD);
        console.log(`JWT: ${jwt?.length} chars`);

        // Test DocView
        console.log('\n=== DocView - Network Debug ===');
        requests404.length = 0;
        
        // Set cookie first
        await page.setCookie({
            name: 'DedgeAuth_access_token',
            value: jwt,
            domain: 'dedge-server',
            path: '/DocView',
            httpOnly: false,
            secure: false
        });

        await page.goto(`${BASE}/DocView/`, { waitUntil: 'networkidle2', timeout: 30000 });
        await delay(5000);

        console.log(`  Final URL: ${page.url()}`);
        console.log(`  Failed requests:`);
        for (const r of requests404) {
            console.log(`    ${r.status}: ${r.url}`);
        }

        // Check if the DedgeAuth/me endpoint works from this page's context
        const meResult = await page.evaluate(async () => {
            const token = sessionStorage.getItem('gk_accessToken') || document.cookie.match(/DedgeAuth_access_token=([^;]*)/)?.[1];
            const headers = { 'Content-Type': 'application/json' };
            if (token) headers['Authorization'] = `Bearer ${token}`;
            
            try {
                const resp = await fetch('api/DedgeAuth/me', { headers });
                return { status: resp.status, url: resp.url, body: await resp.text() };
            } catch(e) {
                return { error: e.message };
            }
        });
        console.log(`\n  Manual api/DedgeAuth/me call:`);
        console.log(`    Status: ${meResult.status}`);
        console.log(`    URL: ${meResult.url}`);
        console.log(`    Body: ${(meResult.body || meResult.error || '').substring(0, 200)}`);

        // Test GenericLogHandler
        console.log('\n=== GenericLogHandler - Network Debug ===');
        requests404.length = 0;
        
        await page.setCookie({
            name: 'DedgeAuth_access_token',
            value: jwt,
            domain: 'dedge-server',
            path: '/GenericLogHandler',
            httpOnly: false,
            secure: false
        });

        await page.goto(`${BASE}/GenericLogHandler/`, { waitUntil: 'networkidle2', timeout: 30000 });
        await delay(5000);

        console.log(`  Final URL: ${page.url()}`);
        console.log(`  Failed requests:`);
        for (const r of requests404) {
            console.log(`    ${r.status}: ${r.url}`);
        }

        const meResult2 = await page.evaluate(async () => {
            const token = sessionStorage.getItem('gk_accessToken') || document.cookie.match(/DedgeAuth_access_token=([^;]*)/)?.[1];
            const headers = { 'Content-Type': 'application/json' };
            if (token) headers['Authorization'] = `Bearer ${token}`;
            
            try {
                const resp = await fetch('api/DedgeAuth/me', { headers });
                return { status: resp.status, url: resp.url, body: await resp.text() };
            } catch(e) {
                return { error: e.message };
            }
        });
        console.log(`\n  Manual api/DedgeAuth/me call:`);
        console.log(`    Status: ${meResult2.status}`);
        console.log(`    URL: ${meResult2.url}`);
        console.log(`    Body: ${(meResult2.body || meResult2.error || '').substring(0, 200)}`);

    } catch (err) {
        console.error('Fatal:', err.message);
    } finally {
        await browser.close();
    }
}

main().catch(console.error);
