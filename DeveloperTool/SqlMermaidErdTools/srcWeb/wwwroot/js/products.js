// Products page functionality
document.addEventListener('DOMContentLoaded', async () => {
    await loadCatalog();
    await loadAllProducts();
    setupCategoryFilters();
});

// Load all products
async function loadAllProducts(category = null) {
    const container = document.getElementById('products-grid');
    if (!container) return;

    try {
        const url = category 
            ? `${API_BASE}/products/category/${encodeURIComponent(category)}`
            : `${API_BASE}/products`;
        
        const response = await fetch(url);
        const data = await response.json();
        
        const products = data.products || [];
        
        if (products.length > 0) {
            container.innerHTML = products.map(product => createProductCard(product)).join('');
        } else {
            container.innerHTML = '<p class="loading">No products available</p>';
        }
    } catch (error) {
        console.error('Failed to load products:', error);
        container.innerHTML = '<p class="loading">Failed to load products</p>';
    }
}

// Setup category filters
function setupCategoryFilters() {
    const filterButtons = document.querySelectorAll('.filter-btn');
    
    filterButtons.forEach(button => {
        button.addEventListener('click', async () => {
            // Update active state
            filterButtons.forEach(btn => btn.classList.remove('active'));
            button.classList.add('active');
            
            // Load products for category
            const category = button.dataset.category;
            if (category === 'all') {
                await loadAllProducts();
            } else {
                await loadAllProducts(category);
            }
        });
    });
}

