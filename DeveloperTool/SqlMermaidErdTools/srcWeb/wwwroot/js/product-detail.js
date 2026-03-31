// Product detail page
let currentProduct = null;

document.addEventListener('DOMContentLoaded', async () => {
    await loadCatalog();
    await loadProductDetails();
});

async function loadProductDetails() {
    const urlParams = new URLSearchParams(window.location.search);
    const productId = urlParams.get('id');
    
    if (!productId) {
        window.location.href = '/products.html';
        return;
    }

    try {
        const response = await fetch(`${API_BASE}/products/${productId}`);
        if (!response.ok) {
            throw new Error('Product not found');
        }
        
        currentProduct = await response.json();
        displayProductDetails(currentProduct);
        displayPricingTable(currentProduct);
    } catch (error) {
        console.error('Failed to load product:', error);
        document.getElementById('product-details').innerHTML = 
            '<p class="loading">Product not found</p>';
    }
}

function displayProductDetails(product) {
    // Update header
    const headerContent = document.getElementById('product-header-content');
    headerContent.innerHTML = `
        <div style="display: flex; align-items: center; gap: 2rem; max-width: 800px; margin: 0 auto;">
            <img src="${product.icon}" alt="${product.name}" style="width: 100px; height: 100px; object-fit: contain;" onerror="this.style.display='none'">
            <div>
                <div style="font-size: 0.875rem; font-weight: 600; text-transform: uppercase; margin-bottom: 0.5rem; opacity: 0.9;">${product.category}</div>
                <h1 style="font-size: 2.5rem; margin-bottom: 0.5rem;">${product.name}</h1>
                <p style="font-size: 1.25rem; opacity: 0.95;">${product.shortDescription}</p>
            </div>
        </div>
    `;

    // Update details
    const detailsContainer = document.getElementById('product-details');
    const allFeatures = [];
    Object.entries(product.features).forEach(([tier, features]) => {
        if (features && Array.isArray(features)) {
            allFeatures.push(...features);
        }
    });
    const uniqueFeatures = [...new Set(allFeatures)];

    detailsContainer.innerHTML = `
        <div style="max-width: 900px; margin: 0 auto;">
            <h2 style="font-size: 2rem; margin-bottom: 1rem;">About This Product</h2>
            <p style="font-size: 1.125rem; color: var(--text-secondary); margin-bottom: 2rem;">${product.fullDescription}</p>
            
            <h3 style="font-size: 1.5rem; margin-bottom: 1rem;">Key Features</h3>
            <ul style="list-style: none; display: grid; grid-template-columns: repeat(auto-fit, minmax(300px, 1fr)); gap: 1rem;">
                ${uniqueFeatures.map(feature => `
                    <li style="display: flex; align-items: flex-start; gap: 0.75rem;">
                        <span style="color: var(--success-color); font-weight: 700; flex-shrink: 0;">✓</span>
                        <span>${feature}</span>
                    </li>
                `).join('')}
            </ul>

            <div style="margin-top: 2rem; padding-top: 2rem; border-top: 1px solid var(--border-color); display: flex; gap: 2rem; flex-wrap: wrap;">
                <div>
                    <div style="font-size: 0.875rem; color: var(--text-secondary);">Version</div>
                    <div style="font-size: 1.25rem; font-weight: 600;">${product.metadata.version}</div>
                </div>
                <div>
                    <div style="font-size: 0.875rem; color: var(--text-secondary);">Downloads</div>
                    <div style="font-size: 1.25rem; font-weight: 600;">${product.metadata.downloads.toLocaleString()}</div>
                </div>
                <div>
                    <div style="font-size: 0.875rem; color: var(--text-secondary);">Rating</div>
                    <div style="font-size: 1.25rem; font-weight: 600;">⭐ ${product.metadata.rating} (${product.metadata.reviewCount} reviews)</div>
                </div>
                <div>
                    <div style="font-size: 0.875rem; color: var(--text-secondary);">Last Updated</div>
                    <div style="font-size: 1.25rem; font-weight: 600;">${new Date(product.metadata.lastUpdated).toLocaleDateString()}</div>
                </div>
            </div>

            ${product.links.github || product.links.apiPortal ? `
                <div style="margin-top: 2rem;">
                    ${product.links.apiPortal ? `<a href="${product.links.apiPortal}" class="btn btn-primary">🔑 API Access Portal</a>` : ''}
                    ${product.links.github ? `<a href="${product.links.github}" target="_blank" class="btn btn-outline" style="${product.links.apiPortal ? 'margin-left: 1rem;' : ''}">View on GitHub</a>` : ''}
                    ${product.links.documentation ? `<a href="${product.links.documentation}" target="_blank" class="btn btn-outline" style="margin-left: 1rem;">Documentation</a>` : ''}
                </div>
            ` : ''}
        </div>
    `;
}

function displayPricingTable(product) {
    const pricingContainer = document.getElementById('pricing-table');
    const tiers = ['free', 'pro', 'enterprise'];
    
    const pricingHTML = tiers.map(tier => {
        const pricing = product.pricing[tier];
        if (!pricing) return '';

        const features = product.features[tier] || [];
        const isFeatured = tier === 'pro';
        
        return `
            <div class="pricing-column ${isFeatured ? 'featured' : ''}">
                ${isFeatured ? '<div class="featured-badge">Popular</div>' : ''}
                
                <div class="pricing-header">
                    <div class="pricing-tier-name">${pricing.label}</div>
                    <div class="pricing-price">
                        ${pricing.price === 0 ? 'FREE' : `$${pricing.price}`}
                    </div>
                    ${pricing.price > 0 ? `<div class="pricing-period">/ ${pricing.billingPeriod}</div>` : ''}
                </div>
                
                <ul class="pricing-features">
                    ${features.map(feature => `<li>${feature}</li>`).join('')}
                    ${pricing.limitations && pricing.limitations.length > 0 ? 
                        pricing.limitations.map(limit => `<li class="limitation">${limit}</li>`).join('')
                    : ''}
                </ul>
                
                <div class="pricing-action">
                    ${generateActionButton(product.id, tier, pricing)}
                </div>
            </div>
        `;
    }).filter(html => html).join('');

    pricingContainer.innerHTML = pricingHTML;
}

function generateActionButton(productId, tier, pricing) {
    if (pricing.downloadUrl) {
        return `<a href="${pricing.downloadUrl}" target="_blank" class="btn btn-${tier === 'free' ? 'success' : 'primary'}" style="width: 100%;">${pricing.action}</a>`;
    } else if (pricing.contactEmail) {
        return `<a href="mailto:${pricing.contactEmail}" class="btn btn-outline" style="width: 100%;">${pricing.action}</a>`;
    } else if (pricing.stripePriceId) {
        return `<button onclick="initiateCheckout('${productId}', '${tier}')" class="btn btn-primary" style="width: 100%;">${pricing.action}</button>`;
    } else {
        return `<button class="btn btn-outline" style="width: 100%;" disabled>${pricing.action}</button>`;
    }
}

