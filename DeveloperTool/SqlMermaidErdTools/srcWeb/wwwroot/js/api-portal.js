// API Portal functionality
const API_BASE = 'http://localhost:5001/api/v1';
let currentProduct = null;
let currentApiKey = null;

document.addEventListener('DOMContentLoaded', async () => {
    await loadProductInfo();
    await loadApiKeySection();
    await loadRateLimits();
});

async function loadProductInfo() {
    const urlParams = new URLSearchParams(window.location.search);
    const productId = urlParams.get('product');
    
    if (productId && catalogData) {
        currentProduct = catalogData.products.find(p => p.id === productId);
        if (currentProduct) {
            document.getElementById('product-subtitle').textContent = 
                `${currentProduct.name} - RESTful API Access`;
        }
    }
}

async function loadApiKeySection() {
    const container = document.getElementById('api-key-section');
    
    // Check if user has an API key in localStorage
    const storedKey = localStorage.getItem('apiKey');
    
    if (storedKey) {
        currentApiKey = storedKey;
        await displayApiKeyInfo(storedKey);
    } else {
        displayApiKeyGenerator();
    }
}

async function displayApiKeyInfo(apiKey) {
    const container = document.getElementById('api-key-section');
    
    try {
        // Try to get key info from API
        const response = await fetch(`${API_BASE}/auth/key-info`, {
            headers: {
                'X-API-Key': apiKey
            }
        });

        if (response.ok) {
            const info = await response.json();
            container.innerHTML = `
                <div class="api-key-display">
                    <div class="key-status active">
                        <span>✓</span>
                        <span>Active - ${info.tier} Tier</span>
                    </div>
                    <div class="api-key-value">${apiKey}</div>
                    <p style="color: var(--text-secondary); margin: 0.5rem 0;">
                        <strong>Email:</strong> ${info.email}<br>
                        <strong>Table Limit:</strong> ${info.tableLimit === 2147483647 ? 'Unlimited' : info.tableLimit}<br>
                        <strong>Daily Requests:</strong> ${info.requestsToday} / ${info.dailyLimit}<br>
                        <strong>Expires:</strong> ${new Date(info.expiresAt).toLocaleDateString()}
                    </p>
                    <div class="api-key-actions">
                        <button class="btn btn-primary" onclick="copyApiKey()">Copy API Key</button>
                        <button class="btn btn-outline" onclick="revokeApiKey()">Revoke Key</button>
                    </div>
                </div>
                <p style="color: var(--text-secondary); font-size: 0.875rem;">
                    ⚠️ Keep your API key secure. Do not share it or commit it to version control.
                </p>
            `;
        } else {
            // Key is invalid
            localStorage.removeItem('apiKey');
            displayApiKeyGenerator();
        }
    } catch (error) {
        console.error('Failed to fetch API key info:', error);
        container.innerHTML = `
            <div class="api-key-display">
                <div class="api-key-value">${apiKey}</div>
                <p style="color: var(--danger-color);">⚠️ Unable to verify API key. The API service may be offline.</p>
                <div class="api-key-actions">
                    <button class="btn btn-primary" onclick="copyApiKey()">Copy API Key</button>
                    <button class="btn btn-outline" onclick="revokeApiKey()">Revoke Key</button>
                </div>
            </div>
        `;
    }
}

function displayApiKeyGenerator() {
    const container = document.getElementById('api-key-section');
    container.innerHTML = `
        <div class="api-key-generator">
            <h3>Generate Your API Key</h3>
            <p>To use the REST API, you need to generate an API key linked to your license.</p>
            
            <div class="form-group">
                <label>Email Address:</label>
                <input type="email" id="gen-email" class="form-input" placeholder="your@email.com" required>
            </div>
            
            <div class="form-group">
                <label>License Key:</label>
                <input type="text" id="gen-license" class="form-input" placeholder="SQLMMD-PRO-XXXX-XXXX-XXXX" required>
                <p style="font-size: 0.875rem; color: var(--text-secondary); margin-top: 0.5rem;">
                    Enter your Pro or Enterprise license key. For Free tier, use: <code>SQLMMD-FREE-TRIAL</code>
                </p>
            </div>
            
            <button class="btn btn-primary" onclick="generateApiKey()">Generate API Key</button>
            
            <div id="gen-error" style="display: none; margin-top: 1rem; padding: 1rem; background: #fee2e2; border-radius: 0.5rem; color: #991b1b;"></div>
        </div>
    `;
}

