// Global API base URL
const API_BASE = '/api';

// Global catalog data
let catalogData = null;

// Load catalog on page load
document.addEventListener('DOMContentLoaded', async () => {
    await loadCatalog();
    initializePage();
});

// Load catalog from API
async function loadCatalog() {
    try {
        const response = await fetch(`${API_BASE}/products`);
        catalogData = await response.json();
        console.log('Catalog loaded:', catalogData);
        return catalogData;
    } catch (error) {
        console.error('Failed to load catalog:', error);
        return null;
    }
}

// Initialize page-specific functionality
function initializePage() {
    const path = window.location.pathname;
    
    if (path === '/' || path === '/index.html') {
        initHomePage();
    }
}

// Initialize home page
async function initHomePage() {
    // Update stats
    if (catalogData) {
        const totalDownloads = catalogData.products.reduce((sum, p) => sum + (p.metadata.downloads || 0), 0);
        document.getElementById('total-downloads').textContent = totalDownloads.toLocaleString();
        document.getElementById('total-products').textContent = catalogData.products.length;
    }

    // Load featured products
    await loadFeaturedProducts();
}

// Load featured products
async function loadFeaturedProducts() {
    const container = document.getElementById('featured-products-grid');
    if (!container) return;

    try {
        const response = await fetch(`${API_BASE}/products/featured`);
        const data = await response.json();
        
        if (data.products && data.products.length > 0) {
            container.innerHTML = data.products.map(product => createProductCard(product)).join('');
        } else {
            container.innerHTML = '<p class="loading">No featured products available</p>';
        }
    } catch (error) {
        console.error('Failed to load featured products:', error);
        container.innerHTML = '<p class="loading">Failed to load products</p>';
    }
}

// Create product card HTML
function createProductCard(product) {
    const tiers = Object.keys(product.pricing).filter(t => product.pricing[t] !== null);
    const lowestPaidTier = tiers.find(t => product.pricing[t].price > 0);
    const pricing = lowestPaidTier ? product.pricing[lowestPaidTier] : product.pricing.free;
    
    const priceDisplay = pricing.price === 0 
        ? `<span class="price-free">FREE</span>`
        : `<span class="price-amount">$${pricing.price}</span>
           <span class="price-period">/ ${pricing.billingPeriod}</span>`;
    
    const tierBadges = tiers.map(tier => 
        `<span class="tier-badge tier-${tier}">${tier}</span>`
    ).join('');

    return `
        <div class="product-card" onclick="viewProduct('${product.id}')">
            ${product.isFeatured ? '<div class="featured-badge">Featured</div>' : ''}
            <img src="${product.icon}" alt="${product.name}" class="product-icon" onerror="this.style.display='none'">
            <div class="product-category">${product.category}</div>
            <h3 class="product-name">${product.name}</h3>
            <p class="product-description">${product.shortDescription}</p>
            <div class="product-tiers">${tierBadges}</div>
            <div class="product-price">${priceDisplay}</div>
            <button class="btn btn-primary" style="width: 100%;">View Details</button>
            <div class="product-meta">
                <span>⬇️ ${product.metadata.downloads.toLocaleString()}</span>
                <span>⭐ ${product.metadata.rating}</span>
            </div>
        </div>
    `;
}

// View product details
function viewProduct(productId) {
    window.location.href = `/product.html?id=${productId}`;
}

// Show search modal
function showSearch() {
    const modal = document.getElementById('search-modal');
    modal.style.display = 'flex';
    document.getElementById('search-input').focus();
    
    // Set up search input handler
    const searchInput = document.getElementById('search-input');
    searchInput.addEventListener('input', debounce(performSearch, 300));
}

// Hide search modal
function hideSearch() {
    document.getElementById('search-modal').style.display = 'none';
    document.getElementById('search-input').value = '';
    document.getElementById('search-results').innerHTML = '';
}

// Perform search
async function performSearch(event) {
    const query = event.target.value;
    const resultsContainer = document.getElementById('search-results');
    
    if (!query || query.length < 2) {
        resultsContainer.innerHTML = '';
        return;
    }
    
    try {
        const response = await fetch(`${API_BASE}/products/search?q=${encodeURIComponent(query)}`);
        const data = await response.json();
        
        if (data.products && data.products.length > 0) {
            resultsContainer.innerHTML = `
                <h3>Search Results (${data.products.length})</h3>
                <div class="products-grid" style="margin-top: 1rem;">
                    ${data.products.map(product => createProductCard(product)).join('')}
                </div>
            `;
        } else {
            resultsContainer.innerHTML = '<p class="loading">No products found</p>';
        }
    } catch (error) {
        console.error('Search failed:', error);
        resultsContainer.innerHTML = '<p class="loading">Search failed</p>';
    }
}

// Debounce function
function debounce(func, wait) {
    let timeout;
    return function executedFunction(...args) {
        const later = () => {
            clearTimeout(timeout);
            func.apply(this, args);
        };
        clearTimeout(timeout);
        timeout = setTimeout(later, wait);
    };
}

// Close modal on outside click
window.onclick = function(event) {
    const modal = document.getElementById('search-modal');
    if (event.target === modal) {
        hideSearch();
    }
}

// Stripe Checkout
async function initiateCheckout(productId, tier) {
    const email = prompt('Enter your email address:');
    if (!email) return;

    try {
        const response = await fetch(`${API_BASE}/checkout/create-session`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                productId,
                tier,
                email
            })
        });

        const data = await response.json();
        
        if (data.checkoutUrl) {
            // In production, this would redirect to Stripe Checkout
            window.location.href = data.checkoutUrl;
        } else {
            alert('Failed to create checkout session');
        }
    } catch (error) {
        console.error('Checkout failed:', error);
        alert('Checkout failed. Please try again.');
    }
}