async function generateApiKey() {
    const email = document.getElementById('gen-email').value;
    const license = document.getElementById('gen-license').value;
    const errorDiv = document.getElementById('gen-error');
    
    if (!email || !license) {
        errorDiv.textContent = 'Please provide both email and license key.';
        errorDiv.style.display = 'block';
        return;
    }
    
    errorDiv.style.display = 'none';
    
    try {
        const response = await fetch(`${API_BASE}/auth/create-api-key`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                email: email,
                licenseKey: license
            })
        });
        
        if (response.ok) {
            const data = await response.json();
            localStorage.setItem('apiKey', data.apiKey);
            currentApiKey = data.apiKey;
            await displayApiKeyInfo(data.apiKey);
            alert('API Key generated successfully!');
        } else {
            const error = await response.json();
            errorDiv.textContent = error.error || 'Failed to generate API key';
            errorDiv.style.display = 'block';
        }
    } catch (error) {
        errorDiv.textContent = 'Failed to connect to API service. Make sure the REST API is running at ' + API_BASE;
        errorDiv.style.display = 'block';
    }
}

function copyApiKey() {
    if (currentApiKey) {
        navigator.clipboard.writeText(currentApiKey);
        alert('API key copied to clipboard!');
    }
}

function revokeApiKey() {
    if (confirm('Are you sure you want to revoke this API key? You will need to generate a new one.')) {
        localStorage.removeItem('apiKey');
        currentApiKey = null;
        displayApiKeyGenerator();
    }
}

async function loadRateLimits() {
    const container = document.getElementById('rate-limits-table');
    
    if (!currentProduct || !currentProduct.apiAccess) {
        container.innerHTML = '<p>No API access information available for this product.</p>';
        return;
    }
    
    const tiers = currentProduct.apiAccess.tiers;
    
    container.innerHTML = `
        <div class="rate-limits-grid">
            ${Object.entries(tiers).map(([tierName, limits]) => `
                <div class="rate-limit-card">
                    <h3>${tierName.charAt(0).toUpperCase() + tierName.slice(1)} Tier</h3>
                    <div class="rate-limit-item">
                        <span class="rate-limit-label">Table Limit</span>
                        <span class="rate-limit-value">${limits.tableLimit}</span>
                    </div>
                    <div class="rate-limit-item">
                        <span class="rate-limit-label">Daily Requests</span>
                        <span class="rate-limit-value">${limits.dailyRequests.toLocaleString()}</span>
                    </div>
                    <div class="rate-limit-item">
                        <span class="rate-limit-label">Rate/Minute</span>
                        <span class="rate-limit-value">${limits.ratePerMinute}/min</span>
                    </div>
                </div>
            `).join('')}
        </div>
    `;
}

function copyCode(elementId) {
    const code = document.getElementById(elementId).textContent;
    navigator.clipboard.writeText(code);
    
    // Show feedback
    const btn = event.target;
    const originalText = btn.textContent;
    btn.textContent = 'Copied!';
    setTimeout(() => {
        btn.textContent = originalText;
    }, 2000);
}

async function testApiCall() {
    const apiKey = document.getElementById('test-api-key').value;
    const endpoint = document.getElementById('test-endpoint').value;
    const body = document.getElementById('test-body').value;
    const outputDiv = document.getElementById('test-output');
    const resultPre = document.getElementById('test-result');
    
    if (!apiKey) {
        alert('Please enter your API key');
        return;
    }
    
    let requestBody;
    try {
        requestBody = JSON.parse(body);
    } catch (error) {
        alert('Invalid JSON in request body');
        return;
    }
    
    const url = `${API_BASE}/conversion/${endpoint}`;
    
    outputDiv.style.display = 'block';
    resultPre.textContent = 'Sending request...';
    
    try {
        const response = await fetch(url, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json',
                'X-API-Key': apiKey
            },
            body: JSON.stringify(requestBody)
        });
        
        const result = await response.json();
        resultPre.textContent = JSON.stringify(result, null, 2);
    } catch (error) {
        resultPre.textContent = `Error: ${error.message}\n\nMake sure the REST API is running at ${API_BASE}`;
    }
}

